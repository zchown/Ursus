const brd = @import("../chess/board.zig");

pub const PieceValues = enum(usize) {
    Pawn = 100,
    Knight = 320,
    Bishop = 330,
    Rook = 500,
    Queen = 900,
    King = 0,
};

pub fn evaluate(board: *brd.Board) f64 {
    return evaluateMaterial(board);
}

pub fn evaluateMaterial(board: *brd.Board) f64 {
    var score: f64 = 0;
    // pawns
    score += @as(f64, @floatFromInt(@popCount(board.piece_bb[0][0]) * @intFromEnum(PieceValues.Pawn)));
    score -= @as(f64, @floatFromInt(@popCount(board.piece_bb[1][0]) * @intFromEnum(PieceValues.Pawn)));
    // knights
    score += @as(f64, @floatFromInt(@popCount(board.piece_bb[0][1]) * @intFromEnum(PieceValues.Knight)));
    score -= @as(f64, @floatFromInt(@popCount(board.piece_bb[1][1]) * @intFromEnum(PieceValues.Knight)));
    // bishops
    score += @as(f64, @floatFromInt(@popCount(board.piece_bb[0][2]) * @intFromEnum(PieceValues.Bishop)));
    score -= @as(f64, @floatFromInt(@popCount(board.piece_bb[1][2]) * @intFromEnum(PieceValues.Bishop)));
    // rooks
    score += @as(f64, @floatFromInt(@popCount(board.piece_bb[0][3]) * @intFromEnum(PieceValues.Rook)));
    score -= @as(f64, @floatFromInt(@popCount(board.piece_bb[1][3]) * @intFromEnum(PieceValues.Rook)));
    // queens
    score += @as(f64, @floatFromInt(@popCount(board.piece_bb[0][4]) * @intFromEnum(PieceValues.Queen)));
    score -= @as(f64, @floatFromInt(@popCount(board.piece_bb[1][4]) * @intFromEnum(PieceValues.Queen)));

    return score;
}
