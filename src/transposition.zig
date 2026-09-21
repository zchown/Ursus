const std = @import("std");
const root = @import("root.zig");
const zob = root.zob;
const brd = root.brd;
const mv = root.moves;

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
    move: mv.Move = mv.Move.none,
    flag: EstimationType = .None,
    depth: u8 = 0,
    age: u8 = 0,
    in_check: bool = false,
    is_pv: bool = false,
    static_eval_valid: bool = false,
};

// 10-byte entry, 3 entries per 32-byte bucket, 2 buckets per 64-byte cache line.
//
//   key16          16 bits   low 16 bits of the zobrist key
//   depth8          8 bits
//   age_pv_bound8   8 bits   [0..4] age (5 bits) | [5..6] flag | [7] is_pv
//   move16         16 bits
//   value16        16 bits   search score, clamped to i16
//   eval16         16 bits   [1..15] static eval (i15) | [0] in_check
const AGE_BITS = 5;
pub const AGE_MASK: u8 = (1 << AGE_BITS) - 1;
const FLAG_SHIFT = AGE_BITS;
const PV_SHIFT = AGE_BITS + 2;

const STATIC_EVAL_LIMIT: i32 = (1 << 14) - 1;
const STATIC_EVAL_NONE: i16 = -(1 << 14);

inline fn ld(ptr: anytype) @TypeOf(ptr.*) {
    return @atomicLoad(@TypeOf(ptr.*), ptr, .monotonic);
}

inline fn st(ptr: anytype, value: @TypeOf(ptr.*)) void {
    @atomicStore(@TypeOf(ptr.*), ptr, value, .monotonic);
}

inline fn keyOf(hash: zob.ZobristKey) u16 {
    return @truncate(hash);
}

inline fn packAgePvBound(age: u8, flag: EstimationType, is_pv: bool) u8 {
    return (age & AGE_MASK) |
        (@as(u8, @intFromEnum(flag)) << FLAG_SHIFT) |
        (@as(u8, @intFromBool(is_pv)) << PV_SHIFT);
}

inline fn ageOf(apb: u8) u8 {
    return apb & AGE_MASK;
}

inline fn flagOf(apb: u8) EstimationType {
    return @enumFromInt(@as(u2, @truncate(apb >> FLAG_SHIFT)));
}

inline fn pvOf(apb: u8) bool {
    return (apb >> PV_SHIFT) & 1 != 0;
}

inline fn packStaticEval(static_eval: i32, valid: bool, in_check: bool) u16 {
    const v: i16 = if (valid)
        @intCast(std.math.clamp(static_eval, -STATIC_EVAL_LIMIT, STATIC_EVAL_LIMIT))
    else
        STATIC_EVAL_NONE;
    return (@as(u16, @bitCast(v)) << 1) | @intFromBool(in_check);
}

const StaticEvalInfo = struct { value: i32, valid: bool, in_check: bool };

inline fn unpackStaticEval(bits: u16) StaticEvalInfo {
    const v: i16 = @as(i16, @bitCast(bits)) >> 1;
    const valid = v != STATIC_EVAL_NONE;
    return .{
        .value = if (valid) v else 0,
        .valid = valid,
        .in_check = bits & 1 != 0,
    };
}

pub const TTEntry = extern struct {
    key16: u16,
    depth8: u8,
    age_pv_bound8: u8,
    move16: u16,
    value16: i16,
    eval16: u16,

    inline fn read(self: *const TTEntry, full_hash: zob.ZobristKey, apb: u8) Entry {
        const se = unpackStaticEval(ld(&self.eval16));
        return Entry{
            .hash = full_hash,
            .eval = ld(&self.value16),
            .static_eval = se.value,
            .move = mv.Move.fromU16(ld(&self.move16)),
            .flag = flagOf(apb),
            .depth = ld(&self.depth8),
            .age = ageOf(apb),
            .in_check = se.in_check,
            .is_pv = pvOf(apb),
            .static_eval_valid = se.valid,
        };
    }

    inline fn write(self: *TTEntry, key: u16, e: Entry, move: mv.Move, age: u8) void {
        const value: i16 = @intCast(std.math.clamp(e.eval, std.math.minInt(i16), std.math.maxInt(i16)));
        st(&self.key16, key);
        st(&self.depth8, e.depth);
        st(&self.age_pv_bound8, packAgePvBound(age, e.flag, e.is_pv));
        st(&self.move16, move.toU16());
        st(&self.value16, value);
        st(&self.eval16, packStaticEval(e.static_eval, e.static_eval_valid, e.in_check));
    }
};

pub var stop_signal: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub const TT_BUCKET_SLOTS = 3;

pub const Bucket = extern struct {
    entries: [TT_BUCKET_SLOTS]TTEntry,
    _pad: [32 - TT_BUCKET_SLOTS * @sizeOf(TTEntry)]u8,

    pub fn init() Bucket {
        return std.mem.zeroes(Bucket);
    }
};

pub const TranspositionTable = struct {
    buckets: []align(64) Bucket,
    num_buckets: usize,
    age: std.atomic.Value(u8),

    pub fn init(allocator: std.mem.Allocator, size_in_mb: usize) !TranspositionTable {
        const num_buckets = @max(1, (size_in_mb * mb) / @sizeOf(Bucket));

        const buckets = try allocator.alignedAlloc(Bucket, std.mem.Alignment.@"64", num_buckets);
        @memset(std.mem.sliceAsBytes(buckets), 0);

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
        @memset(std.mem.sliceAsBytes(self.buckets), 0);
    }

    pub inline fn reset(self: *TranspositionTable) void {
        self.clear();
        self.age.store(0, .monotonic);
    }

    pub inline fn index(self: *TranspositionTable, hash: zob.ZobristKey) usize {
        return @truncate((@as(u128, hash) * @as(u128, self.num_buckets)) >> 64);
    }

    pub inline fn incrementAge(self: *TranspositionTable) void {
        const old_age = self.age.load(.monotonic);
        self.age.store((old_age +% 1) & AGE_MASK, .monotonic);
    }

    pub inline fn setAge(self: *TranspositionTable, new_age: u8) void {
        self.age.store(new_age & AGE_MASK, .monotonic);
    }

    pub inline fn getAge(self: *TranspositionTable) u8 {
        return self.age.load(.monotonic);
    }

    pub inline fn prefetch(self: *TranspositionTable, hash: zob.ZobristKey) void {
        @prefetch(&self.buckets[self.index(hash)], .{
            .rw = .read,
            .locality = 1,
            .cache = .data,
        });
    }

    pub fn get(self: *TranspositionTable, hash: zob.ZobristKey) ?Entry {
        const bucket = &self.buckets[self.index(hash)];
        const key = keyOf(hash);
        for (&bucket.entries) |*slot| {
            if (ld(&slot.key16) != key) continue;
            const apb = ld(&slot.age_pv_bound8);
            if (flagOf(apb) == .None) continue;

            const result = slot.read(hash, apb);
            const current_age = self.getAge();
            if (ageOf(apb) != current_age) {
                st(&slot.age_pv_bound8, (apb & ~AGE_MASK) | current_age);
            }
            return result;
        }
        return null;
    }

    pub inline fn store(self: *TranspositionTable, entry: Entry) void {
        self.set(entry);
    }

    pub inline fn set(self: *TranspositionTable, entry: Entry) void {
        const bucket = &self.buckets[self.index(entry.hash)];
        const key = keyOf(entry.hash);
        const current_age = self.getAge();

        var best_move = entry.move;

        var match_idx: ?usize = null;
        var empty_idx: ?usize = null;

        var worst_idx: usize = 0;
        var worst_score: i32 = std.math.maxInt(i32);

        for (&bucket.entries, 0..) |*slot, i| {
            const apb = ld(&slot.age_pv_bound8);
            const flag = flagOf(apb);

            if (flag == .None) {
                empty_idx = i;
                continue;
            }

            if (ld(&slot.key16) == key) {
                match_idx = i;
                const old_move = mv.Move.fromU16(ld(&slot.move16));
                if (best_move.isNull() and !old_move.isNull()) {
                    best_move = old_move;
                }
                break;
            }

            var score: i32 = ld(&slot.depth8);
            const rel_age: u8 = (current_age -% ageOf(apb)) & AGE_MASK;
            score -= 8 * @as(i32, @min(rel_age, 28));
            if (pvOf(apb)) score += 2;
            if (flag == .Exact) score += 1;

            if (score < worst_score) {
                worst_score = score;
                worst_idx = i;
            }
        }

        const target_idx = match_idx orelse empty_idx orelse worst_idx;
        const target = &bucket.entries[target_idx];

        if (match_idx != null) {
            const keep_old = entry.flag != .Exact and
                ageOf(ld(&target.age_pv_bound8)) == current_age and
                @as(i32, ld(&target.depth8)) >= @as(i32, entry.depth) + 4;
            if (keep_old) return; 
        }

        target.write(key, entry, best_move, current_age);
    }

    pub fn getUsage(self: *TranspositionTable) struct { used: usize, total: usize } {
        var used: usize = 0;

        for (self.buckets) |*bucket| {
            for (&bucket.entries) |*slot| {
                if (flagOf(ld(&slot.age_pv_bound8)) != .None) {
                    used += 1;
                }
            }
        }

        return .{ .used = used, .total = self.num_buckets * TT_BUCKET_SLOTS };
    }
};

comptime {
    if (@sizeOf(TTEntry) != 10) {
        @compileError("TTEntry must be exactly 10 bytes");
    }
    if (@sizeOf(Bucket) != 32) {
        @compileError("Bucket must be exactly 32 bytes (two per 64-byte cache line)");
    }
}
