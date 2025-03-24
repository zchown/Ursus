const std = @import("std");
const brd = @import("chess/board.zig");
const fen = @import("chess/fen.zig");
const mvs = @import("chess/moves.zig");
const srch = @import("engine/search.zig");
const tt = @import("engine/transposition.zig");

pub fn main() !void {
    var board = brd.Board.init();
    fen.setupStartingPosition(&board);

    var move_gen = mvs.MoveGen.init();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    var table = try tt.TranspositionTable.init(gpa.allocator(), 1 << 10, null);

    const tsr = srch.search(&board, &move_gen, &table, 1000);

    tsr.search_result.bestMove.printAlgebraic();
    std.debug.print("\n", .{});

    tsr.stats.print();
    std.debug.print("\n", .{});

    table.stats.print();

}
