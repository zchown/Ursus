const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");

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

fn extract(board: *const brd.Board) struct {
    white: u64, black: u64,
    kings: u64, queens: u64, rooks: u64,
    bishops: u64, knights: u64, pawns: u64,
    rule50: u32, castling: u32, ep: u32, turn: bool,
} {
    const W = @intFromEnum(brd.Color.White);
    const B = @intFromEnum(brd.Color.Black);
    const P = @intFromEnum(brd.Pieces.Pawn);
    const N = @intFromEnum(brd.Pieces.Knight);
    const Bi = @intFromEnum(brd.Pieces.Bishop);
    const R = @intFromEnum(brd.Pieces.Rook);
    const Q = @intFromEnum(brd.Pieces.Queen);
    const K = @intFromEnum(brd.Pieces.King);

    const wb = board.piece_bb[W];
    const bb = board.piece_bb[B];

    const white = wb[P] | wb[N] | wb[Bi] | wb[R] | wb[Q] | wb[K];
    const black = bb[P] | bb[N] | bb[Bi] | bb[R] | bb[Q] | bb[K];

    const gs = board.game_state;
    const halfmove: u32 = @intCast(gs.halfmove_clock);
    const ep_sq: u32 = if (gs.en_passant_square) |sq| @intCast(sq) else 0;

    // Fathom castling bits: 0x1=K, 0x2=Q, 0x4=k, 0x8=q
    var castling: u32 = 0;

    if ((gs.castling_rights & @intFromEnum(brd.CastleRights.WhiteKingside)) != 0) {
        castling |= 0x1;
    }
    if ((gs.castling_rights & @intFromEnum(brd.CastleRights.WhiteQueenside)) != 0) {
        castling |= 0x2;
    }
    if ((gs.castling_rights & @intFromEnum(brd.CastleRights.BlackKingside)) != 0) {
        castling |= 0x4;
    }
    if ((gs.castling_rights & @intFromEnum(brd.CastleRights.BlackQueenside)) != 0) {
        castling |= 0x8;
    }

    return .{
        .white = white, .black = black,
        .kings  = wb[K]  | bb[K],
        .queens = wb[Q]  | bb[Q],
        .rooks  = wb[R]  | bb[R],
        .bishops = wb[Bi] | bb[Bi],
        .knights = wb[N]  | bb[N],
        .pawns  = wb[P]  | bb[P],
        .rule50 = halfmove,
        .castling = castling,
        .ep = ep_sq,
        .turn = board.toMove() == .White,
    };
}

pub fn probeWdl(board: *const brd.Board) ?u32 {
    const e = extract(board);
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
    move: mvs.EncodedMove,
};

pub fn probeRootDtz(board: *const brd.Board, move_gen: *mvs.MoveGen) ?RootProbe {
    const e = extract(board);
    const r = c.tb_probe_root(
        e.white, e.black, e.kings, e.queens, e.rooks,
        e.bishops, e.knights, e.pawns,
        e.rule50, e.castling, e.ep, e.turn,
        null,
    );
    if (r == TB_RESULT_FAILED or r == c.TB_RESULT_CHECKMATE or r == c.TB_RESULT_STALEMATE) {
        return null;
    }

    const from: u8 = @intCast(c.TB_GET_FROM(r));
    const to:   u8 = @intCast(c.TB_GET_TO(r));
    const promo: u8 = @intCast(c.TB_GET_PROMOTES(r));
    const wdl: u32 = c.TB_GET_WDL(r);
    const dtz: u32 = c.TB_GET_DTZ(r);

    const b = @constCast(board);
    const moves = move_gen.generateMoves(b, false);
    var found: ?mvs.EncodedMove = null;
    for (0..moves.len) |i| {
        const m = moves.items[i];
        if (m.start_square == from and m.end_square == to) {
            const want_promo: u8 = switch (promo) {
                0 => 0,
                1 => @intFromEnum(brd.Pieces.Queen),
                2 => @intFromEnum(brd.Pieces.Rook),
                3 => @intFromEnum(brd.Pieces.Bishop),
                4 => @intFromEnum(brd.Pieces.Knight),
                else => 0,
            };
            if (m.promoted_piece == want_promo) {
                found = m;
                break;
            }
        }
    }
    if (found == null) return null;

    return .{ .wdl = wdl, .dtz = dtz, .move = found.? };
}
