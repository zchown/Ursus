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
    in_check: bool = false,
    is_pv: bool = false,
    static_eval_valid: bool = false,
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

    pub inline fn getMove(self: PackedEntry) mv.EncodedMove {
        const move_u16: u16 = @truncate(self.data >> 48);
        return mv.EncodedMove.fromTTKey(move_u16);
    }
};

pub var stop_signal: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub const TT_BUCKET_SLOTS = 4;

const Slot = struct {
    lo: std.atomic.Value(u64),
    hi_x: std.atomic.Value(u64), // stores (hi ^ lo)

    inline fn loadPacked(self: *Slot) u128 {
        const lo = self.lo.load(.monotonic);
        const hi = self.hi_x.load(.monotonic) ^ lo;
        return (@as(u128, hi) << 64) | @as(u128, lo);
    }

    inline fn storePacked(self: *Slot, d: u128) void {
        const lo: u64 = @truncate(d);
        const hi: u64 = @truncate(d >> 64);
        self.lo.store(lo, .monotonic);
        self.hi_x.store(hi ^ lo, .monotonic);
    }

    inline fn clearSlot(self: *Slot) void {
        self.lo.store(0, .monotonic);
        self.hi_x.store(0, .monotonic);
    }
};

pub const Bucket = struct {
    entries: [TT_BUCKET_SLOTS]Slot,
    _pad: [(64 - TT_BUCKET_SLOTS * 16) % 64]u8, // 16B at 3 slots, 0B at 4

    pub fn init() Bucket {
        var b: Bucket = undefined;
        for (&b.entries) |*e| e.clearSlot();
        b._pad = @splat(0);
        return b;
    }
};

pub const TranspositionTable = struct {
    buckets: []Bucket,
    num_buckets: usize,
    age: std.atomic.Value(u8),

    pub fn init(allocator: std.mem.Allocator, size_in_mb: usize) !TranspositionTable {
        const raw_num_buckets = (size_in_mb * mb) / @sizeOf(Bucket);
        const num_buckets = std.math.floorPowerOfTwo(usize, raw_num_buckets);

        // alignedAlloc guarantees each bucket starts exactly on a cache line boundary
        const buckets = try allocator.alignedAlloc(Bucket, std.mem.Alignment.@"64", num_buckets);
        for (buckets) |*b| {
            b.* = Bucket.init();
        }

        return TranspositionTable{
            .buckets = buckets,
            .num_buckets = num_buckets,
            .age = std.atomic.Value(u8).init(0),
        };
    }

    pub fn deinit(self: *TranspositionTable, allocator: std.mem.Allocator) void {
        allocator.free(self.buckets);
    }

    pub inline fn clear(self: *TranspositionTable) void {
        for (self.buckets) |*bucket| {
            for (&bucket.entries) |*entry| {
                entry.clearSlot();
            }
        }
    }

    pub inline fn reset(self: *TranspositionTable) void {
        self.clear();
        self.age.store(0, .monotonic);
    }

    pub inline fn index(self: *TranspositionTable, hash: zob.ZobristKey) usize {
        return @as(usize, hash & (@as(zob.ZobristKey, self.num_buckets) - 1));
    }

    pub inline fn incrementAge(self: *TranspositionTable) void {
        const old_age = self.age.load(.monotonic);
        self.age.store(old_age +% 1, .monotonic);
    }

    pub inline fn setAge(self: *TranspositionTable, new_age: u8) void {
        self.age.store(new_age, .monotonic);
    }

    pub inline fn getAge(self: *TranspositionTable) u8 {
        return self.age.load(.monotonic);
    }

    pub inline fn prefetch(self: *TranspositionTable, hash: zob.ZobristKey) void {
        const idx = self.index(hash);
        const ptr = &self.buckets[idx];
        // Prefetching now pulls all 3 slots into L1 simultaneously
        @prefetch(ptr, .{
            .rw = .read,
            .locality = 1,
            .cache = .data,
        });
    }

    pub fn get(self: *TranspositionTable, hash: zob.ZobristKey) ?Entry {
        const bucket = &self.buckets[self.index(hash)];
        for (&bucket.entries) |*slot| {
            const packed_entry = PackedEntry{ .data = slot.loadPacked() };
            if (packed_entry.verify(hash) and packed_entry.getFlag() != .None) {
               const current_age = self.getAge();
                if (packed_entry.getAge() != current_age) {
                    const age_mask: u128 = @as(u128, 0xFF) << 90;
                    const refreshed = (packed_entry.data & ~age_mask) |
                        (@as(u128, current_age) << 90);
                    slot.storePacked(refreshed);
                }
                return packed_entry.unpack(hash);
            }

        }
        return null;
    }

    pub inline fn store(self: *TranspositionTable, entry: Entry) void {
        self.set(entry);
    }

    pub inline fn set(self: *TranspositionTable, entry: Entry) void {
        const idx = self.index(entry.hash);
        const bucket = &self.buckets[idx];
        const current_age = self.getAge();

        var best_move = entry.move;
        
        var match_idx: ?usize = null;
        var empty_idx: ?usize = null;
        
        var worst_idx: usize = 0;
        var worst_score: i32 = std.math.maxInt(i32);

        // 1. Scan the bucket for a match, an empty slot, and identify the worst entry
        for (&bucket.entries, 0..) |*slot, i| {
            const packed_data = slot.loadPacked();
            const packed_entry = PackedEntry{ .data = packed_data };
            const flag = packed_entry.getFlag();

            if (flag == .None) {
                empty_idx = i;
                continue;
            }

            if (packed_entry.verify(entry.hash)) {
                match_idx = i;
                if (best_move.isNull() and !packed_entry.getMove().isNull()) {
                    best_move = packed_entry.getMove();
                }
                break;
            }

            // 2. Score the entry to find the weakest link for collision handling
            var score: i32 = packed_entry.getDepth();
            const rel_age: u8 = current_age -% packed_entry.getAge();
            score -= 8 * @as(i32, @min(rel_age, 28)); // was: -256 for any age mismatch
            if (packed_entry.getIsPv()) score += 2;
            if (flag == .Exact) score += 1;

            if (score < worst_score) {
                worst_score = score;
                worst_idx = i;
            }
        }

        // 3. Determine the write target: Match > Empty > Worst
        const target_idx = match_idx orelse empty_idx orelse worst_idx;

        if (match_idx != null) {
            const old = PackedEntry{ .data = bucket.entries[target_idx].loadPacked() };
            const keep_old = entry.flag != .Exact and
                old.getAge() == current_age and
                @as(i32, old.getDepth()) >= @as(i32, entry.depth) + 4;
            if (keep_old) return; // deep data survives; move was already merged above
        }

        const new_packed = PackedEntry.pack(
            entry.hash,
            entry.eval,
            best_move.toTTKey(),
            entry.static_eval,
            entry.flag,
            entry.depth,
            current_age,
            entry.in_check,
            entry.is_pv,
            entry.static_eval_valid,
        );

        bucket.entries[target_idx].storePacked(@bitCast(new_packed));
    }

    pub fn getUsage(self: *TranspositionTable) struct { used: usize, total: usize } {
        var used: usize = 0;

        for (self.buckets) |*bucket| {
            for (&bucket.entries) |*item| {
                const packed_data = item.load(.monotonic);
                const packed_entry = PackedEntry{ .data = packed_data };
                if (packed_entry.getFlag() != .None) {
                    used += 1;
                }
            }
        }

        return .{ .used = used, .total = self.num_buckets * TT_BUCKET_SLOTS };
    }

    // pub fn getFillPermill(self: *const TranspositionTable) usize {
    //     const sample_size = @min(1000, self.num_buckets);
    //     var used: usize = 0;
    //
    //     var i: usize = 0;
    //     while (i < sample_size) : (i += 1) {
    //         const idx = (i * self.num_buckets) / sample_size;
    //         for (&self.buckets[idx].entries) |*item| {
    //             const packed_data = item.load(.monotonic);
    //             const packed_entry = PackedEntry{ .data = packed_data };
    //             if (packed_entry.getFlag() != .None) {
    //                 used += 1;
    //             }
    //         }
    //     }
    //
    //     return (used * 1000) / (sample_size * 1);
    // }
};

comptime {
    if (@sizeOf(u128) != 16) {
        @compileError("u128 must be 16 bytes for atomic operations");
    }
    if (@sizeOf(Bucket) != 64) {
        @compileError("Bucket must be exactly 64 bytes to align with CPU cache lines");
    }
}

