const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;
const mvs = root.moves;
const fen = root.fen;
const perft = root.perft;

const Case = struct {
    fen: []const u8,
    depth: u32,
    nodes: u64,
};

const DetailedCase = struct {
    fen: []const u8,
    depth: u32,
    expected: perft.PerftResult,
};

const detailed = [_]DetailedCase{
    .{
        .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        .depth = 6,
        .expected = .{ .total = 119_060_324, .captures = 2_812_008, .en_passant = 5_248, .castling = 0, .promotions = 0 },
    },
    .{
        .fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        .depth = 6,
        .expected = .{ .total = 8_031_647_685, .captures = 1_558_445_089, .en_passant = 3_577_504, .castling = 184_513_607, .promotions = 56_627_920 },
    },
    .{
        .fen = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
        .depth = 8,
        .expected = .{ .total = 3_009_794_393, .captures = 267_586_558, .en_passant = 8_009_239, .castling = 0, .promotions = 6_578_076 },
    },
    .{
        .fen = "r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1",
        .depth = 6,
        .expected = .{ .total = 706_045_033, .captures = 210_369_132, .en_passant = 212, .castling = 10_882_006, .promotions = 81_102_984 },
    },
    .{
        .fen = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
        .depth = 6,
        .expected = .{ .total = 706_045_033, .captures = 210_369_132, .en_passant = 212, .castling = 10_882_006, .promotions = 81_102_984 },
    },
};

const cases = [_]Case{
    .{ .fen = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", .depth = 5, .nodes = 89_941_194 },

    // X-FEN castling on standard setups
    .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 1", .depth = 5, .nodes = 4_865_609 },
    .{ .fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w HAha - 0 1", .depth = 6, .nodes = 119_060_324 },
    .{ .fen = "r3k2r/8/8/8/8/8/8/R3K2R w HAha - 0 1", .depth = 1, .nodes = 26 },
    .{ .fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w HAha - 0 1", .depth = 4, .nodes = 4_085_603 },

    // 960 castling edge cases
    .{ .fen = "r3k2r/8/8/8/8/8/8/R4KR1 w GAga - 0 1", .depth = 1, .nodes = 25 },
    .{ .fen = "r3k2r/8/8/8/8/8/8/R5KR w HAha - 0 1", .depth = 1, .nodes = 24 },
    .{ .fen = "bqnbnrkr/pppppppp/8/8/8/8/PPPPPPPP/BQNBNRKR w HFhf - 0 1", .depth = 1, .nodes = 20 },
    .{ .fen = "r3k3/8/8/8/8/8/8/3RK1R1 w GDq - 0 1", .depth = 1, .nodes = 25 },
    .{ .fen = "1r1k3r/8/8/8/8/8/8/R4KR1 w GAhb - 0 1", .depth = 1, .nodes = 25 },

    // 960 midgames
    .{ .fen = "bqnb1rkr/pp3ppp/3ppn2/2p5/5P2/P2P4/NPP1P1PP/BQ1BNRKR w HFhf - 2 9", .depth = 6, .nodes = 227_689_589 },
    .{ .fen = "2nnrbkr/p1qppppp/8/1ppb4/6PP/3PP3/PPP2P2/BQNNRBKR w HEhe - 1 9", .depth = 6, .nodes = 590_751_109 },
    .{ .fen = "b1q1rrkb/pppppppp/3nn3/8/P7/1PPP4/4PPPP/BQNNRKRB w GE - 1 9", .depth = 6, .nodes = 177_654_692 },
    .{ .fen = "qbbnnrkr/2pp2pp/p7/1p2pp2/8/P3PP2/1PPP1KPP/QBBNNR1R w hf - 0 9", .depth = 6, .nodes = 274_103_539 },
    .{ .fen = "1nbbnrkr/p1p1ppp1/3p4/1p3P1p/3Pq2P/8/PPP1P1P1/QNBBNRKR w HFhf - 0 9", .depth = 6, .nodes = 1_250_970_898 },
    .{ .fen = "qnbnr1kr/ppp1b1pp/4p3/3p1p2/8/2NPP3/PPP1BPPP/QNB1R1KR w HEhe - 1 9", .depth = 6, .nodes = 775_718_317 },
    .{ .fen = "q1bnrkr1/ppppp2p/2n2p2/4b1p1/2NP4/8/PPP1PPPP/QNB1RRKB w ge - 1 9", .depth = 6, .nodes = 649_209_803 },
    .{ .fen = "qbn1brkr/ppp1p1p1/2n4p/3p1p2/P7/6PP/QPPPPP2/1BNNBRKR w HFhf - 0 9", .depth = 6, .nodes = 377_184_252 },
    .{ .fen = "qnnbbrkr/1p2ppp1/2pp3p/p7/1P5P/2NP4/P1P1PPP1/Q1NBBRKR w HFhf - 0 9", .depth = 6, .nodes = 293_989_890 },
    .{ .fen = "qn1rbbkr/ppp2p1p/1n1pp1p1/8/3P4/P6P/1PP1PPPK/QNNRBB1R w hd - 2 9", .depth = 6, .nodes = 594_527_992 },
    .{ .fen = "qnr1bkrb/pppp2pp/3np3/5p2/8/P2P2P1/NPP1PP1P/QN1RBKRB w GDg - 3 9", .depth = 6, .nodes = 646_390_782 },
    .{ .fen = "qb1nrkbr/1pppp1p1/1n3p2/p1B4p/8/3P1P1P/PPP1P1P1/QBNNRK1R w HEhe - 0 9", .depth = 6, .nodes = 651_054_626 },
    .{ .fen = "qnnbrk1r/1p1ppbpp/2p5/p4p2/2NP3P/8/PPP1PPP1/Q1NBRKBR w HEhe - 0 9", .depth = 6, .nodes = 544_866_674 },
    .{ .fen = "1qnrkbbr/1pppppp1/p1n4p/8/P7/1P1N1P2/2PPP1PP/QN1RKBBR w HDhd - 0 9", .depth = 6, .nodes = 783_201_510 },
    .{ .fen = "qn1rkrbb/pp1p1ppp/2p1p3/3n4/4P2P/2NP4/PPP2PP1/Q1NRKRBB w FDfd - 1 9", .depth = 6, .nodes = 233_468_620 },
    .{ .fen = "bb1qnrkr/pp1p1pp1/1np1p3/4N2p/8/1P4P1/P1PPPP1P/BBNQ1RKR w HFhf - 0 9", .depth = 6, .nodes = 776_836_316 },
    .{ .fen = "bnqbnr1r/p1p1ppkp/3p4/1p4p1/P7/3NP2P/1PPP1PP1/BNQB1RKR w HF - 0 9", .depth = 6, .nodes = 809_194_268 },
    .{ .fen = "bnqnrbkr/1pp2pp1/p7/3pP2p/4P1P1/8/PPPP3P/BNQNRBKR w HEhe d6 0 9", .depth = 6, .nodes = 1_008_880_643 },
    .{ .fen = "b1qnrrkb/ppp1pp1p/n2p1Pp1/8/8/P7/1PPPP1PP/BNQNRKRB w GE - 0 9", .depth = 6, .nodes = 193_594_729 },
    .{ .fen = "n1bqnrkr/pp1ppp1p/2p5/6p1/2P2b2/PN6/1PNPPPPP/1BBQ1RKR w HFhf - 2 9", .depth = 6, .nodes = 457_140_569 },

    // Shredder 860-960
    .{ .fen = "rbk1rnbq/pppp1npp/4p3/5p2/4P1P1/7P/PPPP1P1N/RBKNR1BQ w EAea - 1 9", .depth = 6, .nodes = 263_574_861 },
    .{ .fen = "rknbrnb1/p1pppp1p/1p6/3N2p1/P3q1P1/8/1PPPPP1P/RKNBR1BQ w EAea - 1 9", .depth = 6, .nodes = 812_343_987 },
    .{ .fen = "rknrn1b1/ppppppqp/8/6p1/2P5/2P1BP2/PP2P1PP/RKNRNB1Q w DAda - 1 9", .depth = 6, .nodes = 588_518_645 },
    .{ .fen = "1k1rnqbb/npppppp1/r7/p2B3p/5P2/1N4P1/PPPPP2P/RK1RNQB1 w DAd - 0 9", .depth = 6, .nodes = 1_412_437_357 },
    .{ .fen = "bbqr1rkn/pp1ppppp/8/2p5/1P2P1n1/7N/P1PP1P1P/BBQRKR1N w FD - 0 9", .depth = 6, .nodes = 705_170_410 },
    .{ .fen = "bqkr1rnn/1ppp1ppp/p4b2/4p3/P7/3PP2N/1PP2PPP/BQRBKR1N w FC - 3 9", .depth = 6, .nodes = 197_806_842 },
    .{ .fen = "bqrkrbnn/1pp1ppp1/8/p6p/3p4/P3P2P/QPPP1PP1/B1RKRBNN w ECec - 0 9", .depth = 6, .nodes = 298_629_240 },
    .{ .fen = "bqkrrnnb/2p1pppp/p7/1P1p4/8/2R3P1/PP1PPP1P/BQ1KRNNB w E - 0 9", .depth = 6, .nodes = 1_483_524_894 },
    .{ .fen = "qbbrkrn1/p1pppn1p/8/1p3Pp1/2P5/8/PP1PPP1P/QBBRKRNN w FDfd - 0 9", .depth = 6, .nodes = 300_294_295 },
    .{ .fen = "qrbbkrnn/pp1p2pp/4p3/5p2/2p2P1P/2P5/PP1PP1P1/QRBBKRNN w FBfb - 0 9", .depth = 6, .nodes = 228_837_930 },
    .{ .fen = "qrbkrbn1/1pp1pppp/p2p4/8/5PPn/2P5/PP1PP3/QRBKRBNN w EBeb - 0 9", .depth = 6, .nodes = 162_883_949 },
    .{ .fen = "qrb1rnnb/pp1p1ppp/2pk4/4p3/1P2P3/1R6/P1PP1PPP/Q1BKRNNB w E - 4 9", .depth = 6, .nodes = 421_740_856 },
    .{ .fen = "qbrkbrn1/p1pppp1p/6n1/1p4p1/1P6/5P2/P1PPPBPP/QBRK1RNN w FCfc - 1 9", .depth = 6, .nodes = 734_656_217 },
    .{ .fen = "qrkbbr2/2pppppp/5nn1/pp1Q4/P7/3P4/1PP1PPPP/1RKBBRNN w FBfb - 0 9", .depth = 6, .nodes = 1_522_548_864 },
    .{ .fen = "qrkrbbnn/pp2pp2/2pp2pp/1B6/P7/4P3/1PPP1PPP/QRKRB1NN w DBdb - 0 9", .depth = 6, .nodes = 142_507_795 },
    .{ .fen = "qrkrbnnb/p1pp1pp1/1p5p/4p3/1P6/6PN/PKPPPP1P/QR1RBN1B w db - 0 9", .depth = 6, .nodes = 419_552_571 },
    .{ .fen = "qbrkr1bn/p1p1pp1p/1p1p2n1/6p1/3P1P2/4P3/PPP3PP/QBKRRNBN w ec - 2 9", .depth = 6, .nodes = 323_905_533 },
    .{ .fen = "qrk1rnb1/p1pp1ppp/1p2Bbn1/8/4P3/6P1/PPPP1P1P/QRK1RNBN w EBeb - 1 9", .depth = 6, .nodes = 807_913_585 },
    .{ .fen = "1qkrnbbn/1rpppppp/pp6/5N2/P4P2/8/1PPPP1PP/QRKRNBB1 w DBd - 3 9", .depth = 6, .nodes = 251_694_423 },
    .{ .fen = "qrkr2bb/pppppppp/8/1n2n3/1N5P/1P6/P1PPPPP1/QRKR1NBB w DBdb - 1 9", .depth = 6, .nodes = 479_400_272 },
    .{ .fen = "bbrqkrnn/3ppppp/8/ppp5/6P1/4P2N/PPPPKP1P/BBRQ1R1N w fc - 0 9", .depth = 6, .nodes = 470_796_854 },
    .{ .fen = "brqbkrnn/1pp2p1p/3pp1p1/p5N1/8/1P6/P1PPPPPP/BRQBK1RN w Bfb - 0 9", .depth = 6, .nodes = 402_140_795 },
    .{ .fen = "br1krb1n/2qppppp/pp3n2/8/1P4P1/8/P1PPPP1P/1RQKRBNN w EBeb - 0 9", .depth = 6, .nodes = 959_651_619 },
    .{ .fen = "brqkr1nb/2ppp1pp/1p2np2/p7/2P1PN2/8/PP1P1PPP/BRQKRN1B w EBeb - 0 9", .depth = 6, .nodes = 417_396_563 },
    .{ .fen = "rbbqkrnn/3pppp1/p7/1pp4p/2P1P2P/8/PP1P1PP1/RBBQKRNN w FAfa - 0 9", .depth = 6, .nodes = 404_960_259 },
    .{ .fen = "rqbbkr1n/pp1p1p1p/4pn2/2p3p1/4P1P1/3P3P/PPP2P2/RQBBKRNN w FAfa - 0 9", .depth = 6, .nodes = 335_689_685 },
    .{ .fen = "rqbkrbnn/p1ppp3/1p3pp1/7p/3P4/P1P5/1PQ1PPPP/R1BKRBNN w EAea - 0 9", .depth = 6, .nodes = 383_515_709 },
    .{ .fen = "rqbkrnn1/pp2ppbp/3p4/2p3p1/2P5/1P3N1P/P2PPPP1/RQBKRN1B w EAea - 1 9", .depth = 6, .nodes = 907_579_129 },
    .{ .fen = "rbqkb1nn/1ppppr1p/p5p1/5p2/1P6/2P4P/P1KPPPP1/RBQ1BRNN w a - 1 9", .depth = 6, .nodes = 140_934_555 },
    .{ .fen = "rqkb1rnn/1pp1pp1p/p5p1/1b1p4/3P4/P5P1/RPP1PP1P/1QKBBRNN w Ffa - 1 9", .depth = 6, .nodes = 188_559_137 },
    .{ .fen = "rq1rbbnn/pkp1ppp1/3p3p/1p2N1P1/8/8/PPPPPP1P/RQKRBB1N w DA - 0 9", .depth = 6, .nodes = 268_393_274 },
    .{ .fen = "rqkrb2b/p2ppppp/2p3nn/1p6/5P2/PP1P4/2P1P1PP/RQKRBNNB w DAda - 1 9", .depth = 6, .nodes = 485_406_712 },
    .{ .fen = "rbqkr1bn/pp1ppp2/2p1n2p/6p1/8/4BPNP/PPPPP1P1/RBQKRN2 w EAea - 0 9", .depth = 6, .nodes = 314_327_867 },
    .{ .fen = "rqkbrnb1/2ppp1pp/pp3pn1/8/5P2/B2P4/PPP1P1PP/RQKBRN1N w EAea - 2 9", .depth = 6, .nodes = 269_460_607 },
    .{ .fen = "rqkrnbb1/p1p1pppp/1p4n1/3p4/7P/P3P3/1PPPBPP1/RQKRN1BN w DAda - 0 9", .depth = 6, .nodes = 266_047_417 },
    .{ .fen = "rqkrn1bb/p1ppp1pp/4n3/1p6/6p1/4N3/PPPPPPPP/RQKR2BB w DAda - 0 9", .depth = 6, .nodes = 193_376_359 },
    .{ .fen = "bbrkqr2/pppp1ppp/6nn/8/2P1p3/3PP2N/PP3PPP/BBRKQR1N w FCfc - 0 9", .depth = 6, .nodes = 593_204_629 },
    .{ .fen = "brk1qrnn/1pppbppp/4p3/8/1p6/P1P4P/3PPPP1/BRKBQRNN w FBfb - 1 9", .depth = 6, .nodes = 355_969_349 },
    .{ .fen = "1r1qrbnn/p1pkpppp/1p1p4/8/3P1PP1/P4b2/1PP1P2P/BRKQRBNN w EB - 1 9", .depth = 6, .nodes = 401_903_030 },
    .{ .fen = "1rkqrnnb/p1p1p1pp/1p1p4/3b1p1N/4P3/5N2/PPPP1PPP/BRKQR2B w EBeb - 1 9", .depth = 6, .nodes = 791_718_847 },
    .{ .fen = "rbbkq1rn/pppppppp/7n/8/P7/3P3P/1PPKPPP1/RBB1QRNN w a - 3 9", .depth = 6, .nodes = 134_818_483 },
    .{ .fen = "rkbbqr1n/1p1pppp1/2p2n2/p4NBp/8/3P4/PPP1PPPP/RK1BQRN1 w FAfa - 0 9", .depth = 6, .nodes = 673_756_141 },
    .{ .fen = "rkbqrb1n/3pBppp/ppp2n2/8/8/P2P4/1PP1PPPP/RK1QRBNN w EAea - 0 9", .depth = 6, .nodes = 482_288_814 },
    .{ .fen = "rkb1rn1b/ppppqppp/4p3/8/1P2n1P1/5Q2/P1PP1P1P/RKB1RNNB w EAea - 2 9", .depth = 6, .nodes = 1_389_312_729 },
    .{ .fen = "r1kqbrnn/pp1pp1p1/7p/2P2p2/5b2/3P4/P1P1P1PP/RBKQBRNN w FAfa - 0 9", .depth = 6, .nodes = 157_499_039 },
    .{ .fen = "rkqbbr1n/ppp1ppp1/8/Q2p3p/4n3/3P1P2/PPP1P1PP/RK1BBRNN w FAfa - 2 9", .depth = 6, .nodes = 1_366_087_771 },
    .{ .fen = "rkqrbbn1/p1ppppp1/Bp5p/8/P6n/2P1P3/1P1P1PPP/RKQRB1NN w DAda - 0 9", .depth = 6, .nodes = 251_179_183 },
    .{ .fen = "rkqrb1nb/1ppp1ppp/p7/4p3/5n2/3P2N1/PPPQPPPP/RK1RB1NB w DAda - 0 9", .depth = 6, .nodes = 418_191_735 },
    .{ .fen = "rbkqrnbn/pppp1p2/4p1p1/7p/7P/P2P4/BPP1PPP1/R1KQRNBN w EAea - 0 9", .depth = 6, .nodes = 218_658_292 },
    .{ .fen = "rkqbrnbn/pp1ppp2/8/2p3p1/P1P4p/5P2/1PKPP1PP/R1QBRNBN w ea - 0 9", .depth = 6, .nodes = 328_434_174 },
    .{ .fen = "rkqrnbbn/1p2pp1p/3p2p1/p1p5/P5PP/3N4/1PPPPP2/RKQR1BBN w DAda - 0 9", .depth = 6, .nodes = 367_311_176 },
    .{ .fen = "rk2rnbb/ppqppppp/2pn4/8/1P3P2/6P1/P1PPP1NP/RKQR1NBB w DAa - 1 9", .depth = 6, .nodes = 505_212_747 },
    .{ .fen = "b1krrqnn/pp1ppp1p/2p3p1/8/P3Pb1P/1P6/2PP1PP1/BBRKRQNN w EC - 0 9", .depth = 6, .nodes = 800_922_511 },
    .{ .fen = "1rkbrqnn/p1pp1ppp/1p6/8/P2Pp3/8/1PPKPPQP/BR1BR1NN w eb - 0 9", .depth = 6, .nodes = 759_318_058 },
    .{ .fen = "brkrqb1n/1pppp1pp/p7/3n1p2/P5P1/3PP3/1PP2P1P/BRKRQBNN w DBdb - 0 9", .depth = 6, .nodes = 380_267_099 },
    .{ .fen = "brkrqnnb/3pppp1/1p6/p1p4p/2P3P1/6N1/PP1PPP1P/BRKRQ1NB w DBdb - 0 9", .depth = 6, .nodes = 406_594_531 },
    .{ .fen = "r1bkrq1n/pp2pppp/3b1n2/2pp2B1/6P1/3P1P2/PPP1P2P/RB1KRQNN w EAea - 2 9", .depth = 6, .nodes = 631_209_313 },
    .{ .fen = "rk1brq1n/p1p1pppp/3p1n2/1p3b2/4P3/2NQ4/PPPP1PPP/RKBBR2N w EAea - 4 9", .depth = 6, .nodes = 966_310_885 },
    .{ .fen = "rkbrqbnn/1p2ppp1/B1p5/p2p3p/4P2P/8/PPPP1PP1/RKBRQ1NN w DAda - 0 9", .depth = 6, .nodes = 515_304_215 },
    .{ .fen = "rkbrqn1b/pp1pp1pp/2p2p2/5n2/8/2P2P2/PP1PP1PP/RKBRQ1NB w DAda - 0 9", .depth = 6, .nodes = 167_767_913 },
    .{ .fen = "rbkrbnn1/ppppp1pp/5q2/5p2/5P2/P3P2N/1PPP2PP/RBKRBQ1N w DAda - 3 9", .depth = 6, .nodes = 838_704_143 },
    .{ .fen = "rkr1bqnn/1ppp1p1p/p5p1/4p3/3PP2b/2P2P2/PP4PP/RKRBBQNN w CAca - 0 9", .depth = 6, .nodes = 1_024_529_879 },
    .{ .fen = "rkrqbbnn/pppp3p/8/4ppp1/1PP4P/8/P2PPPP1/RKRQBBNN w CAca - 0 9", .depth = 6, .nodes = 484_884_485 },
    .{ .fen = "rkrqbn1b/pppp2pp/8/4pp2/1P1P2n1/5N2/P1P1PP1P/RKRQBN1B w CAca - 0 9", .depth = 6, .nodes = 537_354_146 },
    .{ .fen = "rbkrqnbn/p1p1ppp1/1p1p4/8/3PP2p/2PB4/PP3PPP/R1KRQNBN w DAda - 0 9", .depth = 6, .nodes = 532_603_566 },
    .{ .fen = "1krbqnbn/1p2pppp/r1pp4/p7/8/1P1P2PP/P1P1PP2/RKRBQNBN w CAc - 0 9", .depth = 6, .nodes = 279_864_836 },
    .{ .fen = "rkrq1b2/pppppppb/3n2np/2N5/4P3/7P/PPPP1PP1/RKRQ1BBN w CAca - 1 9", .depth = 6, .nodes = 382_218_272 },
    .{ .fen = "rkr1nnbb/ppp2p1p/3p1qp1/4p3/P5P1/3PN3/1PP1PP1P/RKRQN1BB w CAca - 1 9", .depth = 6, .nodes = 468_666_425 },
    .{ .fen = "bbrkrnqn/1p1ppppp/8/8/p2pP3/PP6/2P2PPP/BBRKRNQN w ECec - 0 9", .depth = 6, .nodes = 509_307_623 },
    .{ .fen = "brkbrnqn/ppp2p2/4p3/P2p2pp/6P1/5P2/1PPPP2P/BRKBRNQN w EBeb - 0 9", .depth = 6, .nodes = 247_750_144 },
    .{ .fen = "brkr1bqn/1pppppp1/3n3p/1p6/P7/4P1P1/1PPP1P1P/BRKRN1QN w DBdb - 0 9", .depth = 6, .nodes = 81_787_718 },
    .{ .fen = "brkr1qnb/pppp2pp/2B1p3/5p2/2n5/6PP/PPPPPPN1/BRKR1QN1 w DBdb - 1 9", .depth = 6, .nodes = 667_089_231 },
    .{ .fen = "rbbkrnqn/p1p1p1pp/8/1p1p4/1P1Pp3/6N1/P1P2PPP/RBBKRNQ1 w EAea - 0 9", .depth = 6, .nodes = 397_454_100 },
    .{ .fen = "rkbbrn1n/pppppp2/5q1p/6p1/3P3P/4P3/PPP2PP1/RKBBRNQN w EAea - 1 9", .depth = 6, .nodes = 485_037_906 },
    .{ .fen = "rkbr1bq1/ppnppppp/6n1/2p5/2P1N2P/8/PP1PPPP1/RKBRNBQ1 w DAda - 3 9", .depth = 6, .nodes = 234_041_078 },
    .{ .fen = "1kbrnqnb/r1ppppp1/8/pp5p/8/1P1NP3/P1PP1PPP/RKB1RQNB w Ad - 2 9", .depth = 6, .nodes = 357_030_697 },
    .{ .fen = "rbkrb1qn/1pp1ppp1/3pn2p/pP6/8/4N1P1/P1PPPP1P/RBKRB1QN w DAda - 0 9", .depth = 6, .nodes = 236_013_157 },
    .{ .fen = "rkrbbnqn/ppppp3/5p2/6pp/5PBP/4P3/PPPP2P1/RKR1BNQN w CAca - 0 9", .depth = 6, .nodes = 669_256_602 },
    .{ .fen = "rkr1bb1n/ppppp1pp/5p2/4n3/3QP3/5P2/RPPP2PP/1KRNBB1N w Cca - 1 9", .depth = 6, .nodes = 1_501_852_662 },
    .{ .fen = "rkr1bqnb/pp1ppppp/8/2pN4/1P6/5N2/P1PPnPPP/RKR1BQ1B w CAca - 0 9", .depth = 6, .nodes = 463_032_124 },
    .{ .fen = "rbkrnqb1/2ppppp1/p5np/1p6/8/3N4/PPPPPPPP/RBKRQNB1 w DAda - 2 9", .depth = 6, .nodes = 133_936_564 },
    .{ .fen = "rkrbnqb1/p1pppnpp/5p2/1p6/2P5/1P1P1N2/P3PPPP/RKRB1QBN w CAca - 0 9", .depth = 6, .nodes = 222_026_485 },
    .{ .fen = "rkr1qbbn/ppppppp1/4n3/7p/8/P7/KPPPPPPP/R1RNQBBN w ca - 0 9", .depth = 6, .nodes = 163_291_279 },
    .{ .fen = "rkrnqnb1/1ppppp2/p5p1/7p/8/P1bPP3/1PP1QPPP/RKRN1NBB w CAca - 0 9", .depth = 6, .nodes = 331_083_405 },
    .{ .fen = "b2krn1q/p1rppppp/1Q3n2/2p1b3/1P4P1/8/P1PPPP1P/BBRKRNN1 w ECe - 3 9", .depth = 6, .nodes = 1_650_202_838 },
    .{ .fen = "brkbrnn1/pp1pppp1/7q/2p5/6Pp/4P1NP/PPPP1P2/BRKBR1NQ w EBeb - 2 9", .depth = 6, .nodes = 936_568_065 },
    .{ .fen = "brkrnb1q/pp1p1ppp/2p1p3/5n2/1P6/5N1N/P1PPPPPP/BRKR1B1Q w DBdb - 1 9", .depth = 6, .nodes = 755_334_868 },
    .{ .fen = "brkr1nqb/pp1p1pp1/2pn3p/P3p3/4P3/6P1/1PPP1P1P/BRKRNNQB w DBdb - 0 9", .depth = 6, .nodes = 103_537_333 },
    .{ .fen = "r1bkrn1q/ppbppppp/5n2/2p5/3P4/P6N/1PP1PPPP/RBBKRNQ1 w EAea - 3 9", .depth = 6, .nodes = 578_210_135 },
    .{ .fen = "rkbbrnnq/pp2pppp/8/2pp4/P1P5/1P3P2/3PP1PP/RKBBRNNQ w EAea - 1 9", .depth = 6, .nodes = 329_615_708 },
    .{ .fen = "rkbr1b1q/p1pppppp/1p1n4/7n/5QP1/3N4/PPPPPP1P/RKBR1BN1 w DAda - 4 9", .depth = 6, .nodes = 842_265_141 },
    .{ .fen = "rkbr1nqb/pppp2np/8/4ppp1/1P6/6N1/P1PPPPPP/RKBRN1QB w DAda - 1 9", .depth = 6, .nodes = 261_247_606 },
    .{ .fen = "rbkr1nnq/p1p1pp1p/1p4p1/3p4/b3P3/4N3/PPPPNPPP/RBKRB1Q1 w DAda - 0 9", .depth = 6, .nodes = 745_802_405 },
    .{ .fen = "rkrbb1nq/p2pppp1/1p4n1/2p4p/3N4/4P1P1/PPPP1P1P/RKRBBN1Q w CAca - 0 9", .depth = 6, .nodes = 441_578_567 },
    .{ .fen = "rkrnbb1q/pp2pp1p/6pn/2pp4/2B1P2P/8/PPPP1PP1/RKRNB1NQ w CAca - 0 9", .depth = 6, .nodes = 712_787_248 },
    .{ .fen = "rk2bnqb/pprpppp1/4n2p/2p5/P7/3P2NP/1PP1PPP1/RKRNB1QB w CAa - 1 9", .depth = 6, .nodes = 323_043_654 },
    .{ .fen = "r1krnnbq/pp1ppp1p/6p1/2p5/2P5/P3P3/Rb1P1PPP/1BKRNNBQ w Dda - 0 9", .depth = 6, .nodes = 28_753_562 },
    .{ .fen = "1krbnnbq/1pp1p1pp/r7/p2p1p2/3PP3/2P3P1/PP3P1P/RKRBNNBQ w CAc - 0 9", .depth = 6, .nodes = 787_205_262 },
    .{ .fen = "rkr1nbbq/2ppp1pp/1pn5/p4p2/P6P/3P4/1PP1PPPB/RKRNNB1Q w CAca - 1 9", .depth = 6, .nodes = 341_262_639 },
    .{ .fen = "rkrnnqbb/p1ppp2p/Qp6/4Pp2/5p2/8/PPPP2PP/RKRNN1BB w CAca - 0 9", .depth = 6, .nodes = 915_268_405 },
    .{ .fen = "bbq1nr1r/pppppk1p/2n2p2/6p1/P4P2/4P1P1/1PPP3P/BBQNNRKR w HF - 1 9", .depth = 6, .nodes = 280_056_112 },
};

pub fn run(allocator: std.mem.Allocator, mg: *const mvs.MoveGen, gs: *brd.GameState, w: *std.Io.Writer) !usize {
    var table = try perft.TranspositionTable.init(allocator, perft.default_tt_size_mb);
    defer table.deinit(allocator);

    var failed: usize = 0;

    for (detailed) |c| {
        try fen.parseFEN(gs, c.fen);
        table.clear();
        const got = perft.perftTT(mg, gs, c.depth, &table);
        if (got.eql(c.expected)) {
            try w.print("ok   d{d} {d} {s}\n", .{ c.depth, got.total, c.fen });
        } else {
            try w.print("FAIL d{d} {s}\n  expected {any}\n  got      {any}\n", .{ c.depth, c.fen, c.expected, got });
            failed += 1;
        }
        try w.flush();
    }

    for (cases) |c| {
        try fen.parseFEN(gs, c.fen);
        table.clear();
        const got = perft.perftTT(mg, gs, c.depth, &table).total;
        if (got == c.nodes) {
            try w.print("ok   d{d} {d} {s}\n", .{ c.depth, got, c.fen });
        } else {
            try w.print("FAIL d{d} {s}\n  expected {d}, got {d}\n", .{ c.depth, c.fen, c.nodes, got });
            failed += 1;
        }
        try w.flush();
    }

    return failed;
}
