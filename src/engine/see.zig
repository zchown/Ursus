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
    0,
};

fn seeSwap(
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    target_sq: usize,
    attacker_sq: usize,
    attacker_piece: brd.Pieces,
    color_: brd.Color,
    initial_gain: i32,
) i32 {
    var gain: [32]i32 = @splat(0);
    var depth: usize = 0;

    var from_sq = attacker_sq;
    var piece = attacker_piece;
    var color = color_;

    gain[0] = initial_gain;

    var occupied = board.occupancy();
    var attackers = getAllAttackers(board, move_gen, target_sq, occupied);

    while (true) {
        depth += 1;
        if (depth >= 32) break;

        gain[depth] = see_values[@intFromEnum(piece)] - gain[depth - 1];

        // Pruning: if both sides can't improve, stop early
        if (@max(-gain[depth - 1], gain[depth]) < 0) break;

        occupied ^= (@as(u64, 1) << @intCast(from_sq));

        // Discover x-ray attackers behind the piece we just removed
        if (piece == .Pawn or piece == .Bishop or piece == .Queen) {
            attackers |= getBishopXrays(board, move_gen, target_sq, occupied);
        }
        if (piece == .Rook or piece == .Queen) {
            attackers |= getRookXrays(board, move_gen, target_sq, occupied);
        }

        attackers &= occupied;

        color = brd.flipColor(color);

        const next_attacker = getLeastValuableAttacker(board, attackers, color);
        if (next_attacker) |na| {
            from_sq = na.square;
            piece = na.piece;
        } else {
            break;
        }
    }

    var i = depth - 1;
    while (i > 0) : (i -= 1) {
        gain[i - 1] = -@max(-gain[i - 1], gain[i]);
    }

    return gain[0];
}

pub fn seeCapture(board: *brd.Board, move_gen: *mvs.MoveGen, move: mvs.EncodedMove) i32 {
    const attacker = board.getPieceFromSquare(move.start_square) orelse return 0;
    const attacker_color = board.getColorFromSquare(move.start_square) orelse return 0;

    // En passant: captured pawn is not on end_square
    if (move.en_passant == 1) {
        return seeSwap(
            board,
            move_gen,
            move.end_square,
            move.start_square,
            attacker,
            attacker_color,
            see_values[@intFromEnum(brd.Pieces.Pawn)],
        );
    }

    const target_piece = board.getPieceFromSquare(move.end_square) orelse return 0;

    return seeSwap(
        board,
        move_gen,
        move.end_square,
        move.start_square,
        attacker,
        attacker_color,
        see_values[@intFromEnum(target_piece)],
    );
}

pub fn seeMove(board: *brd.Board, move_gen: *mvs.MoveGen, move: mvs.EncodedMove) i32 {
    const attacker = board.getPieceFromSquare(move.start_square) orelse return 0;
    const attacker_color = board.getColorFromSquare(move.start_square) orelse return 0;

    // En passant
    if (move.en_passant == 1) {
        return seeSwap(
            board,
            move_gen,
            move.end_square,
            move.start_square,
            attacker,
            attacker_color,
            see_values[@intFromEnum(brd.Pieces.Pawn)],
        );
    }

    // Capture: initial gain = value of captured piece
    const target_piece = board.getPieceFromSquare(move.end_square);
    if (target_piece) |tp| {
        return seeSwap(
            board,
            move_gen,
            move.end_square,
            move.start_square,
            attacker,
            attacker_color,
            see_values[@intFromEnum(tp)],
        );
    }

    return seeSwap(
        board,
        move_gen,
        move.end_square,
        move.start_square,
        attacker,
        attacker_color,
        0,
    );
}

pub fn seeAtLeast(board: *brd.Board, move_gen: *mvs.MoveGen, move: mvs.EncodedMove, threshold: i32) bool {
    const from = @as(usize, move.start_square);
    const to = @as(usize, move.end_square);

    const attacker = board.getPieceFromSquare(from) orelse return false;

    // Step 1: After our initial capture/move, are we above threshold?
    var swap: i32 = 0;
    if (move.en_passant == 1) {
        swap = see_values[@intFromEnum(brd.Pieces.Pawn)] - threshold;
    } else if (board.getPieceFromSquare(to)) |tp| {
        swap = see_values[@intFromEnum(tp)] - threshold;
    } else {
        swap = -threshold; // quiet move: gained nothing
    }
    if (swap < 0) return false;

    // Step 2: Even if opponent recaptures our piece, do we still meet threshold?
    swap = see_values[@intFromEnum(attacker)] - swap;
    if (swap <= 0) return true;

    // Step 3: Need to run the swap loop
    var occ = board.occupancy();
    occ ^= (@as(u64, 1) << @intCast(from));
    occ ^= (@as(u64, 1) << @intCast(to));
    if (move.en_passant == 1) {
        occ ^= (@as(u64, 1) << @intCast(to ^ 8));
    }

    var attackers = getAllAttackers(board, move_gen, to, occ) & occ;

    var stm = brd.flipColor(board.getColorFromSquare(from) orelse return false);

    var res: i32 = 1; // 1 = threshold met, 0 = not met

    while (true) {
        const stm_attackers = attackers & board.color_bb[@intFromEnum(stm)];
        if (stm_attackers == 0) break;

        res ^= 1;

        const na = getLeastValuableAttacker(board, stm_attackers, stm) orelse break;

        swap = see_values[@intFromEnum(na.piece)] - swap;
        if (swap < res) break;

        occ ^= (@as(u64, 1) << @intCast(na.square));

        if (na.piece == .Pawn or na.piece == .Bishop or na.piece == .Queen) {
            attackers |= getBishopXrays(board, move_gen, to, occ);
        }
        if (na.piece == .Rook or na.piece == .Queen) {
            attackers |= getRookXrays(board, move_gen, to, occ);
        }
        attackers &= occ;

        stm = brd.flipColor(stm);
    }

    return res != 0;
}

pub fn see(board: *brd.Board, move_gen: *mvs.MoveGen, target_sq: usize, attacker_sq: usize, attacker_piece: brd.Pieces) i32 {
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
    );
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

fn getAllAttackers(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64) u64 {
    var attackers: u64 = 0;

    const white_pawn_attacks = if (sq >= 16)
        ((@as(u64, 1) << @intCast(sq - 7)) & ~@as(u64, 0x0101010101010101)) | // left diagonal
            ((@as(u64, 1) << @intCast(sq - 9)) & ~@as(u64, 0x8080808080808080)) // right diagonal
    else
        0;

    const black_pawn_attacks = if (sq < 48)
        ((@as(u64, 1) << @intCast(sq + 7)) & ~@as(u64, 0x8080808080808080)) | // left diagonal
            ((@as(u64, 1) << @intCast(sq + 9)) & ~@as(u64, 0x0101010101010101)) // right diagonal
    else
        0;

    attackers |= white_pawn_attacks & board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Pawn)];
    attackers |= black_pawn_attacks & board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Pawn)];

    // Knight attackers
    const knight_attacks = move_gen.knights[sq];
    attackers |= knight_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Knight)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Knight)]);

    // King attackers
    const king_attacks = move_gen.kings[sq];
    attackers |= king_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.King)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.King)]);

    // Sliding piece attackers
    const bishop_attacks = move_gen.getBishopAttacks(sq, occupied);
    attackers |= bishop_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);

    const rook_attacks = move_gen.getRookAttacks(sq, occupied);
    attackers |= rook_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);

    return attackers;
}

fn getBishopXrays(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64) u64 {
    const bishop_attacks = move_gen.getBishopAttacks(sq, occupied);
    return bishop_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);
}

fn getRookXrays(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64) u64 {
    const rook_attacks = move_gen.getRookAttacks(sq, occupied);
    return rook_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);
}
