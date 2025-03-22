const std = @import("std");
const chess = @import("chess/chess.zig");

pub fn main() !void {
    // var rad = chess.Istari.new();
    // rad.initMagicNumbers();
    var board = chess.Board.new();
    chess.setupStartingPosition(&board);

    // chess.debugPrintBoard(&board);

    try chess.runPerftTest();

}
