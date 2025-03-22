const std = @import("std");
const brd = @import("board.zig");
const mvs = @import("moves.zig");
const fen = @import("fen.zig");

pub fn runPerft(mg: *mvs.MoveGen, board: *brd.Board, max_depth: usize) void {
    for (0..max_depth) |depth| {
        const start = std.time.milliTimestamp();
        const nodes = perft(mg, board, depth + 1);
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

pub fn perft(mg: *mvs.MoveGen, board: *brd.Board, depth: usize) u64 {
    if (depth == 0) {
        return 1;
    }
    var nodes: u64 = 0;
    const moveList = mg.generateMoves(board, mvs.allMoves);
    for (0..moveList.current) |m| {
        const move = moveList.list[m];
        mvs.makeMove(board, move);
        const king_square = brd.getLSB(board.piece_bb[@intFromEnum(brd.flipColor(board.game_state.side_to_move))][@intFromEnum(brd.Pieces.King)]);
        if (mg.isAttacked(king_square, board.game_state.side_to_move, board)) {
            mvs.undoMove(board, move);
            continue;
        }
        nodes += perft(mg, board, depth - 1);
        mvs.undoMove(board, move);
    }
    return nodes;
}

const TestPosition = struct {
    fen: []const u8,
    depth: u32,
    expected: u64,
};

pub fn runPerftTest() !void {
    const positions = [_]TestPosition{
        TestPosition{
            .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            .depth = 6,
            .expected = 119060324,
        },
        TestPosition{
            .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            .depth = 1,
            .expected = 6,
        },
        TestPosition{
            .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            .depth = 2,
            .expected = 264,
        },
        TestPosition{
            .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            .depth = 3,
            .expected = 9467,
        },
        TestPosition{
            .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            .depth = 4,
            .expected = 422333,
        },
        TestPosition{
            .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            .depth = 5,
            .expected = 15833292,
        },
        TestPosition{
            .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            .depth = 6,
            .expected = 706045033,
        },
        TestPosition{
            .fen = "1k6/1b6/8/8/7R/8/8/4K2R b K - 0 1",
            .depth = 5,
            .expected = 1063513,
        },
        TestPosition{
            .fen = "3k4/3p4/8/K1P4r/8/8/8/8 b - - 0 1",
            .depth = 6,
            .expected = 1134888,
        },
        TestPosition{
            .fen = "8/8/4k3/8/2p5/8/B2P2K1/8 w - - 0 1",
            .depth = 6,
            .expected = 1015133,
        },
        TestPosition{
            .fen = "3k4/3p4/8/K1P4r/8/8/8/8 b - - 0 1",
            .depth = 6,
            .expected = 1134888,
        },
        TestPosition{
            .fen = "r3k2r/8/3Q4/8/8/5q2/8/R3K2R b KQkq - 0 1",
            .depth = 4,
            .expected = 1720476,
        },
    };

    var mg = mvs.MoveGen.new();
    for (positions) |pos| {
        std.debug.print("Testing position: {s}\n", .{pos.fen});
        var board = brd.Board.new();
        _ = try fen.parseFEN(&board, pos.fen);
        const start = std.time.milliTimestamp();
        const actual = perft(&mg, &board, pos.depth);
        const end = std.time.milliTimestamp();
        const time = end - start;
        std.debug.print("Time: {}ms\n", .{time});
        std.debug.print("kNodes/second: {}\n", .{actual / @as(u64, @intCast(time))});

        if (pos.expected != actual) {
            std.debug.print("Error: Expected {} but got {}\n", .{pos.expected, actual});
            return error.TestFailed;
        } else {
            std.debug.print("Test passed!\n\n", .{});
        }
    }
}
