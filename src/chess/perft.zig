const std = @import("std");
const brd = @import("board.zig");
const mvs = @import("moves.zig");
const fen = @import("fen.zig");

pub fn runPerft(mg: *mvs.MoveGen, board: *brd.Board, depth: usize) u64 {
    if (depth == 0) {
        // check if the side just moved is in check
        const king_square = brd.getLSB(board.piece_bb.get(brd.flipColor(board.game_state.side_to_move)).get(brd.Pieces.King));
        if (mg.isAttacked(king_square, board.game_state.side_to_move, board)) {
            // std.debug.print("Check\n", .{});
            return 0;
        }
        return 1;
    }

    var nodes: u64 = 0;

    const moveList = mg.generateMoves(board, mvs.allMoves);

    for (0..moveList.current) |m| {
        const move = moveList.list[m];
        // move.printAlgebraic();
        mvs.makeMove(board, move);

        // fen.debugPrintBoard(board);

        const king_square = brd.getLSB(board.piece_bb.get(brd.flipColor(board.game_state.side_to_move)).get(brd.Pieces.King));
        // std.debug.print("King square: {}\n", .{king_square});
        if (mg.isAttacked(king_square, board.game_state.side_to_move, board)) {
            // std.debug.print("Illegal move\n", .{});
            mvs.undoMove(board, move);
            continue;
        }

        nodes += runPerft(mg, board, depth - 1);
        mvs.undoMove(board, move);
        // std.debug.print("\n\nAfterUndo\n", .{});
        // fen.debugPrintBoard(board);
    }

    return nodes;
}

// time and run perft
pub fn testPerft(mg: *mvs.MoveGen, board: *brd.Board, max_depth: usize) void {
    for (0..max_depth) |depth| {
        const start = std.time.milliTimestamp();
        const nodes = runPerft(mg, board, depth + 1);
        const end = std.time.milliTimestamp();
        const time = end - start;
        std.debug.print("Depth: {}\n", .{depth + 1});
        std.debug.print("Nodes: {}\n", .{nodes});
        std.debug.print("Time: {}ms\n", .{time});
        if (time == 0) {
            std.debug.print("Nodes/second: N/A\n\n\n", .{});
            continue;
        }
        std.debug.print("Nodes/second: {}\n\n\n", .{nodes * 1000 / @as(u64, @intCast(time))});
    }
}
