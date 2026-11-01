const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;
const mvs = root.moves;
const utils = root.utils;
const ZobristKey = root.zob.ZobristKey;

const GameState = brd.GameState;
const MoveGen = mvs.MoveGen;
const Move = mvs.Move;

pub const default_tt_size_mb = 64;
pub const default_probe = 8;

pub const PerftResult = struct {
    total: u64 = 0,
    captures: u64 = 0,
    en_passant: u64 = 0,
    castling: u64 = 0,
    promotions: u64 = 0,

    pub fn add(self: *PerftResult, other: PerftResult) void {
        self.total += other.total;
        self.captures += other.captures;
        self.en_passant += other.en_passant;
        self.castling += other.castling;
        self.promotions += other.promotions;
    }

    pub inline fn countLeaf(self: *PerftResult, m: Move) void {
        self.total += 1;
        if (m.isCapture()) self.captures += 1;
        if (m.isEP()) self.en_passant += 1;
        if (m.isCastle()) self.castling += 1;
        if (m.isPromo()) self.promotions += 1;
    }

    pub fn eql(self: PerftResult, other: PerftResult) bool {
        return std.meta.eql(self, other);
    }
};

pub const PerftTTEntry = struct {
    hash: ZobristKey = 0,
    result: PerftResult = .{},
    depth: u8 = 0,

    pub inline fn matches(self: PerftTTEntry, key: ZobristKey, depth: u8) bool {
        return self.depth == depth and self.hash == key;
    }

    pub inline fn isEmpty(self: PerftTTEntry) bool {
        return self.depth == 0;
    }
};

pub const TranspositionTable = struct {
    entries: []PerftTTEntry,
    mask: u64,

    pub fn init(allocator: std.mem.Allocator, size_in_mb: usize) !TranspositionTable {
        const raw = (size_in_mb * utils.mb) / @sizeOf(PerftTTEntry);
        if (raw < default_probe) return error.TableTooSmall;

        const num_entries = std.math.floorPowerOfTwo(usize, raw);
        const entries = try allocator.alloc(PerftTTEntry, num_entries);
        @memset(entries, .{});

        return .{
            .entries = entries,
            .mask = @as(u64, num_entries) - 1,
        };
    }

    pub fn deinit(self: *TranspositionTable, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        self.* = undefined;
    }

    pub fn clear(self: *TranspositionTable) void {
        @memset(self.entries, .{});
    }

    inline fn index(self: TranspositionTable, hash: ZobristKey) usize {
        return @intCast(hash & self.mask);
    }

    pub fn prefetch(self: *TranspositionTable, hash: ZobristKey) void {
        @prefetch(&self.entries[self.index(hash)], .{
            .rw = .read,
            .locality = 1,
            .cache = .data,
        });
    }

    pub fn get(self: *TranspositionTable, hash: ZobristKey, depth: u8) ?PerftResult {
        const base = self.index(hash);
        for (0..default_probe) |i| {
            const e = self.entries[(base + i) & self.mask];
            if (e.matches(hash, depth)) return e.result;
        }
        return null;
    }

    pub fn store(self: *TranspositionTable, hash: ZobristKey, depth: u8, result: PerftResult) void {
        const base = self.index(hash);

        var victim: usize = base;
        var victim_depth: u8 = std.math.maxInt(u8);

        for (0..default_probe) |i| {
            const idx = (base + i) & self.mask;
            const e = self.entries[idx];

            if (e.isEmpty() or e.matches(hash, depth)) {
                self.entries[idx] = .{ .hash = hash, .result = result, .depth = depth };
                return;
            }
            if (e.depth < victim_depth) {
                victim_depth = e.depth;
                victim = idx;
            }
        }

        self.entries[victim] = .{ .hash = hash, .result = result, .depth = depth };
    }
};

pub fn perft(mg: *const MoveGen, gs: *GameState, depth: u32) u64 {
    if (depth == 0) return 1;
    return perftNodes(mg, gs, depth);
}

fn perftNodes(mg: *const MoveGen, gs: *GameState, depth: u32) u64 {
    const info = mg.legalInfo(gs);
    const list = mg.generateMoves(gs, .all);

    var nodes: u64 = 0;

    if (depth == 1) {
        for (list.slice()) |m| {
            if (mg.isLegal(gs, m, &info)) nodes += 1;
        }
        return nodes;
    }

    for (list.slice()) |m| {
        if (!mg.isLegal(gs, m, &info)) continue;
        gs.makeMove(m);
        defer gs.unmakeMove(m);
        nodes += perftNodes(mg, gs, depth - 1);
    }
    return nodes;
}

pub fn perftDetailed(mg: *const MoveGen, gs: *GameState, depth: u32) PerftResult {
    if (depth == 0) return .{ .total = 1 };
    return perftDetailedInner(mg, gs, depth);
}

fn perftDetailedInner(mg: *const MoveGen, gs: *GameState, depth: u32) PerftResult {
    const info = mg.legalInfo(gs);
    const list = mg.generateMoves(gs, .all);

    var res = PerftResult{};

    for (list.slice()) |m| {
        if (!mg.isLegal(gs, m, &info)) continue;

        if (depth == 1) {
            res.countLeaf(m);
        } else {
            gs.makeMove(m);
            defer gs.unmakeMove(m);
            res.add(perftDetailedInner(mg, gs, depth - 1));
        }
    }
    return res;
}

pub fn perftTT(mg: *const MoveGen, gs: *GameState, depth: u32, tt: *TranspositionTable) PerftResult {
    if (depth == 0) return .{ .total = 1 };
    return perftTTInner(mg, gs, depth, tt);
}

fn perftTTInner(mg: *const MoveGen, gs: *GameState, depth: u32, tt: *TranspositionTable) PerftResult {
    const key = gs.cur_position.hash;
    const d: u8 = @intCast(depth);

    const cacheable = depth >= 2;
    if (cacheable) {
        if (tt.get(key, d)) |hit| return hit;
    }

    const info = mg.legalInfo(gs);
    const list = mg.generateMoves(gs, .all);

    var res = PerftResult{};

    for (list.slice()) |m| {
        if (!mg.isLegal(gs, m, &info)) continue;

        if (depth == 1) {
            res.countLeaf(m);
        } else {
            gs.makeMove(m);
            defer gs.unmakeMove(m);
            tt.prefetch(gs.cur_position.hash);
            res.add(perftTTInner(mg, gs, depth - 1, tt));
        }
    }

    if (cacheable) tt.store(key, d, res);
    return res;
}

pub const DivideEntry = struct {
    move: Move,
    nodes: u64,
};

pub fn divide(mg: *const MoveGen, gs: *GameState, depth: u32, chess960: bool, out: []DivideEntry) []DivideEntry {
    std.debug.assert(out.len >= mvs.max_moves);
    if (depth == 0) return out[0..0];

    const list = mg.generateLegal(gs, .all);
    var n: usize = 0;

    for (list.slice()) |m| {
        gs.makeMove(m);
        defer gs.unmakeMove(m);

        out[n] = .{ .move = m, .nodes = perft(mg, gs, depth - 1) };
        n += 1;
    }

    const ctx = UciOrder{ .gs = gs, .chess960 = chess960 };
    std.mem.sort(DivideEntry, out[0..n], ctx, UciOrder.lessThan);
    return out[0..n];
}

const UciOrder = struct {
    gs: *const GameState,
    chess960: bool,

    fn lessThan(self: UciOrder, a: DivideEntry, b: DivideEntry) bool {
        var buf_a: [5]u8 = undefined;
        var buf_b: [5]u8 = undefined;
        return std.mem.lessThan(
            u8,
            mvs.moveToUci(self.gs, a.move, self.chess960, &buf_a),
            mvs.moveToUci(self.gs, b.move, self.chess960, &buf_b),
        );
    }
};

pub fn divideTotal(entries: []const DivideEntry) u64 {
    var total: u64 = 0;
    for (entries) |e| total += e.nodes;
    return total;
}
