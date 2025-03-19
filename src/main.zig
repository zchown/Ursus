const std = @import("std");
const chess = @import("chess/chess.zig");

pub fn main() void {
    var rad = chess.Istari.new();
    rad.initMagicNumbers();
    // var board = chess.Board.new();
    // chess.setupStartingPosition(&board);
    //
    // chess.debugPrintBoard(&board);
    //
    // var mg = chess.MoveGen.new();
    // const moves = mg.generateMoves(&board, false);
    // std.debug.print("Number of moves: {}\n", .{moves.current});
    //
    // for (0..moves.current) |i| {
    //     const move = moves.list[i];
    //     move.printAlgebraic();
    // }
}
