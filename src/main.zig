const std = @import("std");
const chess = @import("chess/chess.zig");

pub fn main() void {
    // var rad = chess.Istari.new();
    // rad.initMagicNumbers();
    var board = chess.Board.new();
    chess.setupStartingPosition(&board);

    chess.debugPrintBoard(&board);

    var mg = chess.MoveGen.new();

    chess.testPerft(&mg, &board, 5);

}
