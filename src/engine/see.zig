const brd = @import("board");
const mvs = @import("moves");
const std = @import("std");

pub const see_values = [_]i32{
    93, // Pawn
    308, // Knight
    346, // Bishop
    521, // Rook
    994, // Queen
    20000, // King
    0, // None
};

fn seeSwap(
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    target_sq: usize,
    attacker_sq: usize,
    attacker_piece: brd.Pieces,
    color_: brd.Color,
    initial_gain: i32,
    ep_capture_sq: ?usize,
) i32 {
    var gain: [32]i32 = undefined;
    var depth: usize = 0;

    var from_sq = attacker_sq;
    var piece = attacker_piece;
    var color = color_;

    gain[0] = initial_gain;

    const wp = board.piece_bb[@intFromEnum(brd.Color.White)];
    const bp = board.piece_bb[@intFromEnum(brd.Color.Black)];
    const bq = wp[@intFromEnum(brd.Pieces.Bishop)] | bp[@intFromEnum(brd.Pieces.Bishop)] |
        wp[@intFromEnum(brd.Pieces.Queen)] | bp[@intFromEnum(brd.Pieces.Queen)];
    const rq = wp[@intFromEnum(brd.Pieces.Rook)] | bp[@intFromEnum(brd.Pieces.Rook)] |
        wp[@intFromEnum(brd.Pieces.Queen)] | bp[@intFromEnum(brd.Pieces.Queen)];

    var occupied = board.occupancy();
    if (ep_capture_sq) |eps| {
        occupied ^= (@as(u64, 1) << @intCast(eps));
    }
    occupied ^= (@as(u64, 1) << @intCast(from_sq));

    var attackers = getAllAttackers(board, move_gen, target_sq, occupied, bq, rq) & occupied;

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

        color = brd.flipColor(color);

        const next_attacker = getLeastValuableAttacker(board, attackers, color) orelse break;

        if (next_attacker.piece == .King and
            (attackers & board.color_bb[@intFromEnum(brd.flipColor(color))]) != 0)
        {
            break;
        }

        from_sq = next_attacker.square;
        piece = next_attacker.piece;
        occupied ^= (@as(u64, 1) << @intCast(from_sq));
    }

    var i = depth - 1;
    while (i > 0) : (i -= 1) {
        gain[i - 1] = -@max(-gain[i - 1], gain[i]);
    }

    return gain[0];
}

const MoveInfo = struct {
    lands: brd.Pieces,
    gain: i32,
    ep_capture_sq: ?usize,
};

fn describe(move: mvs.EncodedMove) MoveInfo {
    const pawn = see_values[@intFromEnum(brd.Pieces.Pawn)];
    var info = MoveInfo{
        .lands = @enumFromInt(move.piece),
        .gain = 0,
        .ep_capture_sq = null,
    };

    if (move.en_passant == 1) {
        info.gain = pawn;
        info.ep_capture_sq = @as(usize, move.end_square) ^ 8;
    } else if (move.capture == 1) {
        const captured: brd.Pieces = @enumFromInt(move.captured_piece);
        info.gain = see_values[@intFromEnum(captured)];
    }

    if (move.promoted_piece != 0) {
        const promo: brd.Pieces = @enumFromInt(move.promoted_piece);
        info.gain += see_values[@intFromEnum(promo)] - pawn;
        info.lands = promo;
    }

    return info;
}

pub fn seeMove(
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    move: mvs.EncodedMove,
) i32 {
    const info = describe(move);
    return seeSwap(
        board,
        move_gen,
        move.end_square,
        move.start_square,
        info.lands,
        board.toMove(),
        info.gain,
        info.ep_capture_sq,
    );
}

pub fn seeCapture(
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    move: mvs.EncodedMove,
) i32 {
    if (move.capture == 0 and move.en_passant == 0 and move.promoted_piece == 0) return 0;
    return seeMove(board, move_gen, move);
}

pub fn see(
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    target_sq: usize,
    attacker_sq: usize,
    attacker_piece: brd.Pieces,
) i32 {
    const target_piece = board.getPieceFromSquare(target_sq) orelse return 0;
    const attacker_color = board.getColorFromSquare(attacker_sq) orelse return 0;

    return seeSwap(
        board,
        move_gen,
        target_sq,
        attacker_sq,
        attacker_piece,
        attacker_color,
        see_values[@intFromEnum(target_piece)],
        null,
    );
}

pub fn seeAtLeast(
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    move: mvs.EncodedMove,
    threshold: i32,
) bool {
    const from = @as(usize, move.start_square);
    const to = @as(usize, move.end_square);

    const info = describe(move);

    var swap: i32 = info.gain - threshold;
    if (swap < 0) return false;

    swap = see_values[@intFromEnum(info.lands)] - swap;
    if (swap <= 0) return true;

    var occ = board.occupancy();
    occ ^= (@as(u64, 1) << @intCast(from));
    occ ^= (@as(u64, 1) << @intCast(to));
    if (info.ep_capture_sq) |eps| {
        occ ^= (@as(u64, 1) << @intCast(eps));
    }

    const wp = board.piece_bb[@intFromEnum(brd.Color.White)];
    const bp = board.piece_bb[@intFromEnum(brd.Color.Black)];
    const bq = wp[@intFromEnum(brd.Pieces.Bishop)] | bp[@intFromEnum(brd.Pieces.Bishop)] |
        wp[@intFromEnum(brd.Pieces.Queen)] | bp[@intFromEnum(brd.Pieces.Queen)];
    const rq = wp[@intFromEnum(brd.Pieces.Rook)] | bp[@intFromEnum(brd.Pieces.Rook)] |
        wp[@intFromEnum(brd.Pieces.Queen)] | bp[@intFromEnum(brd.Pieces.Queen)];

    var attackers = getAllAttackers(board, move_gen, to, occ, bq, rq) & occ;

    var stm = brd.flipColor(board.toMove());

    var res: i32 = 1;

    while (true) {
        const stm_attackers = attackers & board.color_bb[@intFromEnum(stm)];
        if (stm_attackers == 0) break;

        res ^= 1;

        const na = getLeastValuableAttacker(board, stm_attackers, stm) orelse break;

        if (na.piece == .King and
            (attackers & board.color_bb[@intFromEnum(brd.flipColor(stm))]) != 0)
        {
            res ^= 1;
            break;
        }

        swap = see_values[@intFromEnum(na.piece)] - swap;
        if (swap < res) break;

        occ ^= (@as(u64, 1) << @intCast(na.square));

        if (na.piece == .Pawn or na.piece == .Bishop or na.piece == .Queen) {
            attackers |= move_gen.getBishopAttacks(to, occ) & bq;
        }
        if (na.piece == .Rook or na.piece == .Queen) {
            attackers |= move_gen.getRookAttacks(to, occ) & rq;
        }
        attackers &= occ;

        stm = brd.flipColor(stm);
    }

    return res != 0;
}

const AttackerInfo = struct {
    square: usize,
    piece: brd.Pieces,
};

fn getLeastValuableAttacker(board: *brd.Board, attackers: u64, color: brd.Color) ?AttackerInfo {
    const c_idx = @intFromEnum(color);

    const pieces = [_]brd.Pieces{ .Pawn, .Knight, .Bishop, .Rook, .Queen, .King };

    for (pieces) |piece| {
        const piece_attackers = attackers & board.piece_bb[c_idx][@intFromEnum(piece)];
        if (piece_attackers != 0) {
            return AttackerInfo{
                .square = brd.getLSB(piece_attackers),
                .piece = piece,
            };
        }
    }

    return null;
}

fn getAllAttackers(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64, bq: u64, rq: u64) u64 {
    const wp = board.piece_bb[@intFromEnum(brd.Color.White)];
    const bp = board.piece_bb[@intFromEnum(brd.Color.Black)];

    var attackers: u64 = 0;

    attackers |= move_gen.pawns[@as(u64, @intFromEnum(brd.Color.Black)) * 64 + sq] & wp[@intFromEnum(brd.Pieces.Pawn)];
    attackers |= move_gen.pawns[@as(u64, @intFromEnum(brd.Color.White)) * 64 + sq] & bp[@intFromEnum(brd.Pieces.Pawn)];

    attackers |= move_gen.knights[sq] & (wp[@intFromEnum(brd.Pieces.Knight)] | bp[@intFromEnum(brd.Pieces.Knight)]);
    attackers |= move_gen.kings[sq] & (wp[@intFromEnum(brd.Pieces.King)] | bp[@intFromEnum(brd.Pieces.King)]);

    attackers |= move_gen.getBishopAttacks(sq, occupied) & bq;
    attackers |= move_gen.getRookAttacks(sq, occupied) & rq;

    return attackers;
}
