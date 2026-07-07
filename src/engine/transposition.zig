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

pub inline fn keyOf(hash: u64) u16 {
    return @truncate(hash >> 48);
}

inline fn clampEval(x: i32) i16 {
    return @intCast(@max(-32768, @min(32767, x)));
}

pub const PackedEntry = extern struct {
    key: u16 = 0,
    score: i16 = 0,
    static_eval: i16 = 0,
    move: u16 = 0,
    depth: u8 = 0,
    meta: u8 = 0,
    age: u8 = 0,

    inline fn makeMeta(flag: EstimationType, pv: bool, in_check: bool, sev: bool) u8 {
        var m: u8 = @intFromEnum(flag);
        m |= @as(u8, @intFromBool(pv)) << 2;
        m |= @as(u8, @intFromBool(in_check)) << 3;
        m |= @as(u8, @intFromBool(sev)) << 4;
        return m;
    }

    pub inline fn bound(self: PackedEntry) EstimationType {
        return @enumFromInt(@as(u2, @truncate(self.meta)));
    }

    pub inline fn isPv(self: PackedEntry) bool {
        return (self.meta >> 2) & 1 != 0;
    }

    pub inline fn inCheck(self: PackedEntry) bool {
        return (self.meta >> 3) & 1 != 0;
    }

    pub inline fn staticEvalValid(self: PackedEntry) bool {
        return (self.meta >> 4) & 1 != 0;
    }

    pub inline fn getMove(self: PackedEntry) mv.EncodedMove {
        return mv.EncodedMove.fromTTKey(self.move);
    }

    // 16-bit verification against the top bits of the query hash.
    pub inline fn verify(self: PackedEntry, full_hash: u64) bool {
        return self.key == keyOf(full_hash);
    }

    pub inline fn fromEntry(entry: Entry, move_u16: u16, age: u8) PackedEntry {
        return .{
            .key = keyOf(entry.hash),
            .score = clampEval(entry.eval),
            .static_eval = clampEval(entry.static_eval),
            .move = move_u16,
            .depth = entry.depth,
            .meta = makeMeta(entry.flag, entry.is_pv, entry.in_check, entry.static_eval_valid),
            .age = age,
        };
    }

    pub inline fn toEntry(self: PackedEntry, full_hash: u64) Entry {
        return .{
            .hash = full_hash,
            .eval = @as(i32, self.score),
            .static_eval = @as(i32, self.static_eval),
            .move = mv.EncodedMove.fromTTKey(self.move),
            .flag = self.bound(),
            .depth = self.depth,
            .age = self.age,
            .in_check = self.inCheck(),
            .is_pv = self.isPv(),
            .static_eval_valid = self.staticEvalValid(),
        };
    }

    pub inline fn atomicRead(e: *const PackedEntry) PackedEntry {
        const key = @atomicLoad(u16, &e.key, .acquire);
        return .{
            .key = key,
            .score = @atomicLoad(i16, &e.score, .monotonic),
            .static_eval = @atomicLoad(i16, &e.static_eval, .monotonic),
            .move = @atomicLoad(u16, &e.move, .monotonic),
            .depth = @atomicLoad(u8, &e.depth, .monotonic),
            .meta = @atomicLoad(u8, &e.meta, .monotonic),
            .age = @atomicLoad(u8, &e.age, .monotonic),
        };
    }

    pub inline fn atomicWrite(e: *PackedEntry, v: PackedEntry) void {
        @atomicStore(i16, &e.score, v.score, .monotonic);
        @atomicStore(i16, &e.static_eval, v.static_eval, .monotonic);
        @atomicStore(u16, &e.move, v.move, .monotonic);
        @atomicStore(u8, &e.depth, v.depth, .monotonic);
        @atomicStore(u8, &e.meta, v.meta, .monotonic);
        @atomicStore(u8, &e.age, v.age, .monotonic);
        @atomicStore(u16, &e.key, v.key, .release); // publish last
    }
};

pub var stop_signal: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

// 5 slots * 12 bytes = 60 bytes, + 4 bytes padding = exactly one 64-byte line.
pub const TT_BUCKET_SLOTS = 5;

pub const Bucket = extern struct {
    entries: [TT_BUCKET_SLOTS]PackedEntry,
    _pad: u32 = 0,

    pub fn init() Bucket {
        return .{ .entries = [_]PackedEntry{.{}} ** TT_BUCKET_SLOTS, ._pad = 0 };
    }
};

pub const TranspositionTable = struct {
    buckets: []Bucket,
    num_buckets: usize,
    age: std.atomic.Value(u8),

    pub fn init(allocator: std.mem.Allocator, size_in_mb: usize) !TranspositionTable {
        const raw_num_buckets = (size_in_mb * mb) / @sizeOf(Bucket);
        const num_buckets = std.math.floorPowerOfTwo(usize, raw_num_buckets);

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
        const empty = PackedEntry{};
        for (self.buckets) |*bucket| {
            for (&bucket.entries) |*entry| {
                PackedEntry.atomicWrite(entry, empty);
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
        @prefetch(ptr, .{
            .rw = .read,
            .locality = 1,
            .cache = .data,
        });
    }

    pub fn get(self: *TranspositionTable, hash: zob.ZobristKey) ?Entry {
        const idx = self.index(hash);
        const bucket = &self.buckets[idx];

        for (&bucket.entries) |*atomic_entry| {
            const pe = PackedEntry.atomicRead(atomic_entry);
            if (pe.bound() != .None and pe.verify(hash)) {
                return pe.toEntry(hash);
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

        // 1. Scan for a match, an empty slot, and the weakest existing entry.
        for (&bucket.entries, 0..) |*atomic_entry, i| {
            const pe = PackedEntry.atomicRead(atomic_entry);
            const flag = pe.bound();

            if (flag == .None) {
                empty_idx = i;
                continue;
            }

            if (pe.verify(entry.hash)) {
                match_idx = i;
                if (best_move.isNull() and !pe.getMove().isNull()) {
                    best_move = pe.getMove();
                }
                break;
            }

            var score: i32 = pe.depth;
            if (pe.age != current_age) score -= 256; // Nuke old searches
            if (pe.isPv()) score += 2;
            if (flag == .Exact) score += 1;

            if (score < worst_score) {
                worst_score = score;
                worst_idx = i;
            }
        }

        const target_idx = match_idx orelse empty_idx orelse worst_idx;

        const new_pe = PackedEntry.fromEntry(entry, best_move.toTTKey(), current_age);
        PackedEntry.atomicWrite(&bucket.entries[target_idx], new_pe);
    }

    pub fn compareAndSwap(
        self: *TranspositionTable,
        hash: zob.ZobristKey,
        expected_entry: Entry,
        new_entry: Entry,
    ) bool {
        const idx = self.index(hash);
        const bucket = &self.buckets[idx];
        const current_age = self.getAge();

        const expected_pe = PackedEntry.fromEntry(expected_entry, expected_entry.move.toTTKey(), current_age);
        const new_pe = PackedEntry.fromEntry(new_entry, new_entry.move.toTTKey(), current_age);

        for (&bucket.entries) |*atomic_entry| {
            const cur = PackedEntry.atomicRead(atomic_entry);
            if (std.meta.eql(cur, expected_pe)) {
                PackedEntry.atomicWrite(atomic_entry, new_pe);
                return true;
            }
        }

        return false;
    }

    pub fn getUsage(self: *TranspositionTable) struct { used: usize, total: usize } {
        var used: usize = 0;

        for (self.buckets) |*bucket| {
            for (&bucket.entries) |*item| {
                const pe = PackedEntry.atomicRead(item);
                if (pe.bound() != .None) {
                    used += 1;
                }
            }
        }

        return .{ .used = used, .total = self.num_buckets * TT_BUCKET_SLOTS };
    }

    pub fn getFillPermill(self: *const TranspositionTable) usize {
        const sample_size = @min(1000, self.num_buckets);
        var used: usize = 0;

        var i: usize = 0;
        while (i < sample_size) : (i += 1) {
            const idx = (i * self.num_buckets) / sample_size;
            for (&self.buckets[idx].entries) |*item| {
                const pe = PackedEntry.atomicRead(item);
                if (pe.bound() != .None) {
                    used += 1;
                }
            }
        }

        return (used * 1000) / (sample_size * TT_BUCKET_SLOTS);
    }
};

comptime {
    if (@sizeOf(PackedEntry) != 12) {
        @compileError("PackedEntry must be 12 bytes");
    }
    if (@sizeOf(Bucket) != 64) {
        @compileError("Bucket must be exactly 64 bytes to align with CPU cache lines");
    }
}
