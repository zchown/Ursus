const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;
const mvs = root.moves;

const Bitboard = brd.Bitboard;
const Square = brd.Square;
const Pieces = brd.Pieces;
const Color = brd.Color;
const Position = brd.Position;
const GameState = brd.GameState;
const Move = mvs.Move;

pub const see_values = [_]i32{
    93, // Pawn
    308, // Knight
    346, // Bishop
    521, // Rook
    994, // Queen
    20000, // King
    0, // None
};

inline fn diagonalSliders(pos: *const Position) Bitboard {
    return pos.getPieceBoard(.Bishop) | pos.getPieceBoard(.Queen);
}

inline fn straightSliders(pos: *const Position) Bitboard {
    return pos.getPieceBoard(.Rook) | pos.getPieceBoard(.Queen);
}

fn seeSwap(
    pos: *const Position,
    move_gen: *const mvs.MoveGen,
    target_sq: Square,
    attacker_sq: Square,
    attacker_piece: Pieces,
    color_: Color,
    initial_gain: i32,
    ep_capture_sq: ?Square,
) i32 {
    var gain: [32]i32 = undefined;
    var depth: usize = 0;

    var from_sq = attacker_sq;
    var piece = attacker_piece;
    var color = color_;

    gain[0] = initial_gain;

    const bq = diagonalSliders(pos);
    const rq = straightSliders(pos);

    var occupied = pos.getOccupancy();
    if (ep_capture_sq) |eps| {
        occupied ^= brd.getSquareBB(eps);
    }
    occupied ^= brd.getSquareBB(from_sq);

    var attackers = move_gen.attackersTo(pos, target_sq, occupied) & occupied;

    while (true) {
        depth += 1;
        if (depth >= 32) break;

        gain[depth] = see_values[@intFromEnum(piece)] - gain[depth - 1];

        if (piece == .Pawn or piece == .Bishop or piece == .Queen) {
            attackers |= move_gen.getBishopAttacks(target_sq, occupied) & bq;
        }
        if (piece == .Rook or piece == .Queen) {
            attackers |= move_gen.getRookAttacks(target_sq, occupied) & rq;
        }
        attackers &= occupied;

        color = color.opposite();

        const next_attacker = getLeastValuableAttacker(pos, attackers, color) orelse break;

        if (next_attacker.piece == .King and
            (attackers & pos.getColorBoard(color.opposite())) != 0)
        {
            break;
        }

        from_sq = next_attacker.square;
        piece = next_attacker.piece;
        occupied ^= brd.getSquareBB(from_sq);
    }

    var i = depth - 1;
    while (i > 0) : (i -= 1) {
        gain[i - 1] = -@max(-gain[i - 1], gain[i]);
    }

    return gain[0];
}

const MoveInfo = struct {
    lands: Pieces,
    gain: i32,
    ep_capture_sq: ?Square,
};

fn describe(pos: *const Position, move: Move) MoveInfo {
    const pawn = see_values[@intFromEnum(Pieces.Pawn)];
    var info = MoveInfo{
        .lands = pos.movedPiece(move).piece,
        .gain = 0,
        .ep_capture_sq = null,
    };

    if (move.isEP()) {
        info.gain = pawn;
        info.ep_capture_sq = move.to ^ 8;
    } else if (move.isCapture()) {
        info.gain = see_values[@intFromEnum(pos.getPieceFromSquare(move.to))];
    }

    if (move.isPromo()) {
        const promo = move.promoPiece();
        info.gain += see_values[@intFromEnum(promo)] - pawn;
        info.lands = promo;
    }

    return info;
}

pub fn seeMove(
    gs: *const GameState,
    move_gen: *const mvs.MoveGen,
    move: Move,
) i32 {
    const pos = &gs.cur_position;
    const info = describe(pos, move);
    return seeSwap(
        pos,
        move_gen,
        move.to,
        move.from,
        info.lands,
        gs.to_move,
        info.gain,
        info.ep_capture_sq,
    );
}

pub fn seeCapture(
    gs: *const GameState,
    move_gen: *const mvs.MoveGen,
    move: Move,
) i32 {
    if (!move.isCapture() and !move.isPromo()) return 0;
    return seeMove(gs, move_gen, move);
}

pub fn see(
    gs: *const GameState,
    move_gen: *const mvs.MoveGen,
    target_sq: Square,
    attacker_sq: Square,
    attacker_piece: Pieces,
) i32 {
    const pos = &gs.cur_position;
    const target_piece = pos.getPieceFromSquare(target_sq);
    if (target_piece == .None or pos.getPieceFromSquare(attacker_sq) == .None) return 0;

    return seeSwap(
        pos,
        move_gen,
        target_sq,
        attacker_sq,
        attacker_piece,
        pos.getColorFromSquare(attacker_sq),
        see_values[@intFromEnum(target_piece)],
        null,
    );
}

pub fn seeAtLeast(
    gs: *const GameState,
    move_gen: *const mvs.MoveGen,
    move: Move,
    threshold: i32,
) bool {
    const pos = &gs.cur_position;
    const from = move.from;
    const to = move.to;

    const info = describe(pos, move);

    var swap: i32 = info.gain - threshold;
    if (swap < 0) return false;

    swap = see_values[@intFromEnum(info.lands)] - swap;
    if (swap <= 0) return true;

    var occ = pos.getOccupancy();
    occ ^= brd.getSquareBB(from);
    occ ^= brd.getSquareBB(to);
    if (info.ep_capture_sq) |eps| {
        occ ^= brd.getSquareBB(eps);
    }

    const bq = diagonalSliders(pos);
    const rq = straightSliders(pos);

    var attackers = move_gen.attackersTo(pos, to, occ) & occ;

    var stm = gs.to_move.opposite();

    var res: i32 = 1;

    while (true) {
        const stm_attackers = attackers & pos.getColorBoard(stm);
        if (stm_attackers == 0) break;

        res ^= 1;

        const na = getLeastValuableAttacker(pos, stm_attackers, stm) orelse break;

        if (na.piece == .King and
            (attackers & pos.getColorBoard(stm.opposite())) != 0)
        {
            res ^= 1;
            break;
        }

        swap = see_values[@intFromEnum(na.piece)] - swap;
        if (swap < res) break;

        occ ^= brd.getSquareBB(na.square);

        if (na.piece == .Pawn or na.piece == .Bishop or na.piece == .Queen) {
            attackers |= move_gen.getBishopAttacks(to, occ) & bq;
        }
        if (na.piece == .Rook or na.piece == .Queen) {
            attackers |= move_gen.getRookAttacks(to, occ) & rq;
        }
        attackers &= occ;

        stm = stm.opposite();
    }

    return res != 0;
}

const AttackerInfo = struct {
    square: Square,
    piece: Pieces,
};

fn getLeastValuableAttacker(pos: *const Position, attackers: Bitboard, color: Color) ?AttackerInfo {
    const pieces = [_]Pieces{ .Pawn, .Knight, .Bishop, .Rook, .Queen, .King };

    for (pieces) |piece| {
        const piece_attackers = attackers & pos.getPieceColorBoard(piece, color);
        if (piece_attackers != 0) {
            return AttackerInfo{
                .square = brd.lsb(piece_attackers),
                .piece = piece,
            };
        }
    }

    return null;
}
