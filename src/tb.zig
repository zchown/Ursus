const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;
const mvs = root.moves;

const c = @cImport({
    @cInclude("tbprobe.h");
});

// Wrapper around Fathom's TBProbe

pub const TB_LOSS: u32 = 0;
pub const TB_BLESSED_LOSS: u32 = 1;
pub const TB_DRAW: u32 = 2;
pub const TB_CURSED_WIN: u32 = 3;
pub const TB_WIN: u32 = 4;
pub const TB_RESULT_FAILED: u32 = 0xFFFFFFFF;

comptime {
    std.debug.assert(@intFromEnum(brd.CastleValues.WhiteKingside) == c.TB_CASTLING_K);
    std.debug.assert(@intFromEnum(brd.CastleValues.WhiteQueenside) == c.TB_CASTLING_Q);
    std.debug.assert(@intFromEnum(brd.CastleValues.BlackKingside) == c.TB_CASTLING_k);
    std.debug.assert(@intFromEnum(brd.CastleValues.BlackQueenside) == c.TB_CASTLING_q);
}

pub fn largest() u32 {
    return c.TB_LARGEST;
}

pub fn isLoaded() bool {
    return c.TB_LARGEST > 0;
}

pub fn init(path: [:0]const u8) bool {
    return c.tb_init(path.ptr);
}

pub fn deinit() void {
    c.tb_free();
}

const Extracted = struct {
    white: u64,
    black: u64,
    kings: u64,
    queens: u64,
    rooks: u64,
    bishops: u64,
    knights: u64,
    pawns: u64,
    rule50: u32,
    castling: u32,
    ep: u32,
    turn: bool,
};

fn extract(gs: *const brd.GameState) Extracted {
    const pos = &gs.cur_position;
    return .{
        .white = pos.getColorBoard(.White),
        .black = pos.getColorBoard(.Black),
        .kings = pos.getPieceBoard(.King),
        .queens = pos.getPieceBoard(.Queen),
        .rooks = pos.getPieceBoard(.Rook),
        .bishops = pos.getPieceBoard(.Bishop),
        .knights = pos.getPieceBoard(.Knight),
        .pawns = pos.getPieceBoard(.Pawn),
        .rule50 = pos.halfmove,
        .castling = pos.castle,
        .ep = if (pos.ep_sq) |sq| sq else 0,
        .turn = gs.to_move == .White,
    };
}

pub fn probeWdl(gs: *const brd.GameState) ?u32 {
    const e = extract(gs);
    const r = c.tb_probe_wdl(
        e.white, e.black, e.kings, e.queens, e.rooks,
        e.bishops, e.knights, e.pawns,
        e.rule50, e.castling, e.ep, e.turn,
    );
    if (r == TB_RESULT_FAILED) return null;
    return r;
}

pub const RootProbe = struct {
    wdl: u32,
    dtz: u32,
    move: mvs.Move,
};

pub fn probeRootDtz(gs: *const brd.GameState, move_gen: *const mvs.MoveGen) ?RootProbe {
    const e = extract(gs);
    const r = c.tb_probe_root(
        e.white, e.black, e.kings, e.queens, e.rooks,
        e.bishops, e.knights, e.pawns,
        e.rule50, e.castling, e.ep, e.turn,
        null,
    );
    if (r == TB_RESULT_FAILED or r == c.TB_RESULT_CHECKMATE or r == c.TB_RESULT_STALEMATE) {
        return null;
    }

    const from: u32 = c.TB_GET_FROM(r);
    const to: u32 = c.TB_GET_TO(r);
    const want_promo: ?brd.Pieces = switch (c.TB_GET_PROMOTES(r)) {
        c.TB_PROMOTES_QUEEN => .Queen,
        c.TB_PROMOTES_ROOK => .Rook,
        c.TB_PROMOTES_BISHOP => .Bishop,
        c.TB_PROMOTES_KNIGHT => .Knight,
        else => null,
    };

    const moves = move_gen.generateLegal(gs, .all);
    for (moves.slice()) |m| {
        if (m.from != from or m.to != to) continue;
        const promo: ?brd.Pieces = if (m.isPromo()) m.promoPiece() else null;
        if (promo != want_promo) continue;
        return .{ .wdl = c.TB_GET_WDL(r), .dtz = c.TB_GET_DTZ(r), .move = m };
    }
    return null;
}
