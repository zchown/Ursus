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

pub const Entry = struct {
    hash: zob.ZobristKey = 0,
    eval: i32 = 0,
    static_eval: i32 = 0,
    move: mv.EncodedMove = mv.EncodedMove.fromU32(0),
    flag: EstimationType = .None,
    depth: u8 = 0,
    age: u8 = 0,
    in_check: bool = false,          // Was the side to move in check at this node?
    is_pv: bool = false,             // Did this entry originate from a PV node?
    static_eval_valid: bool = false, // Is static_eval a real NNUE result (not TB placeholder)?
};

// Packed into 128 bits for atomic load/store:
//
//   bits   0-31:  hash key upper (bits 32-63 of zobrist)
//   bits  32-47:  eval (i16, clamped)
//   bits  48-63:  move (u16, compressed from u32)
//   bits  64-79:  static_eval (i16, clamped)
//   bits  80-81:  flag (EstimationType, 2 bits)
//   bits  82-89:  depth (u8)
//   bits  90-97:  age (u8)
//   bit   98:     in_check (1 bit)
//   bit   99:     is_pv (1 bit)
//   bit  100:     static_eval_valid (1 bit)
//   bits 101-127: hash key lower (bits 0-26 of zobrist, 27 bits)
//
// Hash verification: bits 0-31 (upper 32) + bits 101-127 (lower 27) = 59-bit key.
// This reduces false-positive collision probability 
pub const PackedEntry = extern struct {
    data: u128,

    pub inline fn pack(
        hash: u64,
        eval_: i32,
        move_u16: u16,
        static_eval: i32,
        flag: EstimationType,
        depth: u8,
        age: u8,
        in_check: bool,
        is_pv: bool,
        static_eval_valid: bool,
    ) PackedEntry {
        const hash_upper: u32 = @truncate(hash >> 32);
        const hash_lower: u27 = @truncate(hash);

        const clamped_eval: i16 = @intCast(@max(-32768, @min(32767, eval_)));
        const eval_bits: u16 = @bitCast(clamped_eval);

        const clamped_static: i16 = @intCast(@max(-32768, @min(32767, static_eval)));
        const static_bits: u16 = @bitCast(clamped_static);

        var packed_entry: u128 = 0;
        packed_entry |= @as(u128, hash_upper);                            // bits   0-31
        packed_entry |= @as(u128, eval_bits) << 32;                       // bits  32-47
        packed_entry |= @as(u128, move_u16) << 48;                        // bits  48-63
        packed_entry |= @as(u128, static_bits) << 64;                     // bits  64-79
        packed_entry |= @as(u128, @intFromEnum(flag)) << 80;              // bits  80-81
        packed_entry |= @as(u128, depth) << 82;                           // bits  82-89
        packed_entry |= @as(u128, age) << 90;                             // bits  90-97
        packed_entry |= @as(u128, @intFromBool(in_check)) << 98;          // bit   98
        packed_entry |= @as(u128, @intFromBool(is_pv)) << 99;             // bit   99
        packed_entry |= @as(u128, @intFromBool(static_eval_valid)) << 100; // bit  100
        packed_entry |= @as(u128, hash_lower) << 101;                     // bits 101-127

        return PackedEntry{ .data = packed_entry };
    }

    pub inline fn unpack(self: PackedEntry, full_hash: u64) Entry {
        const eval_bits: u16 = @truncate(self.data >> 32);
        const eval_: i16 = @bitCast(eval_bits);

        const move_u16: u16 = @truncate(self.data >> 48);

        const static_bits: u16 = @truncate(self.data >> 64);
        const static_eval: i16 = @bitCast(static_bits);

        const flag_bits: u2 = @truncate(self.data >> 80);
        const depth: u8 = @truncate(self.data >> 82);
        const age: u8 = @truncate(self.data >> 90);
        const in_check: bool = ((self.data >> 98) & 1) != 0;
        const is_pv: bool = ((self.data >> 99) & 1) != 0;
        const static_eval_valid: bool = ((self.data >> 100) & 1) != 0;

        return Entry{
            .hash = full_hash,
            .eval = @as(i32, eval_),
            .static_eval = @as(i32, static_eval),
            .move = mv.EncodedMove.fromTTKey(move_u16),
            .flag = @enumFromInt(flag_bits),
            .depth = depth,
            .age = age,
            .in_check = in_check,
            .is_pv = is_pv,
            .static_eval_valid = static_eval_valid,
        };
    }

    pub inline fn getHashKey(self: PackedEntry) u32 {
        return @truncate(self.data);
    }

    // 59-bit verification: upper 32 bits of zobrist (stored in bits 0-31) plus
    // lower 27 bits of zobrist (stored in bits 101-127).
    pub inline fn verify(self: PackedEntry, full_hash: u64) bool {
        const stored_upper: u32 = @truncate(self.data);
        const stored_lower: u27 = @truncate(self.data >> 101);
        const hash_upper: u32 = @truncate(full_hash >> 32);
        const hash_lower: u27 = @truncate(full_hash);
        return stored_upper == hash_upper and stored_lower == hash_lower;
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

    pub inline fn getInCheck(self: PackedEntry) bool {
        return ((self.data >> 98) & 1) != 0;
    }

    pub inline fn getIsPv(self: PackedEntry) bool {
        return ((self.data >> 99) & 1) != 0;
    }

    pub inline fn getStaticEvalValid(self: PackedEntry) bool {
        return ((self.data >> 100) & 1) != 0;
    }
};

pub var stop_signal: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub const TranspositionTable = struct {
    items: []std.atomic.Value(u128),
    size: usize,
    age: std.atomic.Value(u8),

    pub fn init(allocator: std.mem.Allocator, size_in_mb: usize) !TranspositionTable {
        const raw_num_entries = (size_in_mb * mb) / @sizeOf(u128);
        const num_entries: usize = std.math.floorPowerOfTwo(usize, raw_num_entries);

        const items = try allocator.alloc(std.atomic.Value(u128), num_entries);
        for (items) |*item| {
            item.* = std.atomic.Value(u128).init(0);
        }

        return TranspositionTable{
            .items = items,
            .size = num_entries,
            .age = std.atomic.Value(u8).init(0),
        };
    }

    pub fn deinit(self: *TranspositionTable, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
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

    pub inline fn incrementAge(self: *TranspositionTable) void {
        const old_age = self.age.load(.monotonic);
        self.age.store(old_age +% 1, .monotonic);
    }

    pub inline fn getAge(self: *TranspositionTable) u8 {
        return self.age.load(.monotonic);
    }

    pub inline fn set(self: *TranspositionTable, entry: Entry) void {
        const idx = self.index(entry.hash);

        const current_packed_data = self.items[idx].load(.acquire);
        const current_packed = PackedEntry{ .data = current_packed_data };

        const current_age = self.getAge();

        const hash_matches = current_packed.verify(entry.hash);
        const should_replace =
            entry.flag == .Exact or
            !hash_matches or
            current_packed.getDepth() <= entry.depth + 4 or
            current_packed.getAge() != current_age;

        if (should_replace) {
            const new_packed = PackedEntry.pack(
                entry.hash,
                entry.eval,
                entry.move.toTTKey(),
                entry.static_eval,
                entry.flag,
                entry.depth,
                current_age,
                entry.in_check,
                entry.is_pv,
                entry.static_eval_valid,
            );
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

    pub fn get(self: *TranspositionTable, hash: zob.ZobristKey) ?Entry {
        const idx = self.index(hash);

        const packed_data = self.items[idx].load(.acquire);
        const packed_entry = PackedEntry{ .data = packed_data };

        const flag = packed_entry.getFlag();

        if (packed_entry.verify(hash) and flag != .None) {
            return packed_entry.unpack(hash);
        }

        return null;
    }

    pub inline fn store(self: *TranspositionTable, entry: Entry) void {
        const idx = self.index(entry.hash);
        const current_age = self.getAge();

        const packed_entry = PackedEntry.pack(
            entry.hash,
            entry.eval,
            entry.move.toTTKey(),
            entry.static_eval,
            entry.flag,
            entry.depth,
            current_age,
            entry.in_check,
            entry.is_pv,
            entry.static_eval_valid,
        );

        self.items[idx].store(packed_entry.data, .release);
    }

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
            expected_entry.move.toTTKey(),
            expected_entry.static_eval,
            expected_entry.flag,
            expected_entry.depth,
            current_age,
            expected_entry.in_check,
            expected_entry.is_pv,
            expected_entry.static_eval_valid,
        );

        const new_packed = PackedEntry.pack(
            new_entry.hash,
            new_entry.eval,
            new_entry.move.toTTKey(),
            new_entry.static_eval,
            new_entry.flag,
            new_entry.depth,
            current_age,
            new_entry.in_check,
            new_entry.is_pv,
            new_entry.static_eval_valid,
        );

        const result = self.items[idx].cmpxchgStrong(
            expected_packed.data,
            new_packed.data,
            .acqRel,
            .acquire,
        );

        return result == null;
    }

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

    pub fn getFillPermill(self: *const TranspositionTable) usize {
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

comptime {
    if (@sizeOf(u128) != 16) {
        @compileError("u128 must be 16 bytes for atomic operations");
    }
    if (@sizeOf(PackedEntry) != 16) {
        @compileError("PackedEntry must be 16 bytes for atomic operations");
    }
}
