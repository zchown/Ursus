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
//   (E) QS rook stays       — QS rook already on its destination (d1);
//                              king slides left while rook doesn't move.
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
            .fen  = "bqnb1rkr/pp3ppp/3ppn2/2p5/5P2/P2P4/NPP1P1PP/BQ1BNRKR w HFhf - 2 9",
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
            .fen  = "1qnrkbbr/1pppppp1/p1n4p/8/P7/1P1N1P2/2PPP1PP/QN1RKBBR w HDhd - 0 9",
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

pub fn runShredderPerftTests() !void {
    const positions = [_]Chess960Position{
        .{ .fen = "rbk1rnbq/pppp1npp/4p3/5p2/4P1P1/7P/PPPP1P1N/RBKNR1BQ w EAea - 1 9", .depth = 6, .expected = 263574861, .note = "Shredder 860" },
        .{ .fen = "rknbrnb1/p1pppp1p/1p6/3N2p1/P3q1P1/8/1PPPPP1P/RKNBR1BQ w EAea - 1 9", .depth = 6, .expected = 812343987, .note = "Shredder 861" },
        .{ .fen = "rknrn1b1/ppppppqp/8/6p1/2P5/2P1BP2/PP2P1PP/RKNRNB1Q w DAda - 1 9", .depth = 6, .expected = 588518645, .note = "Shredder 862" },
        .{ .fen = "1k1rnqbb/npppppp1/r7/p2B3p/5P2/1N4P1/PPPPP2P/RK1RNQB1 w DAd - 0 9", .depth = 6, .expected = 1412437357, .note = "Shredder 863" },
        .{ .fen = "bbqr1rkn/pp1ppppp/8/2p5/1P2P1n1/7N/P1PP1P1P/BBQRKR1N w FD - 0 9", .depth = 6, .expected = 705170410, .note = "Shredder 864" },
        .{ .fen = "bqkr1rnn/1ppp1ppp/p4b2/4p3/P7/3PP2N/1PP2PPP/BQRBKR1N w FC - 3 9", .depth = 6, .expected = 197806842, .note = "Shredder 865" },
        .{ .fen = "bqrkrbnn/1pp1ppp1/8/p6p/3p4/P3P2P/QPPP1PP1/B1RKRBNN w ECec - 0 9", .depth = 6, .expected = 298629240, .note = "Shredder 866" },
        .{ .fen = "bqkrrnnb/2p1pppp/p7/1P1p4/8/2R3P1/PP1PPP1P/BQ1KRNNB w E - 0 9", .depth = 6, .expected = 1483524894, .note = "Shredder 867" },
        .{ .fen = "qbbrkrn1/p1pppn1p/8/1p3Pp1/2P5/8/PP1PPP1P/QBBRKRNN w FDfd - 0 9", .depth = 6, .expected = 300294295, .note = "Shredder 868" },
        .{ .fen = "qrbbkrnn/pp1p2pp/4p3/5p2/2p2P1P/2P5/PP1PP1P1/QRBBKRNN w FBfb - 0 9", .depth = 6, .expected = 228837930, .note = "Shredder 869" },
        .{ .fen = "qrbkrbn1/1pp1pppp/p2p4/8/5PPn/2P5/PP1PP3/QRBKRBNN w EBeb - 0 9", .depth = 6, .expected = 162883949, .note = "Shredder 870" },
        .{ .fen = "qrb1rnnb/pp1p1ppp/2pk4/4p3/1P2P3/1R6/P1PP1PPP/Q1BKRNNB w E - 4 9", .depth = 6, .expected = 421740856, .note = "Shredder 871" },
        .{ .fen = "qbrkbrn1/p1pppp1p/6n1/1p4p1/1P6/5P2/P1PPPBPP/QBRK1RNN w FCfc - 1 9", .depth = 6, .expected = 734656217, .note = "Shredder 872" },
        .{ .fen = "qrkbbr2/2pppppp/5nn1/pp1Q4/P7/3P4/1PP1PPPP/1RKBBRNN w FBfb - 0 9", .depth = 6, .expected = 1522548864, .note = "Shredder 873" },
        .{ .fen = "qrkrbbnn/pp2pp2/2pp2pp/1B6/P7/4P3/1PPP1PPP/QRKRB1NN w DBdb - 0 9", .depth = 6, .expected = 142507795, .note = "Shredder 874" },
        .{ .fen = "qrkrbnnb/p1pp1pp1/1p5p/4p3/1P6/6PN/PKPPPP1P/QR1RBN1B w db - 0 9", .depth = 6, .expected = 419552571, .note = "Shredder 875" },
        .{ .fen = "qbrkr1bn/p1p1pp1p/1p1p2n1/6p1/3P1P2/4P3/PPP3PP/QBKRRNBN w ec - 2 9", .depth = 6, .expected = 323905533, .note = "Shredder 876" },
        .{ .fen = "qrk1rnb1/p1pp1ppp/1p2Bbn1/8/4P3/6P1/PPPP1P1P/QRK1RNBN w EBeb - 1 9", .depth = 6, .expected = 807913585, .note = "Shredder 877" },
        .{ .fen = "1qkrnbbn/1rpppppp/pp6/5N2/P4P2/8/1PPPP1PP/QRKRNBB1 w DBd - 3 9", .depth = 6, .expected = 251694423, .note = "Shredder 878" },
        .{ .fen = "qrkr2bb/pppppppp/8/1n2n3/1N5P/1P6/P1PPPPP1/QRKR1NBB w DBdb - 1 9", .depth = 6, .expected = 479400272, .note = "Shredder 879" },
        .{ .fen = "bbrqkrnn/3ppppp/8/ppp5/6P1/4P2N/PPPPKP1P/BBRQ1R1N w fc - 0 9", .depth = 6, .expected = 470796854, .note = "Shredder 880" },
        .{ .fen = "brqbkrnn/1pp2p1p/3pp1p1/p5N1/8/1P6/P1PPPPPP/BRQBK1RN w Bfb - 0 9", .depth = 6, .expected = 402140795, .note = "Shredder 881" },
        .{ .fen = "br1krb1n/2qppppp/pp3n2/8/1P4P1/8/P1PPPP1P/1RQKRBNN w EBeb - 0 9", .depth = 6, .expected = 959651619, .note = "Shredder 882" },
        .{ .fen = "brqkr1nb/2ppp1pp/1p2np2/p7/2P1PN2/8/PP1P1PPP/BRQKRN1B w EBeb - 0 9", .depth = 6, .expected = 417396563, .note = "Shredder 883" },
        .{ .fen = "rbbqkrnn/3pppp1/p7/1pp4p/2P1P2P/8/PP1P1PP1/RBBQKRNN w FAfa - 0 9", .depth = 6, .expected = 404960259, .note = "Shredder 884" },
        .{ .fen = "rqbbkr1n/pp1p1p1p/4pn2/2p3p1/4P1P1/3P3P/PPP2P2/RQBBKRNN w FAfa - 0 9", .depth = 6, .expected = 335689685, .note = "Shredder 885" },
        .{ .fen = "rqbkrbnn/p1ppp3/1p3pp1/7p/3P4/P1P5/1PQ1PPPP/R1BKRBNN w EAea - 0 9", .depth = 6, .expected = 383515709, .note = "Shredder 886" },
        .{ .fen = "rqbkrnn1/pp2ppbp/3p4/2p3p1/2P5/1P3N1P/P2PPPP1/RQBKRN1B w EAea - 1 9", .depth = 6, .expected = 907579129, .note = "Shredder 887" },
        .{ .fen = "rbqkb1nn/1ppppr1p/p5p1/5p2/1P6/2P4P/P1KPPPP1/RBQ1BRNN w a - 1 9", .depth = 6, .expected = 140934555, .note = "Shredder 888" },
        .{ .fen = "rqkb1rnn/1pp1pp1p/p5p1/1b1p4/3P4/P5P1/RPP1PP1P/1QKBBRNN w Ffa - 1 9", .depth = 6, .expected = 188559137, .note = "Shredder 889" },
        .{ .fen = "rq1rbbnn/pkp1ppp1/3p3p/1p2N1P1/8/8/PPPPPP1P/RQKRBB1N w DA - 0 9", .depth = 6, .expected = 268393274, .note = "Shredder 890" },
        .{ .fen = "rqkrb2b/p2ppppp/2p3nn/1p6/5P2/PP1P4/2P1P1PP/RQKRBNNB w DAda - 1 9", .depth = 6, .expected = 485406712, .note = "Shredder 891" },
        .{ .fen = "rbqkr1bn/pp1ppp2/2p1n2p/6p1/8/4BPNP/PPPPP1P1/RBQKRN2 w EAea - 0 9", .depth = 6, .expected = 314327867, .note = "Shredder 892" },
        .{ .fen = "rqkbrnb1/2ppp1pp/pp3pn1/8/5P2/B2P4/PPP1P1PP/RQKBRN1N w EAea - 2 9", .depth = 6, .expected = 269460607, .note = "Shredder 893" },
        .{ .fen = "rqkrnbb1/p1p1pppp/1p4n1/3p4/7P/P3P3/1PPPBPP1/RQKRN1BN w DAda - 0 9", .depth = 6, .expected = 266047417, .note = "Shredder 894" },
        .{ .fen = "rqkrn1bb/p1ppp1pp/4n3/1p6/6p1/4N3/PPPPPPPP/RQKR2BB w DAda - 0 9", .depth = 6, .expected = 193376359, .note = "Shredder 895" },
        .{ .fen = "bbrkqr2/pppp1ppp/6nn/8/2P1p3/3PP2N/PP3PPP/BBRKQR1N w FCfc - 0 9", .depth = 6, .expected = 593204629, .note = "Shredder 896" },
        .{ .fen = "brk1qrnn/1pppbppp/4p3/8/1p6/P1P4P/3PPPP1/BRKBQRNN w FBfb - 1 9", .depth = 6, .expected = 355969349, .note = "Shredder 897" },
        .{ .fen = "1r1qrbnn/p1pkpppp/1p1p4/8/3P1PP1/P4b2/1PP1P2P/BRKQRBNN w EB - 1 9", .depth = 6, .expected = 401903030, .note = "Shredder 898" },
        .{ .fen = "1rkqrnnb/p1p1p1pp/1p1p4/3b1p1N/4P3/5N2/PPPP1PPP/BRKQR2B w EBeb - 1 9", .depth = 6, .expected = 791718847, .note = "Shredder 899" },
        .{ .fen = "rbbkq1rn/pppppppp/7n/8/P7/3P3P/1PPKPPP1/RBB1QRNN w a - 3 9", .depth = 6, .expected = 134818483, .note = "Shredder 900" },
        .{ .fen = "rkbbqr1n/1p1pppp1/2p2n2/p4NBp/8/3P4/PPP1PPPP/RK1BQRN1 w FAfa - 0 9", .depth = 6, .expected = 673756141, .note = "Shredder 901" },
        .{ .fen = "rkbqrb1n/3pBppp/ppp2n2/8/8/P2P4/1PP1PPPP/RK1QRBNN w EAea - 0 9", .depth = 6, .expected = 482288814, .note = "Shredder 902" },
        .{ .fen = "rkb1rn1b/ppppqppp/4p3/8/1P2n1P1/5Q2/P1PP1P1P/RKB1RNNB w EAea - 2 9", .depth = 6, .expected = 1389312729, .note = "Shredder 903" },
        .{ .fen = "r1kqbrnn/pp1pp1p1/7p/2P2p2/5b2/3P4/P1P1P1PP/RBKQBRNN w FAfa - 0 9", .depth = 6, .expected = 99039905, .note = "Shredder 904" },
        .{ .fen = "rkqbbr1n/ppp1ppp1/8/Q2p3p/4n3/3P1P2/PPP1P1PP/RK1BBRNN w FAfa - 2 9", .depth = 6, .expected = 1366087771, .note = "Shredder 905" },
        .{ .fen = "rkqrbbn1/p1ppppp1/Bp5p/8/P6n/2P1P3/1P1P1PPP/RKQRB1NN w DAda - 0 9", .depth = 6, .expected = 251179183, .note = "Shredder 906" },
        .{ .fen = "rkqrb1nb/1ppp1ppp/p7/4p3/5n2/3P2N1/PPPQPPPP/RK1RB1NB w DAda - 0 9", .depth = 6, .expected = 418191735, .note = "Shredder 907" },
        .{ .fen = "rbkqrnbn/pppp1p2/4p1p1/7p/7P/P2P4/BPP1PPP1/R1KQRNBN w EAea - 0 9", .depth = 6, .expected = 255021865, .note = "Shredder 908" },
        .{ .fen = "rkqbrnbn/pp1ppp2/8/2p3p1/P1P4p/5P2/1PKPP1PP/R1QBRNBN w ea - 0 9", .depth = 6, .expected = 328434174, .note = "Shredder 909" },
        .{ .fen = "rkqrnbbn/1p2pp1p/3p2p1/p1p5/P5PP/3N4/1PPPPP2/RKQR1BBN w DAda - 0 9", .depth = 6, .expected = 367311176, .note = "Shredder 910" },
        .{ .fen = "rk2rnbb/ppqppppp/2pn4/8/1P3P2/6P1/P1PPP1NP/RKQR1NBB w DAa - 1 9", .depth = 6, .expected = 505212747, .note = "Shredder 911" },
        .{ .fen = "b1krrqnn/pp1ppp1p/2p3p1/8/P3Pb1P/1P6/2PP1PP1/BBRKRQNN w EC - 0 9", .depth = 6, .expected = 800922511, .note = "Shredder 912" },
        .{ .fen = "1rkbrqnn/p1pp1ppp/1p6/8/P2Pp3/8/1PPKPPQP/BR1BR1NN w eb - 0 9", .depth = 6, .expected = 759318058, .note = "Shredder 913" },
        .{ .fen = "brkrqb1n/1pppp1pp/p7/3n1p2/P5P1/3PP3/1PP2P1P/BRKRQBNN w DBdb - 0 9", .depth = 6, .expected = 380267099, .note = "Shredder 914" },
        .{ .fen = "brkrqnnb/3pppp1/1p6/p1p4p/2P3P1/6N1/PP1PPP1P/BRKRQ1NB w DBdb - 0 9", .depth = 6, .expected = 406594531, .note = "Shredder 915" },
        .{ .fen = "r1bkrq1n/pp2pppp/3b1n2/2pp2B1/6P1/3P1P2/PPP1P2P/RB1KRQNN w EAea - 2 9", .depth = 6, .expected = 631209313, .note = "Shredder 916" },
        .{ .fen = "rk1brq1n/p1p1pppp/3p1n2/1p3b2/4P3/2NQ4/PPPP1PPP/RKBBR2N w EAea - 4 9", .depth = 6, .expected = 966310885, .note = "Shredder 917" },
        .{ .fen = "rkbrqbnn/1p2ppp1/B1p5/p2p3p/4P2P/8/PPPP1PP1/RKBRQ1NN w DAda - 0 9", .depth = 6, .expected = 515304215, .note = "Shredder 918" },
        .{ .fen = "rkbrqn1b/pp1pp1pp/2p2p2/5n2/8/2P2P2/PP1PP1PP/RKBRQ1NB w DAda - 0 9", .depth = 6, .expected = 167767913, .note = "Shredder 919" },
        .{ .fen = "rbkrbnn1/ppppp1pp/5q2/5p2/5P2/P3P2N/1PPP2PP/RBKRBQ1N w DAda - 3 9", .depth = 6, .expected = 838704143, .note = "Shredder 920" },
        .{ .fen = "rkr1bqnn/1ppp1p1p/p5p1/4p3/3PP2b/2P2P2/PP4PP/RKRBBQNN w CAca - 0 9", .depth = 6, .expected = 1024529879, .note = "Shredder 921" },
        .{ .fen = "rkrqbbnn/pppp3p/8/4ppp1/1PP4P/8/P2PPPP1/RKRQBBNN w CAca - 0 9", .depth = 6, .expected = 484884485, .note = "Shredder 922" },
        .{ .fen = "rkrqbn1b/pppp2pp/8/4pp2/1P1P2n1/5N2/P1P1PP1P/RKRQBN1B w CAca - 0 9", .depth = 6, .expected = 537354146, .note = "Shredder 923" },
        .{ .fen = "rbkrqnbn/p1p1ppp1/1p1p4/8/3PP2p/2PB4/PP3PPP/R1KRQNBN w DAda - 0 9", .depth = 6, .expected = 532603566, .note = "Shredder 924" },
        .{ .fen = "1krbqnbn/1p2pppp/r1pp4/p7/8/1P1P2PP/P1P1PP2/RKRBQNBN w CAc - 0 9", .depth = 6, .expected = 279864836, .note = "Shredder 925" },
        .{ .fen = "rkrq1b2/pppppppb/3n2np/2N5/4P3/7P/PPPP1PP1/RKRQ1BBN w CAca - 1 9", .depth = 6, .expected = 382218272, .note = "Shredder 926" },
        .{ .fen = "rkr1nnbb/ppp2p1p/3p1qp1/4p3/P5P1/3PN3/1PP1PP1P/RKRQN1BB w CAca - 1 9", .depth = 6, .expected = 468666425, .note = "Shredder 927" },
        .{ .fen = "bbrkrnqn/1p1ppppp/8/8/p2pP3/PP6/2P2PPP/BBRKRNQN w ECec - 0 9", .depth = 6, .expected = 509307623, .note = "Shredder 928" },
        .{ .fen = "brkbrnqn/ppp2p2/4p3/P2p2pp/6P1/5P2/1PPPP2P/BRKBRNQN w EBeb - 0 9", .depth = 6, .expected = 247750144, .note = "Shredder 929" },
        .{ .fen = "brkr1bqn/1pppppp1/3n3p/1p6/P7/4P1P1/1PPP1P1P/BRKRN1QN w DBdb - 0 9", .depth = 6, .expected = 817877189, .note = "Shredder 930" },
        .{ .fen = "brkr1qnb/pppp2pp/2B1p3/5p2/2n5/6PP/PPPPPPN1/BRKR1QN1 w DBdb - 1 9", .depth = 6, .expected = 667089231, .note = "Shredder 931" },
        .{ .fen = "rbbkrnqn/p1p1p1pp/8/1p1p4/1P1Pp3/6N1/P1P2PPP/RBBKRNQ1 w EAea - 0 9", .depth = 6, .expected = 397454100, .note = "Shredder 932" },
        .{ .fen = "rkbbrn1n/pppppp2/5q1p/6p1/3P3P/4P3/PPP2PP1/RKBBRNQN w EAea - 1 9", .depth = 6, .expected = 485037906, .note = "Shredder 933" },
        .{ .fen = "rkbr1bq1/ppnppppp/6n1/2p5/2P1N2P/8/PP1PPPP1/RKBRNBQ1 w DAda - 3 9", .depth = 6, .expected = 234041078, .note = "Shredder 934" },
        .{ .fen = "1kbrnqnb/r1ppppp1/8/pp5p/8/1P1NP3/P1PP1PPP/RKB1RQNB w Ad - 2 9", .depth = 6, .expected = 357030697, .note = "Shredder 935" },
        .{ .fen = "rbkrb1qn/1pp1ppp1/3pn2p/pP6/8/4N1P1/P1PPPP1P/RBKRB1QN w DAda - 0 9", .depth = 6, .expected = 236013157, .note = "Shredder 936" },
        .{ .fen = "rkrbbnqn/ppppp3/5p2/6pp/5PBP/4P3/PPPP2P1/RKR1BNQN w CAca - 0 9", .depth = 6, .expected = 669256602, .note = "Shredder 937" },
        .{ .fen = "rkr1bb1n/ppppp1pp/5p2/4n3/3QP3/5P2/RPPP2PP/1KRNBB1N w Cca - 1 9", .depth = 6, .expected = 1501852662, .note = "Shredder 938" },
        .{ .fen = "rkr1bqnb/pp1ppppp/8/2pN4/1P6/5N2/P1PPnPPP/RKR1BQ1B w CAca - 0 9", .depth = 6, .expected = 463032124, .note = "Shredder 939" },
        .{ .fen = "rbkrnqb1/2ppppp1/p5np/1p6/8/3N4/PPPPPPPP/RBKRQNB1 w DAda - 2 9", .depth = 6, .expected = 1339365649, .note = "Shredder 940" },
        .{ .fen = "rkrbnqb1/p1pppnpp/5p2/1p6/2P5/1P1P1N2/P3PPPP/RKRB1QBN w CAca - 0 9", .depth = 6, .expected = 222026485, .note = "Shredder 941" },
        .{ .fen = "rkr1qbbn/ppppppp1/4n3/7p/8/P7/KPPPPPPP/R1RNQBBN w ca - 0 9", .depth = 6, .expected = 163291279, .note = "Shredder 942" },
        .{ .fen = "rkrnqnb1/1ppppp2/p5p1/7p/8/P1bPP3/1PP1QPPP/RKRN1NBB w CAca - 0 9", .depth = 6, .expected = 331083405, .note = "Shredder 943" },
        .{ .fen = "b2krn1q/p1rppppp/1Q3n2/2p1b3/1P4P1/8/P1PPPP1P/BBRKRNN1 w ECe - 3 9", .depth = 6, .expected = 1650202838, .note = "Shredder 944" },
        .{ .fen = "brkbrnn1/pp1pppp1/7q/2p5/6Pp/4P1NP/PPPP1P2/BRKBR1NQ w EBeb - 2 9", .depth = 6, .expected = 936568065, .note = "Shredder 945" },
        .{ .fen = "brkrnb1q/pp1p1ppp/2p1p3/5n2/1P6/5N1N/P1PPPPPP/BRKR1B1Q w DBdb - 1 9", .depth = 6, .expected = 755334868, .note = "Shredder 946" },
        .{ .fen = "brkr1nqb/pp1p1pp1/2pn3p/P3p3/4P3/6P1/1PPP1P1P/BRKRNNQB w DBdb - 0 9", .depth = 6, .expected = 1035373339, .note = "Shredder 947" },
        .{ .fen = "r1bkrn1q/ppbppppp/5n2/2p5/3P4/P6N/1PP1PPPP/RBBKRNQ1 w EAea - 3 9", .depth = 6, .expected = 578210135, .note = "Shredder 948" },
        .{ .fen = "rkbbrnnq/pp2pppp/8/2pp4/P1P5/1P3P2/3PP1PP/RKBBRNNQ w EAea - 1 9", .depth = 6, .expected = 329615708, .note = "Shredder 949" },
        .{ .fen = "rkbr1b1q/p1pppppp/1p1n4/7n/5QP1/3N4/PPPPPP1P/RKBR1BN1 w DAda - 4 9", .depth = 6, .expected = 842265141, .note = "Shredder 950" },
        .{ .fen = "rkbr1nqb/pppp2np/8/4ppp1/1P6/6N1/P1PPPPPP/RKBRN1QB w DAda - 1 9", .depth = 6, .expected = 261247606, .note = "Shredder 951" },
        .{ .fen = "rbkr1nnq/p1p1pp1p/1p4p1/3p4/b3P3/4N3/PPPPNPPP/RBKRB1Q1 w DAda - 0 9", .depth = 6, .expected = 745802405, .note = "Shredder 952" },
        .{ .fen = "rkrbb1nq/p2pppp1/1p4n1/2p4p/3N4/4P1P1/PPPP1P1P/RKRBBN1Q w CAca - 0 9", .depth = 6, .expected = 441578567, .note = "Shredder 953" },
        .{ .fen = "rkrnbb1q/pp2pp1p/6pn/2pp4/2B1P2P/8/PPPP1PP1/RKRNB1NQ w CAca - 0 9", .depth = 6, .expected = 712787248, .note = "Shredder 954" },
        .{ .fen = "rk2bnqb/pprpppp1/4n2p/2p5/P7/3P2NP/1PP1PPP1/RKRNB1QB w CAa - 1 9", .depth = 6, .expected = 323043654, .note = "Shredder 955" },
        .{ .fen = "r1krnnbq/pp1ppp1p/6p1/2p5/2P5/P3P3/Rb1P1PPP/1BKRNNBQ w Dda - 0 9", .depth = 6, .expected = 562, .note = "Shredder 956" },
        .{ .fen = "1krbnnbq/1pp1p1pp/r7/p2p1p2/3PP3/2P3P1/PP3P1P/RKRBNNBQ w CAc - 0 9", .depth = 6, .expected = 787205262, .note = "Shredder 957" },
        .{ .fen = "rkr1nbbq/2ppp1pp/1pn5/p4p2/P6P/3P4/1PP1PPPB/RKRNNB1Q w CAca - 1 9", .depth = 6, .expected = 341262639, .note = "Shredder 958" },
        .{ .fen = "rkrnnqbb/p1ppp2p/6p1/4Pp2/5p2/8/PPPP2PP/RKRNN1BB w CAca - 0 9", .depth = 6, .expected = 915268405, .note = "Shredder 959" },
        .{ .fen = "bbq1nr1r/pppppk1p/2n2p2/6p1/P4P2/4P1P1/1PPP3P/BBQNNRKR w HF - 1 9", .depth = 6, .expected = 280056112, .note = "Shredder 960" },
    };

    var allocator = std.heap.page_allocator;
    const mg = try allocator.create(mvs.MoveGen);
    mg.init();
    defer allocator.destroy(mg);

    var template = brd.Board.init();
    var any_failed = false;

    std.debug.print("\n╔══════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║             Shredder Depth 6 Perft Suite             ║\n", .{});
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
    try runShredderPerftTests();

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
}
