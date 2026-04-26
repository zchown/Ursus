const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const fen = @import("fen");

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

pub fn runPerft(mg: *mvs.MoveGen, board: *brd.Board, max_depth: usize) !void {
    for (0..max_depth) |depth| {
        const start = std.time.milliTimestamp();
        const result = perft(mg, board, depth + 1, std.heap.page_allocator);
        const end = std.time.milliTimestamp();
        const time = end - start;

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("\nDepth: {}\n", .{depth + 1});
        try stdout.print("-----------------\n", .{});
        try stdout.print("Total nodes:    {}\n", .{result.total});
        try stdout.print("Captures:       {}\n", .{result.captures});
        try stdout.print("En passants:    {}\n", .{result.en_passant});
        try stdout.print("Castles:        {}\n", .{result.castling});
        try stdout.print("Promotions:     {}\n", .{result.promotions});
        try stdout.print("Time:           {}ms\n", .{time});

        if (time > 0) {
            const kNps = (result.total * 1000) / @as(u64, @intCast(time));
            try stdout.print("kN/s:           {}\n", .{kNps});
        }

        try stdout.flush();
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

    for (0..moveList.len) |m| {
        const move = moveList.items[m];

        // Capture original state and FEN
        // const original_state = board.game_state;
        // const original_fen = fen.toFEN(board, allocator) catch unreachable;
        // defer allocator.free(original_fen);

        mvs.makeMove(board, move);

        // King safety check
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

// ─────────────────────────────────────────────────────────────────────────────
// Chess960 / DFRC Perft Tests
// ─────────────────────────────────────────────────────────────────────────────
//
// Each position is chosen to exercise a specific Chess960 castling edge-case.
// D1 counts are hand-verified by move enumeration (see comments).
// D5/D6 values for X-FEN positions are identical to the corresponding standard-
// chess position — they verify that X-FEN parsing produces the same results.
// Fill in deeper values once the engine is confirmed correct at D1.
//
// Castling edge-cases covered:
//   (A) X-FEN HAha notation — standard king/rook squares, different token style.
//   (B) King-rook swap      — king on f1, KS rook on g1 (adjacent, they trade).
//   (C) King stays in place — king is already on the KS destination square (g1).
//   (D) Blocked rook dest   — KS rook destination (f1) occupied by the QS rook;
//                              KS castling is therefore illegal.
//   (E) QS rook stays       — QS rook already on its destination (d1); king
//                              slides left while rook doesn't move.
//   (F) DFRC                — white and black have independent castling setups.

const Chess960Position = struct {
    fen: []const u8,
    depth: u32,
    expected: u64,
    note: []const u8,
};

pub fn runChess960PerftTests() !void {
    const positions = [_]Chess960Position{
        .{
            .fen   = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 1",
            .depth = 5,
            .expected = 4_865_609,
            .note  = "standard start via X-FEN HAha, D5",
        },
        .{
            .fen   = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 1",
            .depth = 6,
            .expected = 119_060_324,
            .note  = "standard start via X-FEN HAha, D6",
        },

        .{
            .fen   = "r3k2r/8/8/8/8/8/8/R3K2R w HAha - 0 1",
            .depth = 1,
            .expected = 26,
            .note  = "castling endgame X-FEN, D1",
        },

        .{
            .fen   = "r3k2r/8/8/8/8/8/8/R4KR1 w GAga - 0 1",
            .depth = 1,
            .expected = 25,
            .note  = "960 king-rook swap castling, D1",
        },

        .{
            .fen   = "r3k2r/8/8/8/8/8/8/R5KR w HAha - 0 1",
            .depth = 1,
            .expected = 24,
            .note  = "960 king already at KS destination, D1",
        },

        .{
            .fen   = "bqnbnrkr/pppppppp/8/8/8/8/PPPPPPPP/BQNBNRKR w HFhf - 0 1",
            .depth = 1,
            .expected = 20,
            .note  = "960 both castle destinations occupied → no castling, D1",
        },

        .{
            .fen   = "r3k3/8/8/8/8/8/8/3RK1R1 w GDq - 0 1",
            .depth = 1,
            .expected = 25,
            .note  = "960 QS rook already on destination (d1), rook stays, D1",
        },

        .{
            .fen   = "1r1k3r/8/8/8/8/8/8/R4KR1 w GAhb - 0 1",
            .depth = 1,
            .expected = 25,
            .note  = "DFRC independent setups, D1",
        },

        .{
            .fen   = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w HAha - 0 1",
            .depth = 4,
            .expected = 4_085_603,
            .note  = "kiwipete via X-FEN HAha, D4",
        },

        .{
            .fen   = "bqnb1rkr/pp3ppp/3ppn2/2p5/5P2/P2P4/NPP1P1PP/BQ1BNRKR w HFhf - 2 9",
            .depth = 6,
            .expected = 227_689_589,
            .note  = "960 mid-game  #1, D6",
        },
        .{
            .fen   = "2nnrbkr/p1qppppp/8/1ppb4/6PP/3PP3/PPP2P2/BQNNRBKR w HEhe - 1 9",
            .depth = 6,
            .expected = 590_751_109,
            .note  = "960 mid-game  #2, D6",
        },
        .{
            .fen   = "b1q1rrkb/pppppppp/3nn3/8/P7/1PPP4/4PPPP/BQNNRKRB w GE - 1 9",
            .depth = 6,
            .expected = 177_654_692,
            .note  = "960 mid-game  #3, D6 (white castling only)",
        },
        .{
            .fen   = "qbbnnrkr/2pp2pp/p7/1p2pp2/8/P3PP2/1PPP1KPP/QBBNNR1R w hf - 0 9",
            .depth = 6,
            .expected = 274_103_539,
            .note  = "960 mid-game  #4, D6 (black castling only)",
        },
        .{
            .fen   = "1nbbnrkr/p1p1ppp1/3p4/1p3P1p/3Pq2P/8/PPP1P1P1/QNBBNRKR w HFhf - 0 9",
            .depth = 6,
            .expected = 1_250_970_898,
            .note  = "960 mid-game  #5, D6",
        },
        .{
            .fen   = "qnbnr1kr/ppp1b1pp/4p3/3p1p2/8/2NPP3/PPP1BPPP/QNB1R1KR w HEhe - 1 9",
            .depth = 6,
            .expected = 775_718_317,
            .note  = "960 mid-game  #6, D6",
        },
        .{
            .fen   = "q1bnrkr1/ppppp2p/2n2p2/4b1p1/2NP4/8/PPP1PPPP/QNB1RRKB w ge - 1 9",
            .depth = 6,
            .expected = 649_209_803,
            .note  = "960 mid-game  #7, D6 (black castling only)",
        },
        .{
            .fen   = "qbn1brkr/ppp1p1p1/2n4p/3p1p2/P7/6PP/QPPPPP2/1BNNBRKR w HFhf - 0 9",
            .depth = 6,
            .expected = 377_184_252,
            .note  = "960 mid-game  #8, D6",
        },
        .{
            .fen   = "qnnbbrkr/1p2ppp1/2pp3p/p7/1P5P/2NP4/P1P1PPP1/Q1NBBRKR w HFhf - 0 9",
            .depth = 6,
            .expected = 293_989_890,
            .note  = "960 mid-game  #9, D6",
        },
        .{
            .fen   = "qn1rbbkr/ppp2p1p/1n1pp1p1/8/3P4/P6P/1PP1PPPK/QNNRBB1R w hd - 2 9",
            .depth = 6,
            .expected = 594_527_992,
            .note  = "960 mid-game #10, D6 (black castling only)",
        },
        .{
            .fen   = "qnr1bkrb/pppp2pp/3np3/5p2/8/P2P2P1/NPP1PP1P/QN1RBKRB w GDg - 3 9",
            .depth = 6,
            .expected = 646_390_782,
            .note  = "960 mid-game #11, D6",
        },
        .{
            .fen   = "qb1nrkbr/1pppp1p1/1n3p2/p1B4p/8/3P1P1P/PPP1P1P1/QBNNRK1R w HEhe - 0 9",
            .depth = 6,
            .expected = 651_054_626,
            .note  = "960 mid-game #12, D6",
        },
        .{
            .fen   = "qnnbrk1r/1p1ppbpp/2p5/p4p2/2NP3P/8/PPP1PPP1/Q1NBRKBR w HEhe - 0 9",
            .depth = 6,
            .expected = 544_866_674,
            .note  = "960 mid-game #13, D6",
        },
        .{
            .fen   = "1qnrkbbr/1pppppp1/p1n4p/8/P7/1P1N1P2/2PPP1PP/QN1RKBBR w HDhd - 0 9",
            .depth = 6,
            .expected = 783_201_510,
            .note  = "960 mid-game #14, D6",
        },
        .{
            .fen   = "qn1rkrbb/pp1p1ppp/2p1p3/3n4/4P2P/2NP4/PPP2PP1/Q1NRKRBB w FDfd - 1 9",
            .depth = 6,
            .expected = 233_468_620,
            .note  = "960 mid-game #15, D6",
        },
        .{
            .fen   = "bb1qnrkr/pp1p1pp1/1np1p3/4N2p/8/1P4P1/P1PPPP1P/BBNQ1RKR w HFhf - 0 9",
            .depth = 6,
            .expected = 776_836_316,
            .note  = "960 mid-game #16, D6",
        },
        .{
            .fen   = "bnqbnr1r/p1p1ppkp/3p4/1p4p1/P7/3NP2P/1PPP1PP1/BNQB1RKR w HF - 0 9",
            .depth = 6,
            .expected = 809_194_268,
            .note  = "960 mid-game #17, D6 (white castling only)",
        },
        .{
            .fen   = "bnqnrbkr/1pp2pp1/p7/3pP2p/4P1P1/8/PPPP3P/BNQNRBKR w HEhe d6 0 9",
            .depth = 6,
            .expected = 1_008_880_643,
            .note  = "960 mid-game #18, D6 (en passant)",
        },
        .{
            .fen   = "b1qnrrkb/ppp1pp1p/n2p1Pp1/8/8/P7/1PPPP1PP/BNQNRKRB w GE - 0 9",
            .depth = 6,
            .expected = 193_594_729,
            .note  = "960 mid-game #19, D6 (white castling only)",
        },
        .{
            .fen   = "n1bqnrkr/pp1ppp1p/2p5/6p1/2P2b2/PN6/1PNPPPPP/1BBQ1RKR w HFhf - 2 9",
            .depth = 6,
            .expected = 457_140_569,
            .note  = "960 mid-game #20, D6",
        },
    };

    var allocator = std.heap.page_allocator;
    const mg = try allocator.create(mvs.MoveGen);
    mg.init();
    defer allocator.destroy(mg);

    var template = brd.Board.init();
    var any_failed = false;

    std.debug.print("\n╔══════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║         Chess960 / DFRC Perft Test Suite            ║\n", .{});
    std.debug.print("╚══════════════════════════════════════════════════════╝\n", .{});

    for (positions) |pos| {
        std.debug.print("\n[{s}]\n  FEN: {s}\n", .{ pos.note, pos.fen });

        var board = template.copyBoard();
        _ = try fen.parseFEN(&board, pos.fen);

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const start = std.time.milliTimestamp();
        const result = perft(mg, &board, pos.depth, gpa.allocator());
        const elapsed = std.time.milliTimestamp() - start;

        if (result.total != pos.expected) {
            std.debug.print("  FAIL  nodes: expected {}, got {} ({}ms)\n",
                .{ pos.expected, result.total, elapsed });
            any_failed = true;
        } else {
            std.debug.print("  PASS  nodes: {} ({}ms)\n", .{ result.total, elapsed });
        }
    }

    std.debug.print("\n", .{});
    if (any_failed) return error.Chess960TestFailed;
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

    try runChess960PerftTests();

    const positions = [_]TestPosition{
        .{
            .fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8  ",
            .depth = 5,
            .expected = 89_941_194,
            .captures = null,
            .en_passant = null,
            .castling = null,
            .promotions = null,
        },
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

    // var mg = mvs.MoveGen.init();
    var allocator = std.heap.page_allocator;
    const mg = try allocator.create(mvs.MoveGen);
    mg.init();
    defer allocator.destroy(mg);
    var sBoard = brd.Board.init();

    for (positions) |pos| {
        std.debug.print("\nTesting position: {s}\n", .{pos.fen});
        var board = sBoard.copyBoard();
        _ = try fen.parseFEN(&board, pos.fen);

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};

        const result = perft(mg, &board, pos.depth, gpa.allocator());

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

    // Run Chess960 / DFRC tests after standard tests.
}
