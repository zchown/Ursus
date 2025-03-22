const std = @import("std");
const chess = @import("chess/chess.zig");

pub fn main() !void {
    // var rad = chess.Istari.new();
    // rad.initMagicNumbers();
    // var board = chess.Board.new();
    // _ = try chess.parseFEN(&board, "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");

    // mg = chess.MoveGen.new();

    // chess.setupStartingPosition(&board);

    // chess.debugPrintBoard(&board);

    try chess.runPerftTest();
}
