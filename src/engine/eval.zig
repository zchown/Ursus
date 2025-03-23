const std = @import("std");
const brd = @import("../chess/board.zig");

pub const PieceValues = enum (f64) {
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
    score += @popCount(board.piece_bb[0][0]) * PieceValues.Pawn;
    score -= @popCount(board.piece_bb[1][0]) * PieceValues.Pawn;

    // knights
    score += @popCount(board.piece_bb[0][1]) * PieceValues.Knight;
    score -= @popCount(board.piece_bb[1][1]) * PieceValues.Knight;

    // bishops
    score += @popCount(board.piece_bb[0][2]) * PieceValues.Bishop;
    score -= @popCount(board.piece_bb[1][2]) * PieceValues.Bishop;

    // rooks
    score += @popCount(board.piece_bb[0][3]) * PieceValues.Rook;
    score -= @popCount(board.piece_bb[1][3]) * PieceValues.Rook;

    // queens
    score += @popCount(board.piece_bb[0][4]) * PieceValues.Queen;
    score -= @popCount(board.piece_bb[1][4]) * PieceValues.Queen;
    return score;
}
