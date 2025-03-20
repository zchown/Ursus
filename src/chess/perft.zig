const std = @import("std");
const brd = @import("board.zig");
const mvs = @import("moves.zig");
const fen = @import("fen.zig");

pub fn runPerft(mg: *mvs.MoveGen, board: *brd.Board, depth: usize, allocator: std.mem.Allocator) !u64 {
    if (depth == 0) {
        // check if the side just moved is in check
        // const king_square = brd.getLSB(board.piece_bb.get(brd.flipColor(board.game_state.side_to_move)).get(brd.Pieces.King));
        const king_square = brd.getLSB(board.piece_bb[@intFromEnum(brd.flipColor(board.game_state.side_to_move))][@intFromEnum(brd.Pieces.King)]);
        if (mg.isAttacked(king_square, board.game_state.side_to_move, board)) {
            return 0;
        }
        return 1;
    }

    var nodes: u64 = 0;

    const moveList = mg.generateMoves(board, mvs.allMoves);

    for (0..moveList.current) |m| {
        const move = moveList.list[m];
        // move.printAlgebraic();
        // const fen_before = try fen.toFEN(board, allocator);
        mvs.makeMove(board, move);

        // fen.debugPrintBoard(board);

        // const king_square = brd.getLSB(board.piece_bb.get(brd.flipColor(board.game_state.side_to_move)).get(brd.Pieces.King));
        const king_square = brd.getLSB(board.piece_bb[@intFromEnum(brd.flipColor(board.game_state.side_to_move))][@intFromEnum(brd.Pieces.King)]);
        // std.debug.print("King square: {}\n", .{king_square});
        if (mg.isAttacked(king_square, board.game_state.side_to_move, board)) {
            // std.debug.print("Illegal move\n", .{});
            mvs.undoMove(board, move);
            continue;
        }

        nodes += try runPerft(mg, board, depth - 1, allocator);
        mvs.undoMove(board, move);
        // const fen_after = try fen.toFEN(board, allocator);
        // if (fen.compareFEN(fen_before, fen_after)) {
        //     std.debug.print("FEN mismatch: {s} != {s}\n", .{fen_before, fen_after});
        //     move.printAlgebraic();
        //     fen.debugPrintBoard(board);
        //     std.posix.exit(1);
        // }
        // std.debug.print("\n\nAfterUndo\n", .{});
        // fen.debugPrintBoard(board);
    }

    return nodes;
}

// time and run perft
pub fn testPerft(mg: *mvs.MoveGen, board: *brd.Board, max_depth: usize) !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    for (0..max_depth) |depth| {
        const start = std.time.milliTimestamp();
        const nodes = try runPerft(mg, board, depth + 1, allocator.allocator());
        const end = std.time.milliTimestamp();
        const time = end - start;
        std.debug.print("Depth: {}\n", .{depth + 1});
        std.debug.print("Nodes: {}\n", .{nodes});
        std.debug.print("Time: {}ms\n", .{time});
        if (time == 0) {
            std.debug.print("kNodes/second: N/A\n\n\n", .{});
            continue;
        }
        // thousands of nodes per second
        std.debug.print("kNodes/second: {}\n\n\n", .{nodes / @as(u64, @intCast(time))});
    }
}
