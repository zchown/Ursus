const std = @import("std");
const brd = @import("board");
const zob = @import("zobrist");

inline fn pieceKey(color: brd.Color, piece: brd.Pieces, sq: usize) u64 {
    return zob.ZobristKeys.pieceKeys(color, piece, sq);
}

inline fn sideKey() u64 {
    return zob.ZobristKeys.sideKeys(.White) ^ zob.ZobristKeys.sideKeys(.Black);
}

const table_size = 8192;

inline fn h1(key: u64) usize {
    return @intCast(key & 0x1fff);
}

inline fn h2(key: u64) usize {
    return @intCast((key >> 16) & 0x1fff);
}

const Tables = struct {
    keys: [table_size]u64,
    moves: [table_size]u16,
    between: [64][64]u64,
};

const tables: Tables = blk: {
    @setEvalBranchQuota(50_000_000);
    break :blk build();
};

const Dir = struct { df: i32, dr: i32 };
const orth_dirs = [_]Dir{ .{ .df = 1, .dr = 0 }, .{ .df = -1, .dr = 0 }, .{ .df = 0, .dr = 1 }, .{ .df = 0, .dr = -1 } };
const diag_dirs = [_]Dir{ .{ .df = 1, .dr = 1 }, .{ .df = 1, .dr = -1 }, .{ .df = -1, .dr = 1 }, .{ .df = -1, .dr = -1 } };
const knight_jumps = [_]Dir{
    .{ .df = 1, .dr = 2 },   .{ .df = 2, .dr = 1 },   .{ .df = 2, .dr = -1 },  .{ .df = 1, .dr = -2 },
    .{ .df = -1, .dr = -2 }, .{ .df = -2, .dr = -1 }, .{ .df = -2, .dr = 1 },  .{ .df = -1, .dr = 2 },
};

fn onBoard(f: i32, r: i32) bool {
    return f >= 0 and f < 8 and r >= 0 and r < 8;
}

fn bit(f: i32, r: i32) u64 {
    return @as(u64, 1) << @intCast(r * 8 + f);
}

fn slide(sq: usize, dirs: []const Dir) u64 {
    const f0: i32 = @intCast(sq % 8);
    const r0: i32 = @intCast(sq / 8);
    var bb: u64 = 0;
    for (dirs) |d| {
        var f = f0 + d.df;
        var r = r0 + d.dr;
        while (onBoard(f, r)) : ({
            f += d.df;
            r += d.dr;
        }) bb |= bit(f, r);
    }
    return bb;
}

fn step(sq: usize, dirs: []const Dir) u64 {
    const f0: i32 = @intCast(sq % 8);
    const r0: i32 = @intCast(sq / 8);
    var bb: u64 = 0;
    for (dirs) |d| {
        if (onBoard(f0 + d.df, r0 + d.dr)) bb |= bit(f0 + d.df, r0 + d.dr);
    }
    return bb;
}

fn emptyBoardAttacks(piece: brd.Pieces, sq: usize) u64 {
    return switch (piece) {
        .Knight => step(sq, &knight_jumps),
        .Bishop => slide(sq, &diag_dirs),
        .Rook => slide(sq, &orth_dirs),
        .Queen => slide(sq, &diag_dirs) | slide(sq, &orth_dirs),
        .King => step(sq, &orth_dirs) | step(sq, &diag_dirs),
        else => 0,
    };
}

fn build() Tables {
    var t: Tables = .{
        .keys = @splat(0),
        .moves = @splat(0),
        .between = std.mem.zeroes([64][64]u64),
    };

    const all_dirs = orth_dirs ++ diag_dirs;
    for (0..64) |a| {
        const fa: i32 = @intCast(a % 8);
        const ra: i32 = @intCast(a / 8);
        for (all_dirs) |d| {
            var gap: u64 = 0;
            var f = fa + d.df;
            var r = ra + d.dr;
            while (onBoard(f, r)) : ({
                f += d.df;
                r += d.dr;
            }) {
                t.between[a][@intCast(r * 8 + f)] = gap;
                gap |= bit(f, r);
            }
        }
    }

    const colors = [_]brd.Color{ .White, .Black };
    const pieces = [_]brd.Pieces{ .Knight, .Bishop, .Rook, .Queen, .King };

    var count: usize = 0;
    for (colors) |c| {
        for (pieces) |p| {
            for (0..64) |s1| {
                const attacks = emptyBoardAttacks(p, s1);
                for (s1 + 1..64) |s2| {
                    if (attacks & (@as(u64, 1) << @intCast(s2)) == 0) continue;

                    var key: u64 = pieceKey(c, p, s1) ^ pieceKey(c, p, s2) ^ sideKey();
                    var mv: u16 = @intCast(s1 | (s2 << 6));
                    var slot = h1(key);
                    var kicks: usize = 0;
                    while (true) : (kicks += 1) {
                        std.mem.swap(u64, &t.keys[slot], &key);
                        std.mem.swap(u16, &t.moves[slot], &mv);
                        if (mv == 0) break; 
                        if (kicks > table_size) @compileError("cuckoo: insertion cycle, Zobrist keys collide on h1/h2");
                        slot = if (slot == h1(key)) h2(key) else h1(key); 
                    }
                    count += 1;
                }
            }
        }
    }
    if (count != 3668) @compileError("cuckoo: expected 3668 reversible moves");
    return t;
}

pub inline fn reversiblePlies(board: *const brd.Board) usize {
    return @min(@as(usize, board.game_state.halfmove_clock), board.history.history_count);
}

pub fn upcomingRepetition(board: *const brd.Board, ply: usize, max_lookback: usize) bool {
    const end = @min(reversiblePlies(board), max_lookback);
    if (end < 3) return false;

    const count = board.history.history_count;
    const hist = board.history.history_list[0..count];
    const side = sideKey();
    const original = board.game_state.zobrist;

    var other: u64 = original ^ hist[count - 1].zobrist ^ side;

    var i: usize = 3;
    while (i <= end) : (i += 2) {
        other ^= hist[count - (i - 1)].zobrist ^ hist[count - i].zobrist ^ side;
        if (other != 0) continue;

        const target = hist[count - i].zobrist;
        const move_key = original ^ target;
        var slot = h1(move_key);
        if (tables.keys[slot] != move_key) {
            slot = h2(move_key);
            if (tables.keys[slot] != move_key) continue;
        }
        const mv = tables.moves[slot];
        if (mv == 0) continue;

        const s1: usize = mv & 63;
        const s2: usize = mv >> 6;
        if (tables.between[s1][s2] & board.occupancy() != 0) continue;

        if (i <= ply) return true;

        var k: usize = 2;
        while (i + k <= end) : (k += 2) {
            if (hist[count - i - k].zobrist == target) return true;
        }
    }
    return false;
}
