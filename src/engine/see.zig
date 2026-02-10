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

pub fn seeThreshold(board: *brd.Board, move_gen: *mvs.MoveGen, move: mvs.EncodedMove, threshold: i32) bool {
    const from = move.start_square;
    const to = move.end_square;
    const attacker_piece = board.getPieceFromSquare(from) orelse return false;
    const target_piece = board.getPieceFromSquare(to) orelse return false;
    var swap = see_values[@intFromEnum(target_piece)] - threshold;
    if (swap < 0) return false;
    swap -= see_values[@intFromEnum(attacker_piece)];
    if (swap >= 0) return true;

    var occupied = board.occupancy();
    var attackers = getAllAttackers(board, move_gen, to, occupied);
    const color = board.getColorFromSquare(from) orelse return false;
    var stm = brd.flipColor(color);

    while (true) {
        attackers &= occupied;

        const next_attacker = getLeastValuableAttacker(board, attackers, stm);
        if (next_attacker == null) break;

        const p = @intFromEnum(next_attacker.?.piece);
        const attacker_sq = next_attacker.?.square;

        stm = brd.flipColor(stm);

        swap = -swap - 1 - see_values[p];

        if (swap >= 0) {
            if (p == @intFromEnum(brd.Pieces.King)) {
                if (attackers & board.color_bb[@intFromEnum(stm)] != 0) {
                    stm = brd.flipColor(stm);
                }
            }
            break;
        }

        occupied ^= (@as(u64, 1) << @intCast(attacker_sq));

        if (p == @intFromEnum(brd.Pieces.Pawn) or 
        p == @intFromEnum(brd.Pieces.Bishop) or 
        p == @intFromEnum(brd.Pieces.Queen)) {
            attackers |= getBishopXrays(board, move_gen, to, occupied);
        }
        if (p == @intFromEnum(brd.Pieces.Rook) or 
        p == @intFromEnum(brd.Pieces.Queen)) {
            attackers |= getRookXrays(board, move_gen, to, occupied);
        }
    }
    return stm != color;
}

pub fn see(board: *brd.Board, move_gen: *mvs.MoveGen, target_sq: usize, attacker_sq: usize, attacker_piece: brd.Pieces) i32 {
    var gain: [32]i32 = @splat(0);
    var depth: usize = 0;

    var from_sq = attacker_sq;
    var piece = attacker_piece;
    var color = board.getColorFromSquare(from_sq) orelse return 0;

    const target_piece = board.getPieceFromSquare(target_sq) orelse return 0;
    gain[0] = see_values[@intFromEnum(target_piece)];

    var occupied = board.occupancy();
    var attackers = getAllAttackers(board, move_gen, target_sq, occupied);

    while (true) {
        depth += 1;
        if (depth >= 32) break;

        gain[depth] = see_values[@intFromEnum(piece)] - gain[depth - 1];

        if (@max(-gain[depth - 1], gain[depth]) < 0) break;

        occupied ^= (@as(u64, 1) << @intCast(from_sq));

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

    const target_piece = board.getPieceFromSquare(move.end_square);
    if (target_piece == null) {
        if (move.en_passant == 1) {
            return see_values[@intFromEnum(brd.Pieces.Pawn)] - 
            see(board, move_gen, move.end_square, move.start_square, attacker);
        }
        return 0;
    }

    return see(board, move_gen, move.end_square, move.start_square, attacker);
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
    ((@as(u64, 1) << @intCast(sq - 9)) & ~@as(u64, 0x8080808080808080))   // right diagonal
        else 0;

    const black_pawn_attacks = if (sq < 48)
    ((@as(u64, 1) << @intCast(sq + 7)) & ~@as(u64, 0x8080808080808080)) | // left diagonal
    ((@as(u64, 1) << @intCast(sq + 9)) & ~@as(u64, 0x0101010101010101))   // right diagonal
        else 0;

    attackers |= white_pawn_attacks & board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Pawn)];
    attackers |= black_pawn_attacks & board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Pawn)];

    // Knight attackers
    const knight_attacks = move_gen.knights[sq];
    attackers |= knight_attacks & (
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Knight)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Knight)]
);

    // King attackers
    const king_attacks = move_gen.kings[sq];
    attackers |= king_attacks & (
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.King)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.King)]
);

    // Sliding piece attackers
    const bishop_attacks = move_gen.getBishopAttacks(sq, occupied);
    attackers |= bishop_attacks & (
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)] |
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]
);

    const rook_attacks = move_gen.getRookAttacks(sq, occupied);
    attackers |= rook_attacks & (
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Rook)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Rook)] |
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]
);

    return attackers;
}

fn getBishopXrays(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64) u64 {
    const bishop_attacks = move_gen.getBishopAttacks(sq, occupied);
    return bishop_attacks & (
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)] |
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]
);
}

fn getRookXrays(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64) u64 {
    const rook_attacks = move_gen.getRookAttacks(sq, occupied);
    return rook_attacks & (
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Rook)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Rook)] |
    board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
    board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]
);
}
