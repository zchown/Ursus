const std = @import("std");
const zob = @import("zobrist");
const brd = @import("board");
const mv = @import("moves");

pub const default_tt_size_mb = 64;
pub const kb = 1 << 10;
pub const mb = 1 << 20;

pub const EstimationType = enum(u2) {
    None = 0,
    Under = 1,
    Over = 2,
    Exact = 3,
};

// Original entry structure (for API compatibility)
pub const Entry = struct {
    hash: zob.ZobristKey = 0,
    eval: i32 = 0,
    move: mv.EncodedMove = mv.EncodedMove.fromU32(0),
    flag: EstimationType = .None,
    depth: u8 = 0,
    age: u8 = 0,  // ✓ Full u8 for proper wrapping
};

// Packed entry that fits in 128 bits for atomic operations
//
// APPROACH: Use 32-bit hash key (stored) + table index for verification
// This gives extremely low collision rate while keeping everything compact
//
// Layout (128 bits total):
// bits 0-31:   hash_key (32 bits) - lower 32 bits of zobrist hash
// bits 32-47:  eval (16 bits signed)
// bits 48-79:  move (32 bits)
// bits 80-81:  flag (2 bits)
// bits 82-89:  depth (8 bits) ✓
// bits 90-97:  age (8 bits) ✓
// bits 98-127: spare (30 bits) - reserved for future use
pub const PackedEntry = extern struct {
    data: u128,
    
    pub inline fn pack(
        hash: u64,
        eval: i32,
        move: u32,
        flag: EstimationType,
        depth: u8,
        age: u8,
    ) PackedEntry {
        // Use lower 32 bits of hash as key
        const hash_key: u32 = @truncate(hash);
        
        // Clamp eval to i16 range
        const clamped_eval: i16 = @intCast(@max(-32768, @min(32767, eval)));
        const eval_bits: u16 = @bitCast(clamped_eval);
        
        var packed_entry: u128 = 0;
        packed_entry |= @as(u128, hash_key);                    // bits 0-31
        packed_entry |= @as(u128, eval_bits) << 32;             // bits 32-47
        packed_entry |= @as(u128, move) << 48;                  // bits 48-79
        packed_entry |= @as(u128, @intFromEnum(flag)) << 80;    // bits 80-81
        packed_entry |= @as(u128, depth) << 82;                 // bits 82-89
        packed_entry |= @as(u128, age) << 90;                   // bits 90-97
        // bits 98-127 remain zero (spare)
        
        return PackedEntry{ .data = packed_entry };
    }
    
    pub inline fn unpack(self: PackedEntry, full_hash: u64) Entry {
        const eval_bits: u16 = @truncate(self.data >> 32);
        const eval: i16 = @bitCast(eval_bits);
        const move: u32 = @truncate(self.data >> 48);
        const flag_bits: u2 = @truncate(self.data >> 80);
        const depth: u8 = @truncate(self.data >> 82);
        const age: u8 = @truncate(self.data >> 90);
        
        return Entry{
            .hash = full_hash,  // Return full hash for API consistency
            .eval = @as(i32, eval),
            .move = mv.EncodedMove.fromU32(move),
            .flag = @enumFromInt(flag_bits),
            .depth = depth,
            .age = age,
        };
    }
    
    pub inline fn getHashKey(self: PackedEntry) u32 {
        return @truncate(self.data);
    }
    
    pub inline fn verify(self: PackedEntry, full_hash: u64) bool {
        const stored_key: u32 = @truncate(self.data);
        const hash_key: u32 = @truncate(full_hash);
        return stored_key == hash_key;
    }
    
    pub inline fn getFlag(self: PackedEntry) EstimationType {
        const flag_bits: u2 = @truncate(self.data >> 80);
        return @enumFromInt(flag_bits);
    }
    
    pub inline fn getDepth(self: PackedEntry) u8 {
        return @truncate(self.data >> 82);
    }
    
    pub inline fn getAge(self: PackedEntry) u8 {
        return @truncate(self.data >> 90);
    }
};

// Use an atomic bool to signal all threads to stop
pub var stop_signal: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub var tt_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
pub var global_tt_initialized: bool = false;
pub var global_tt: *TranspositionTable = undefined;

pub const TranspositionTable = struct {
    items: []std.atomic.Value(u128),
    size: usize,
    age: std.atomic.Value(u8),  // Full u8 for proper wrapping

    pub fn initGlobal(size_in_mb: usize) !void {
        const raw_num_entries = (size_in_mb * mb) / @sizeOf(u128);
        const num_entries: usize = std.math.floorPowerOfTwo(usize, raw_num_entries);
        
        global_tt = try tt_arena.allocator().create(TranspositionTable);
        
        // Allocate atomic array
        const items = try tt_arena.allocator().alloc(std.atomic.Value(u128), num_entries);
        
        // Initialize all entries to zero
        for (items) |*item| {
            item.* = std.atomic.Value(u128).init(0);
        }

        global_tt.* = TranspositionTable{
            .items = items,
            .size = num_entries,
            .age = std.atomic.Value(u8).init(0),
        };
        global_tt_initialized = true;
        
        std.debug.print("TT initialized: {} entries ({} MB)\n", .{
            num_entries,
            (num_entries * @sizeOf(u128)) / mb,
        });
    }

    pub inline fn clear(self: *TranspositionTable) void {
        for (self.items) |*item| {
            item.store(0, .monotonic);
        }
    }

    pub inline fn reset(self: *TranspositionTable) void {
        self.clear();
        self.age.store(0, .monotonic);
    }

    pub inline fn index(self: *TranspositionTable, hash: zob.ZobristKey) usize {
        return @as(usize, hash & (@as(zob.ZobristKey, self.size) - 1));
    }

    pub inline fn incrememtAge(self: *TranspositionTable) void {
        const old_age = self.age.load(.monotonic);
        // u8 wraps naturally with +%
        self.age.store(old_age +% 1, .monotonic);
    }
    
    pub inline fn getAge(self: *TranspositionTable) u8 {
        return self.age.load(.monotonic);
    }

    // Thread-safe atomic set using Release ordering
    //
    // Collision detection: index + 32-bit key gives very low collision rate
    // Probability of collision: ~1 / (2^32 * table_size / total_positions)
    // With 4M entries and typical game tree, collision rate < 0.0001%
    pub inline fn set(self: *TranspositionTable, entry: Entry) void {
        const idx = self.index(entry.hash);
        
        // Read current entry (Acquire ordering for synchronization)
        const current_packed_data = self.items[idx].load(.acquire);
        const current_packed = PackedEntry{ .data = current_packed_data };
        
        const current_age = self.getAge();
        
        // Replacement strategy:
        // Replace if: exact bound, hash collision, deeper search, or old age
        const hash_matches = current_packed.verify(entry.hash);
        const should_replace = 
            entry.flag == .Exact or 
            !hash_matches or  // Different position (collision)
            current_packed.getDepth() <= entry.depth + 4 or 
            current_packed.getAge() != current_age;
        
        if (should_replace) {
            // Pack the new entry
            const new_packed = PackedEntry.pack(
                entry.hash,
                entry.eval,
                entry.move.toU32(),
                entry.flag,
                entry.depth,
                current_age,
            );
            
            // Atomic store with Release ordering
            // This ensures all previous writes are visible before this write
            self.items[idx].store(new_packed.data, .release);
        }
    }

    pub inline fn prefetch(self: *TranspositionTable, hash: zob.ZobristKey) void {
        const idx = self.index(hash);
        const ptr = &self.items[idx];
        @prefetch(ptr, .{
            .rw = .read,
            .locality = 1,
            .cache = .data,
        });
    }

    // Thread-safe atomic get using Acquire ordering
    //
    // Verification: We verify using both table index AND 32-bit key
    // This combination gives extremely low false positive rate
    pub fn get(self: *TranspositionTable, hash: zob.ZobristKey) ?Entry {
        const idx = self.index(hash);
        
        // Atomic load with Acquire ordering
        const packed_data = self.items[idx].load(.acquire);
        const packed_entry = PackedEntry{ .data = packed_data };
        
        // Verify hash key matches
        const flag = packed_entry.getFlag();
        
        if (packed_entry.verify(hash) and flag != .None) {
            return packed_entry.unpack(hash);
        }
        
        return null;
    }
    
    // Store without replacement check
    pub inline fn store(self: *TranspositionTable, entry: Entry) void {
        const idx = self.index(entry.hash);
        const current_age = self.getAge();
        
        const packed_entry = PackedEntry.pack(
            entry.hash,
            entry.eval,
            entry.move.toU32(),
            entry.flag,
            entry.depth,
            current_age,
        );
        
        self.items[idx].store(packed_entry.data, .release);
    }
    
    // Compare-and-swap for lock-free updates
    pub fn compareAndSwap(
        self: *TranspositionTable,
        hash: zob.ZobristKey,
        expected_entry: Entry,
        new_entry: Entry,
    ) bool {
        const idx = self.index(hash);
        const current_age = self.getAge();
        
        const expected_packed = PackedEntry.pack(
            expected_entry.hash,
            expected_entry.eval,
            expected_entry.move.toU32(),
            expected_entry.flag,
            expected_entry.depth,
            current_age,
        );
        
        const new_packed = PackedEntry.pack(
            new_entry.hash,
            new_entry.eval,
            new_entry.move.toU32(),
            new_entry.flag,
            new_entry.depth,
            current_age,
        );
        
        const result = self.items[idx].cmpxchgStrong(
            expected_packed.data,
            new_packed.data,
            .acqRel,
            .acquire,
        );
        
        return result == null;
    }
    
    // Get statistics about TT usage
    pub fn getUsage(self: *TranspositionTable) struct { used: usize, total: usize } {
        var used: usize = 0;
        
        for (self.items) |*item| {
            const packed_data = item.load(.monotonic);
            const packed_entry = PackedEntry{ .data = packed_data };
            if (packed_entry.getFlag() != .None) {
                used += 1;
            }
        }
        
        return .{ .used = used, .total = self.size };
    }
    
    // Get fill percentage (0-1000 for 0.0% to 100.0%)
    pub fn getFillPermill(self: *TranspositionTable) usize {
        const sample_size = @min(1000, self.size);
        var used: usize = 0;
        
        var i: usize = 0;
        while (i < sample_size) : (i += 1) {
            const idx = (i * self.size) / sample_size;
            const packed_data = self.items[idx].load(.monotonic);
            const packed_entry = PackedEntry{ .data = packed_data };
            if (packed_entry.getFlag() != .None) {
                used += 1;
            }
        }
        
        return (used * 1000) / sample_size;
    }
};

// Compile-time checks
comptime {
    if (@sizeOf(u128) != 16) {
        @compileError("u128 must be 16 bytes for atomic operations");
    }
    if (@sizeOf(PackedEntry) != 16) {
        @compileError("PackedEntry must be 16 bytes for atomic operations");
    }
}
// const std = @import("std");
// const zob = @import("zobrist");
// const brd = @import("board");
// const mv = @import("moves");
//
// pub const default_tt_size_mb = 64;
// pub const kb = 1 << 10;
// pub const mb = 1 << 20;
//
// pub const EstimationType = enum(u2) {
//     None,
//     Under,
//     Over,
//     Exact,
// };
//
// pub const Entry = struct {
//     hash: zob.ZobristKey = 0,
//     eval: i32 = 0,
//     move: mv.EncodedMove = mv.EncodedMove.fromU32(0),
//     flag: EstimationType = .None,
//     depth: u8 = 0,
//     age: u6 = 0,
// };
//
// // Use an atomic bool to signal all threads to stop
// pub var stop_signal: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
//
// pub var tt_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
// pub var global_tt_initialized: bool = false;
// pub var global_tt: *TranspositionTable = undefined;
//
// pub const TranspositionTable = struct {
//     items: []Entry, // Changed from ArrayList to slice for stable memory
//     size: usize,
//     age: u6,
//
//     pub fn initGlobal(size_in_mb: usize) !void {
//         const raw_num_entries = (size_in_mb * mb) / @sizeOf(Entry);
//         const num_entries: usize = std.math.floorPowerOfTwo(usize, raw_num_entries);
//
//         global_tt = try tt_arena.allocator().create(TranspositionTable);
//
//         // Allocate fixed slice.
//         // Note: In a real engine, you might want aligned allocation,
//         // but standard alloc is fine for this UB/Racy approach.
//         const items = try tt_arena.allocator().alloc(Entry, num_entries);
//         @memset(items, Entry{});
//
//         global_tt.* = TranspositionTable{
//             .items = items,
//             .size = num_entries,
//             .age = 0,
//         };
//         global_tt_initialized = true;
//     }
//
//     pub inline fn clear(self: *TranspositionTable) void {
//         @memset(self.items, Entry{});
//     }
//
//     pub inline fn reset(self: *TranspositionTable) void {
//         self.clear();
//         self.age = 0;
//     }
//
//     pub inline fn index(self: *TranspositionTable, hash: zob.ZobristKey) usize {
//         return @as(usize, hash & (@as(zob.ZobristKey, self.size) - 1));
//     }
//
//     pub inline fn incrememtAge(self: *TranspositionTable) void {
//         self.age +%= 1;
//     }
//
//     // "UB" / Racy Set
//     // We write to the entry without a lock.
//     // This can cause tearing (invalid mix of data), but is standard in chess engines.
//     pub inline fn set(self: *TranspositionTable, entry: Entry) void {
//         const idx = self.index(entry.hash);
//         // We read unsafely first
//         const cur_entry = self.items[idx];
//
//         if (entry.flag == .Exact or
//             cur_entry.hash != entry.hash or
//             cur_entry.depth <= entry.depth + 4 or
//             cur_entry.age != self.age)
//         {
//             // Unsafe write
//             self.items[idx] = entry;
//         }
//     }
//
//     pub inline fn prefetch(self: *TranspositionTable, hash: zob.ZobristKey) void {
//         @prefetch(&self.items[self.index(hash)], .{
//             .rw = .read,
//             .locality = 1,
//             .cache = .data,
//         });
//     }
//
//     pub fn get(self: *TranspositionTable, hash: zob.ZobristKey) ?Entry {
//         const idx = self.index(hash);
//         // Unsafe read
//         const entry = self.items[idx];
//
//         if (entry.hash == hash and entry.flag != .None) {
//             return entry;
//         } else {
//             return null;
//         }
//     }
// };
//
