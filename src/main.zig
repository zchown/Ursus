const std = @import("std");
const perft = @import("chess/perft.zig");

pub fn main() !void {
    // var rad = chess.Istari.init();
    // rad.initMagicNumbers();
    // var board = chess.Board.init();
    // _ = try chess.parseFEN(&board, "r3k2r/p1ppNpb1/1n2pn2/3P4/1pb1P3/2N2Q1p/PPPBBPPP/R3K2R b KQkq - 0 2");
    //
    // var mg = chess.MoveGen.init();
    // const moveList = mg.generateMoves(&board, false);
    //
    // std.debug.print("Moves generated: {d}\n", .{moveList.current});
    // for (0..moveList.current) |m| {
    //     const move = moveList.list[m];
    //     move.printAlgebraic();
    // }

    // chess.setupStartingPosition(&board);

    // chess.debugPrintBoard(&board);

    try perft.runPerftTest();
}
