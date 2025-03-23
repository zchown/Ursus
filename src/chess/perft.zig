const std = @import("std");
const brd = @import("board.zig");
const mvs = @import("moves.zig");
const fen = @import("fen.zig");

pub const PerftResult = struct {
    total: u64 = 0,
    captures: u64 = 0,
    en_passant: u64 = 0,
    castling: u64 = 0,
    promotions: u64 = 0,

    pub fn add(self: *PerftResult, other: PerftResult) void {
        self.total += other.total;
        self.captures += other.captures;
        self.en_passant += other.en_passant;
        self.castling += other.castling;
        self.promotions += other.promotions;
    }
};

pub fn runPerft(mg: *mvs.MoveGen, board: *brd.Board, max_depth: usize) void {
    for (0..max_depth) |depth| {
        const start = std.time.milliTimestamp();
        const result = perft(mg, board, depth + 1, std.heap.page_allocator);
        const end = std.time.milliTimestamp();
        const time = end - start;

        std.debug.print("\nDepth: {}\n", .{depth + 1});
        std.debug.print("-----------------\n", .{});
        std.debug.print("Total nodes:    {}\n", .{result.total});
        std.debug.print("Captures:       {}\n", .{result.captures});
        std.debug.print("En passants:    {}\n", .{result.en_passant});
        std.debug.print("Castles:        {}\n", .{result.castling});
        std.debug.print("Promotions:     {}\n", .{result.promotions});
        std.debug.print("Time:           {}ms\n", .{time});

        if (time > 0) {
            const kNps = (result.total * 1000) / @as(u64, @intCast(time));
            std.debug.print("kN/s:           {}\n", .{kNps});
        }
    }
}

pub fn perft(
    mg: *mvs.MoveGen,
    board: *brd.Board,
    depth: usize,
    allocator: std.mem.Allocator,
) PerftResult {
    var result = PerftResult{};

    if (depth == 0) {
        result.total = 1;
        return result;
    }

    const moveList = mg.generateMoves(board, mvs.allMoves);
    var fails: usize = 0;

    for (0..moveList.current) |m| {
        const move = moveList.list[m];

        // Capture original state and FEN
        // const original_state = board.game_state;
        // const original_fen = fen.toFEN(board, allocator) catch unreachable;
        // defer allocator.free(original_fen);

        mvs.makeMove(board, move);

        // King safety check
        const current_side = board.game_state.side_to_move;
        const opponent_side = brd.flipColor(current_side);
        const king_square = brd.getLSB(board.piece_bb[@intFromEnum(opponent_side)][@intFromEnum(brd.Pieces.King)]);

        if (mg.isAttacked(king_square, current_side, board)) {
            fails += 1;
            mvs.undoMove(board, move);

            // Post-undo FEN check for illegal moves
            // const illegal_fen = fen.toFEN(board, allocator) catch unreachable;
            // defer allocator.free(illegal_fen);
            // if (!std.mem.eql(u8, original_fen, illegal_fen)) {
            //     @panic("FEN mismatch after illegal move undo");
            // }
            continue;
        }

        // Recursive perft call
        const child_result = perft(mg, board, depth - 1, allocator);
        result.add(child_result);

        // if (depth == 4) {
        //     move.printAlgebraic();
        //     std.debug.print(" -> {} nodes\n", .{child_result.total});
        // }

        // Update move type counters
        if (depth == 1) {
            if (move.capture != 0) result.captures += child_result.total;
            if (move.en_passant != 0) result.en_passant += child_result.total;
            if (move.castling != 0) result.castling += child_result.total;
            if (move.promoted_piece != 0) result.promotions += child_result.total;
        }

        mvs.undoMove(board, move);

        // Post-undo state validation
        // const new_fen = fen.toFEN(board, allocator) catch unreachable;
        // defer allocator.free(new_fen);
        //
        // if (!std.mem.eql(u8, original_fen, new_fen)) {
        //     std.debug.print("\nFEN MISMATCH!\nOriginal: {s}\nNew: {s}\n", .{
        //         original_fen,
        //         new_fen,
        //     });
        //     @panic("FEN mismatch after move undo");
        // }
        //
        // if (!std.meta.eql(board.game_state, original_state)) {
        //     std.debug.print("\nSTATE MISMATCH!\nOriginal: {any}\nNew: {any}\n", .{
        //         original_state,
        //         board.game_state,
        //     });
        //     @panic("Game state mismatch after move undo");
        // }
    }

    return result;
}

const TestPosition = struct {
    fen: []const u8,
    depth: u32,
    expected: u64,
    captures: ?u64 = null,
    en_passant: ?u64 = null,
    castling: ?u64 = null,
    promotions: ?u64 = null,
};

pub fn runPerftTest() !void {
    const positions = [_]TestPosition{
        .{
            .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            .depth = 6,
            .expected = 119060324,
            .captures = 2812008,
            .en_passant = 5248,
            .castling = 0,
            .promotions = 0,
        },
        .{
            .fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            .depth = 6,
            .expected = 8031647685,
            .captures = 1558445089,
            .en_passant = 3577504,
            .castling = 184513607,
            .promotions = 56627920,
        },
        .{
            .fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1 ",
            .depth = 8,
            .expected = 3009794393,
            .captures = 267586558,
            .en_passant = 8009239,
            .castling = 0,
            .promotions = 6578076,
        },
        .{
            .fen = "r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1 ",
            .depth = 6,
            .expected = 706045033,
            .captures = 210369132,
            .en_passant = 212,
            .castling = 10882006,
            .promotions = 81102984,
        },
        .{
            .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            .depth = 6,
            .expected = 706045033,
            .captures = 210369132,
            .en_passant = 212,
            .castling = 10882006,
            .promotions = 81102984,
        },
    };

    var mg = mvs.MoveGen.init();
    const sBoard = brd.Board.init();

    for (positions) |pos| {
        std.debug.print("\nTesting position: {s}\n", .{pos.fen});
        var board = sBoard.copyBoard();
        _ = try fen.parseFEN(&board, pos.fen);

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};

        const result = perft(&mg, &board, pos.depth, gpa.allocator());

        var toReturn: usize = 0;

        // Verify results
        if (result.total != pos.expected) {
            std.debug.print("FAIL: Nodes expected {} got {}\n", .{ pos.expected, result.total });
            toReturn = 1;
        }

        if (pos.captures) |v| if (result.captures != v) {
            std.debug.print("FAIL: Captures expected {} got {}\n", .{ v, result.captures });
            toReturn = 1;
        };

        if (pos.en_passant) |v| if (result.en_passant != v) {
            std.debug.print("FAIL: En passant expected {} got {}\n", .{ v, result.en_passant });
            toReturn = 1;
        };

        if (pos.castling) |v| if (result.castling != v) {
            std.debug.print("FAIL: Castling expected {} got {}\n", .{ v, result.castling });
            toReturn = 1;
        };

        if (pos.promotions) |v| if (result.promotions != v) {
            std.debug.print("FAIL: Promotions expected {} got {}\n", .{ v, result.promotions });
            toReturn = 1;
        };

        if (toReturn == 0) {
            std.debug.print("PASSED!\n", .{});
        } else {
            return error.TestFailed;
        }
    }
}
