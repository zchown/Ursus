const brd = @import("board");
const std = @import("std");
const mvs = @import("moves");
const pawn_tt = @import("pawn_tt");

pub const mate_score: i32 = 888888;

const total_phase: i32 = 24;
const pawn_phase: i32 = 0;
const knight_phase: i32 = 1;
const bishop_phase: i32 = 1;
const rook_phase: i32 = 2;
const queen_phase: i32 = 4;

const mg_pawn: i32 = 82;
const eg_pawn: i32 = 94;
const mg_knight: i32 = 337;
const eg_knight: i32 = 281;
const mg_bishop: i32 = 365;
const eg_bishop: i32 = 297;
const mg_rook: i32 = 477;
const eg_rook: i32 = 512;
const mg_queen: i32 = 1025;
const eg_queen: i32 = 936;
const mg_king: i32 = 0;
const eg_king: i32 = 0;

// King Safety Bonuses
const castled_bonus: i32 = 50;
const pawn_shield_bonus: i32 = 15;
const open_file_penalty: i32 = -30;
const semi_open_penalty: i32 = -15;
const knight_attack_bonus: i32 = 2;
const bishop_attack_bonus: i32 = 2;
const rook_attack_bonus: i32 = 3;
const queen_attack_bonus: i32 = 5;
const safety_table = [16]i32{ 0, 0, 5, 10, 20, 40, 70, 110, 160, 220, 300, 400, 500, 600, 700, 800 };

// Endgame Bonuses
const rook_on_7th_bonus: i32 = 20;
const rook_behind_passer_bonus: i32 = 60;
const king_pawn_proximity: i32 = 4;

// Pawn Structure Bonuses
const passed_pawn_bonus = [8]i32{ 0, 15, 25, 40, 65, 115, 175, 0 };
const mg_passed_bonus = [8]i32{ 0, 5, 10, 15, 25, 40, 60, 0 };
const protected_pawn_bonus: i32 = 8;
const doubled_pawn_penalty: i32 = -25;
const isolated_pawn_penalty: i32 = -12;
const connected_pawn_bonus: i32 = 10;
const backward_pawn_penalty: i32 = -15;

// Rook Bonuses
const rook_on_open_file_bonus: i32 = 45;
const rook_on_semi_open_file_bonus: i32 = 20;
const trapped_rook_penalty: i32 = 50;

// Tactical Bonuses
const minor_threat_penalty: i32 = 30;
const rook_threat_penalty: i32 = 50;
const queen_threat_penalty: i32 = 80;
const rook_on_queen_bonus: i32 = 20;
const rook_on_king_bonus: i32 = 15;
const queen_on_king_bonus: i32 = 10;
const bad_bishop_penalty: i32 = 35;
const bishop_on_queen_bonus: i32 = 25;
const bishop_on_king_bonus: i32 = 15;
const hanging_piece_penalty: i32 = 40;
const attacked_by_pawn_penalty: i32 = 35;
const attacked_by_minor_penalty: i32 = 25;
const attacked_by_rook_penalty: i32 = 20;

// Miscellaneous Bonuses
const tempo_bonus: i32 = 10;
const bishop_pair_bonus: i32 = 30;
const knight_outpost_bonus: i32 = 30;
const space_per_square: i32 = 2;
const center_control_bonus: i32 = 10;
const extended_center_bonus: i32 = 5;

const EvalStruct = struct {
    mg: i32,
    eg: i32,
};

// Pawn Table (incentivize pushing)
const mg_pawn_table = [64]i32{
    0,   0,   0,   0,   0,   0,   0,  0,
    98,  134, 61,  95,  68,  126, 34, -11,
    -6,  7,   26,  31,  65,  56,  25, -20,
    -14, 13,  6,   21,  23,  12,  17, -23,
    -27, -2,  -5,  12,  17,  6,   10, -25,
    -26, -4,  -4,  -10, 3,   3,   33, -12,
    -35, -1,  -20, -23, -15, 24,  38, -22,
    0,   0,   0,   0,   0,   0,   0,  0,
};
const eg_pawn_table = [64]i32{
    0,   0,   0,   0,   0,   0,   0,   0,
    178, 173, 158, 134, 147, 132, 165, 187,
    94,  100, 85,  67,  56,  53,  82,  84,
    32,  24,  13,  5,   -2,  4,   17,  17,
    13,  9,   -3,  -7,  -7,  -8,  3,   -1,
    4,   7,   -6,  1,   0,   -5,  -1,  -8,
    13,  8,   8,   10,  13,  0,   2,   -7,
    0,   0,   0,   0,   0,   0,   0,   0,
};
// Knight Table (incentivize center)
const mg_knight_table = [64]i32{
    -167, -89, -34, -49, 61,  -97, -15, -107,
    -73,  -41, 72,  36,  23,  62,  7,   -17,
    -47,  60,  37,  65,  84,  129, 73,  44,
    -9,   17,  19,  53,  37,  69,  18,  22,
    -13,  4,   16,  13,  28,  19,  21,  -8,
    -23,  -9,  12,  10,  19,  17,  25,  -16,
    -29,  -53, -12, -3,  -1,  18,  -14, -19,
    -105, -21, -58, -33, -17, -28, -19, -23,
};
const eg_knight_table = [64]i32{
    -58, -38, -13, -28, -31, -27, -63, -99,
    -25, -8,  -25, -2,  -9,  -25, -24, -52,
    -24, -20, 10,  9,   -1,  -9,  -19, -41,
    -17, 3,   22,  22,  22,  11,  8,   -18,
    -18, -6,  16,  25,  16,  17,  4,   -18,
    -23, -3,  -1,  15,  10,  -3,  -20, -22,
    -42, -20, -10, -5,  -2,  -20, -23, -44,
    -29, -51, -23, -15, -22, -18, -50, -64,
};

// Bishop Table (avoid corners, control diagonals)
const mg_bishop_table = [64]i32{
    -29, 4,  -82, -37, -25, -42, 7,   -8,
    -26, 16, -18, -13, 30,  59,  18,  -47,
    -16, 37, 43,  40,  35,  50,  37,  -2,
    -4,  5,  19,  50,  37,  37,  7,   -2,
    -6,  13, 13,  26,  34,  12,  10,  4,
    0,   15, 15,  15,  14,  27,  18,  10,
    4,   15, 16,  0,   7,   21,  33,  1,
    -33, -3, -14, -21, -13, -12, -39, -21,
};
const eg_bishop_table = [64]i32{
    -14, -21, -11, -8,  -7, -9,  -17, -24,
    -8,  -4,  7,   -12, -3, -13, -4,  -14,
    2,   -8,  0,   -1,  -2, 6,   0,   4,
    -3,  9,   12,  9,   14, 10,  3,   2,
    -6,  3,   13,  19,  7,  10,  -3,  -9,
    -12, -3,  8,   10,  13, 3,   -7,  -15,
    -14, -18, -7,  -1,  4,  -9,  -15, -27,
    -23, -9,  -23, -5,  -9, -16, -5,  -17,
};

// Rook Table
const mg_rook_table = [64]i32{
    32,  42,  32,  51,  63, 9,  31,  43,
    27,  32,  58,  62,  80, 67, 26,  44,
    -5,  19,  26,  36,  17, 45, 61,  16,
    -24, -11, 7,   26,  24, 35, -8,  -20,
    -36, -26, -12, -1,  9,  -7, 6,   -23,
    -45, -25, -16, -17, 3,  0,  -5,  -33,
    -44, -16, -20, -9,  -1, 11, -6,  -71,
    -19, -13, 1,   17,  16, 7,  -37, -26,
};
const eg_rook_table = [64]i32{
    13, 10, 18, 15, 12, 12,  8,   5,
    11, 13, 13, 11, -3, 3,   8,   3,
    7,  7,  7,  5,  4,  -3,  -5,  -3,
    4,  3,  13, 1,  2,  1,   -1,  2,
    3,  5,  8,  4,  -5, -6,  -8,  -11,
    -4, 0,  -5, -1, -7, -12, -8,  -16,
    -6, -6, 0,  2,  -9, -9,  -11, -3,
    -9, 2,  3,  -1, -5, -13, 4,   -20,
};

// Queen Table
const mg_queen_table = [64]i32{
    -28, 0,   29,  12,  59,  44,  43,  45,
    -24, -39, -5,  1,   -16, 57,  28,  54,
    -13, -17, 7,   8,   29,  56,  47,  57,
    -27, -27, -16, -16, -1,  17,  -2,  1,
    -9,  -26, -9,  -10, -2,  -4,  3,   -3,
    -14, 2,   -11, -2,  -5,  2,   14,  5,
    -35, -8,  11,  2,   8,   15,  -3,  1,
    -1,  -18, -9,  10,  -15, -25, -31, -50,
};
const eg_queen_table = [64]i32{
    -9,  22,  22,  27,  27,  19,  10,  20,
    -17, 20,  32,  41,  58,  25,  30,  0,
    -20, 6,   9,   49,  47,  35,  19,  9,
    3,   22,  24,  45,  57,  40,  57,  36,
    -18, 28,  19,  47,  31,  34,  39,  23,
    -16, -27, 15,  6,   9,   17,  10,  5,
    -22, -23, -30, -16, -16, -23, -36, -32,
    -33, -28, -22, -43, -5,  -32, -20, -41,
};

// King Table (Hide in safety in MG, Active in EG)
const mg_king_table = [64]i32{
    -65, 23,  16,  -15, -56, -34, 2,   13,
    29,  -1,  -20, -7,  -8,  -4,  -38, -29,
    -9,  24,  2,   -16, -20, 6,   22,  -22,
    -17, -20, -12, -27, -30, -25, -14, -36,
    -49, -1,  -27, -39, -46, -44, -33, -51,
    -14, -14, -22, -46, -44, -30, -15, -27,
    1,   7,   -8,  -64, -43, -16, 9,   8,
    -15, 36,  12,  -54, 8,   -28, 24,  14,
};
const eg_king_table = [64]i32{ -74, -35, -18, -18, -11, 15, 4, -17, -12, 17, 14, 17, 17, 38, 23, 11, 10, 17, 23, 15, 20, 45, 44, 13, -8, 22, 24, 27, 26, 33, 26, 3, -18, -4, 21, 24, 27, 23, 9, -11, -19, -3, 11, 21, 23, 16, 7, -9, -27, -11, 4, 13, 14, 4, -5, -17, -53, -34, -21, -11, -28, -14, -24, -43 };

// Mirror array for black to flip the square index
const mirror_sq = initMirror();
fn initMirror() [64]usize {
    var table: [64]usize = undefined;
    for (0..64) |i| {
        table[i] = i ^ 56; // Flip Rank (a1 <-> a8)
    }
    return table;
}

// Manhattan distance between two squares
fn manhattanDistance(sq1: usize, sq2: usize) i32 {
    const file1: i32 = @intCast(@mod(sq1, 8));
    const rank1: i32 = @intCast(@divTrunc(sq1, 8));
    const file2: i32 = @intCast(@mod(sq2, 8));
    const rank2: i32 = @intCast(@divTrunc(sq2, 8));
    return @as(i32, @intCast(@abs(file1 - file2) + @abs(rank1 - rank2)));
}

// Distance from center (used for driving losing king to edge)
fn centerDistance(sq: usize) i32 {
    const file: i32 = @intCast(@mod(sq, 8));
    const rank: i32 = @intCast(@divTrunc(sq, 8));
    const file_dist = @min(@abs(file - 3), @abs(file - 4));
    const rank_dist = @min(@abs(rank - 3), @abs(rank - 4));
    return @as(i32, @intCast(file_dist + rank_dist));
}

pub fn pieceValueByEnum(piece: brd.Pieces) i32 {
    return switch (piece) {
        .Pawn => mg_pawn,
        .Knight => mg_knight,
        .Bishop => mg_bishop,
        .Rook => mg_rook,
        .Queen => mg_queen,
        .King => 0,
        .None => 0,
    };
}

fn getPawnAttacks(pawn_bb: u64, color: brd.Color) u64 {
    if (color == brd.Color.White) {
        const not_file_a: u64 = 0xFEFEFEFEFEFEFEFE;
        const not_file_h: u64 = 0x7F7F7F7F7F7F7F7F;
        return ((pawn_bb << 9) & not_file_h) | ((pawn_bb << 7) & not_file_a);
    } else {
        const not_file_a: u64 = 0xFEFEFEFEFEFEFEFE;
        const not_file_h: u64 = 0x7F7F7F7F7F7F7F7F;
        return ((pawn_bb >> 9) & not_file_a) | ((pawn_bb >> 7) & not_file_h);
    }
}

pub fn evaluate(board: *brd.Board, move_gen: *mvs.MoveGen) i32 {
    var current_phase: i32 = 0;

    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][1]) + @popCount(board.piece_bb[1][1]))) * knight_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][2]) + @popCount(board.piece_bb[1][2]))) * bishop_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][3]) + @popCount(board.piece_bb[1][3]))) * rook_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][4]) + @popCount(board.piece_bb[1][4]))) * queen_phase;

    current_phase = std.math.clamp(current_phase, 0, total_phase);

    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

    const white_eval = evalColorCombined(board, brd.Color.White, move_gen);
    const black_eval = evalColorCombined(board, brd.Color.Black, move_gen);
    mg_score += white_eval.mg - black_eval.mg;
    eg_score += white_eval.eg - black_eval.eg;

    // King Safety (middlegame focused)
    mg_score += evalKingSafety(board, brd.Color.White);
    mg_score -= evalKingSafety(board, brd.Color.Black);

    pawn_tt.pawn_tt.prefetch(board.game_state.pawn_hash);
    // Pawn Structure evaluation
    const pawn_eval = evalPawnStructure(board, current_phase);
    mg_score += pawn_eval.mg;
    eg_score += pawn_eval.eg;

    // Endgame-specific evaluation (more important as phase approaches 0)
    if (current_phase < total_phase / 2) {
        const eg_eval = evalEndgame(board, current_phase);
        eg_score += eg_eval;
    }

    const white_bishops = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)]);
    const black_bishops = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)]);

    if (white_bishops >= 2) {
        mg_score += bishop_pair_bonus;
        eg_score += bishop_pair_bonus;
    }
    if (black_bishops >= 2) {
        mg_score -= bishop_pair_bonus;
        eg_score -= bishop_pair_bonus;
    }

        
    var score: i32 = 0;
    score += evalThreats(board, move_gen, brd.Color.White);
    score -= evalThreats(board, move_gen, brd.Color.Black);

    score += evalSpace(board, move_gen, brd.Color.White);
    score -= evalSpace(board, move_gen, brd.Color.Black);

    mg_score += score;
    eg_score += score;

    var final_score = (mg_score * current_phase + eg_score * (total_phase - current_phase));
    final_score = @divTrunc(final_score, total_phase);
    final_score += tempo_bonus;

    // help with oposite colored bishop endgames - if both sides have only a bishop and they are on opposite colors, it's often a draw, so reduce score to reflect that
    // loses elo :(
//     const white_knights = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Knight)]);
//     const black_knights = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Knight)]);
//     const white_rooks = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Rook)]);
//     const black_rooks = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Rook)]);
//     const white_queens = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)]);
//     const black_queens = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);
//
//
//     if (white_bishops == 1 and black_bishops == 1 and
//     white_knights == 0 and black_knights == 0 and
//     white_rooks == 0 and black_rooks == 0 and
//     white_queens == 0 and black_queens == 0) 
// {
//         const white_bishop_sq = brd.getLSB(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)]);
//         const black_bishop_sq = brd.getLSB(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)]);
//
//         const white_is_light = (white_bishop_sq / 8 + white_bishop_sq % 8) % 2 != 0; 
//         const black_is_light = (black_bishop_sq / 8 + black_bishop_sq % 8) % 2 != 0;
//
//         if (white_is_light != black_is_light) {
//             if (current_phase == 0) {
//                 final_score = @divTrunc(final_score, 2); 
//             } else {
//                 final_score = @divTrunc(final_score * 3, 4);
//             }
//         }
//     }

    if (board.toMove() == brd.Color.White) {
        return final_score;
    } else {
        return -final_score;
    }
}

fn evalColorCombined(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen) EvalStruct {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    var score: i32 = 0;
    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

    var attack_units: i32 = 0;
    var attacker_count: i32 = 0;

    const getPst = struct {
        fn get(sq: usize, table: [64]i32, c: brd.Color) i32 {
            if (c == brd.Color.White) return table[sq];
            return table[mirror_sq[sq]];
        }
    }.get;

    // Pre-calculate useful bitboards for positional logic
    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];
    const our_pawn_attacks = getPawnAttacks(our_pawns, color);
    const opp_pawn_attacks = getPawnAttacks(opp_pawns, if (color == brd.Color.White) brd.Color.Black else brd.Color.White);
    const opp_king_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.King)];
    const opp_queen_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Queen)];
    const occupancy = board.occupancy();
    const opp_king_sq = brd.getLSB(opp_king_bb);
    const opp_king_zone = getKingZone(opp_king_sq, color.opposite(), move_gen);

    // Pawns
    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_pawn;
        eg_score += eg_pawn;
        mg_score += getPst(sq, mg_pawn_table, color);
        eg_score += getPst(sq, eg_pawn_table, color);
        brd.popBit(&bb, sq);
    }

    // Knights
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_knight;
        eg_score += eg_knight;
        mg_score += getPst(sq, mg_knight_table, color);
        eg_score += getPst(sq, eg_knight_table, color);

        const rank = @divTrunc(sq, 8);
        const relative_rank = if (color == brd.Color.White) rank else 7 - rank;
        const is_supported = (our_pawn_attacks & (@as(u64, 1) << @intCast(sq))) != 0;

        if (is_supported and relative_rank >= 3 and relative_rank <= 5) {
            mg_score += knight_outpost_bonus;
        }

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            score -= minor_threat_penalty;
        }

        score += evalMobility(@as(usize, @intCast(sq)), .Knight, board, move_gen, opp_pawn_attacks, color);

        const attack_mask = move_gen.knights[@as(usize, @intCast(sq))];
        if (attack_mask & opp_king_zone != 0) {
            attack_units += knight_attack_bonus;
            attacker_count += 1;
        }

        brd.popBit(&bb, sq);
    }

    // Bishops
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_bishop;
        eg_score += eg_bishop;
        mg_score += getPst(sq, mg_bishop_table, color);
        eg_score += getPst(sq, eg_bishop_table, color);

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            score -= minor_threat_penalty;
        }

        const bishop_mask: u64 = move_gen.getBishopAttacks(sq, occupancy);
        const blocking_pawns: i32 = @as(i32, @intCast(@popCount(our_pawns & bishop_mask)));
        if (blocking_pawns > 1) {
            score -= (blocking_pawns - 1) * bad_bishop_penalty;
        }

        score += evalMobility(@as(usize, @intCast(sq)), .Bishop, board, move_gen, opp_pawn_attacks, color);

        const attack_mask = move_gen.getBishopAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            attack_units += bishop_attack_bonus;
            attacker_count += 1;
        }

        brd.popBit(&bb, sq);
    }

    // Rooks
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_rook;
        eg_score += eg_rook;
        mg_score += getPst(sq, mg_rook_table, color);
        eg_score += getPst(sq, eg_rook_table, color);

        const file = @mod(sq, 8);
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);

        const our_pawns_on_file = (our_pawns & file_mask) != 0;
        const opp_pawns_on_file = (opp_pawns & file_mask) != 0;

        if (!our_pawns_on_file) {
            if (!opp_pawns_on_file) {
                score += rook_on_open_file_bonus;
            } else {
                score += rook_on_semi_open_file_bonus;
            }
        }

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            score -= rook_threat_penalty;
        }

        if (file_mask & opp_queen_bb != 0) {
            score += rook_on_queen_bonus;
        }

        if (file_mask & opp_king_bb != 0) {
            score += rook_on_king_bonus;
        }

        score += evalMobility(@as(usize, @intCast(sq)), .Rook, board, move_gen, opp_pawn_attacks, color);

        const attack_mask = move_gen.getRookAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            attack_units += rook_attack_bonus;
            attacker_count += 1;
        }

        // Loses elo
        // const is_corner = (sq == 0 or sq == 7 or sq == 56 or sq == 63);
        // if (is_corner) {
        //     const king_sq = brd.getLSB(board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)]);
        //     const dist = manhattanDistance(sq, king_sq);
        //
        //     // If king is adjacent to the cornered rook (e.g., g1 and h1)
        //     if (dist <= 2) {
        //         // Check if rook is trapped by lack of mobility
        //         const attacks = move_gen.getRookAttacks(sq, occupancy);
        //         if (@popCount(attacks) <= 3) {
        //             score -= trapped_rook_penalty;
        //         }
        //     }
        // }

        brd.popBit(&bb, sq);
    }

    // Queens
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Queen)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_queen;
        eg_score += eg_queen;
        mg_score += getPst(sq, mg_queen_table, color);
        eg_score += getPst(sq, eg_queen_table, color);
        brd.popBit(&bb, sq);

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            score -= queen_threat_penalty;
        }

        const file = @mod(sq, 8);
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        if (file_mask & opp_king_bb != 0) {
            score += queen_on_king_bonus;
        }

        score += evalMobility(@as(usize, @intCast(sq)), .Queen, board, move_gen, opp_pawn_attacks, color);

        const attack_mask = move_gen.getQueenAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            attack_units += queen_attack_bonus;
            attacker_count += 1;
        }
    }

    // King
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_king;
        eg_score += eg_king;
        mg_score += getPst(sq, mg_king_table, color);
        eg_score += getPst(sq, eg_king_table, color);
    }

    if (attacker_count > 1) {
        const index = @as(usize, @intCast(@min(attack_units, 15)));
        score += safety_table[index];
    }

    return EvalStruct{
        .mg = mg_score + score,
        .eg = eg_score + score,
    };
}

// King Safety evaluation - incentivizes castling and pawn shields
fn evalKingSafety(board: *brd.Board, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    var safety: i32 = 0;

    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return 0;

    const king_sq = brd.getLSB(king_bb);
    const king_file = @mod(king_sq, 8);
    const king_rank = @divTrunc(king_sq, 8);

    // Check if castled (king on g1/g8 or c1/c8 with appropriate rank)
    const has_castled = blk: {
        if (color == brd.Color.White) {
            // White castled kingside: king on g1 (sq 6)
            // White castled queenside: king on c1 (sq 2)
            break :blk king_sq == 6 or king_sq == 2;
        } else {
            // Black castled kingside: king on g8 (sq 62)
            // Black castled queenside: king on c8 (sq 58)
            break :blk king_sq == 62 or king_sq == 58;
        }
    };

    if (has_castled) {
        safety += castled_bonus;
    }

    // Evaluate pawn shield
    const pawn_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const shield_files = [3]i32{ @as(i32, @intCast(king_file)) - 1, @as(i32, @intCast(king_file)), @as(i32, @intCast(king_file)) + 1 };

    for (shield_files) |file| {
        if (file < 0 or file > 7) continue;

        // Check for pawns in front of king
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        const pawns_on_file = pawn_bb & file_mask;

        if (pawns_on_file != 0) {
            var temp_bb = pawns_on_file;
            while (temp_bb != 0) {
                const pawn_sq = brd.getLSB(temp_bb);
                const pawn_rank = @divTrunc(pawn_sq, 8);

                // Check if pawn is in front of king 
                const is_shield = if (color == brd.Color.White)
                    pawn_rank > king_rank and pawn_rank <= king_rank + 2
                else
                    pawn_rank < king_rank and pawn_rank >= king_rank - 2;

                if (is_shield) {
                    safety += pawn_shield_bonus;
                }

                brd.popBit(&temp_bb, pawn_sq);
            }
        }
    }

    // Penalty for open/semi-open files near king
    const all_pawns = board.piece_bb[0][@intFromEnum(brd.Pieces.Pawn)] |
        board.piece_bb[1][@intFromEnum(brd.Pieces.Pawn)];

    for (shield_files) |file| {
        if (file < 0 or file > 7) continue;

        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        const our_pawns_on_file = pawn_bb & file_mask;
        const their_pawns_on_file = (all_pawns & file_mask) ^ our_pawns_on_file;

        if (our_pawns_on_file == 0 and their_pawns_on_file == 0) {
            safety += open_file_penalty; // Open file
        } else if (our_pawns_on_file == 0 and their_pawns_on_file != 0) {
            safety += semi_open_penalty; // Semi-open file (dangerous)
        }
    }

    return safety;
}

const PawnEval = struct {
    mg: i32,
    eg: i32,
};

// Pawn Structure evaluation - passed pawns, pawn chains, isolated/doubled
fn evalPawnStructure(board: *brd.Board, phase: i32) PawnEval {
    var result = PawnEval{ .mg = 0, .eg = 0 };

    const white_eval = evalPawnsForColor(board, brd.Color.White, phase);
    const black_eval = evalPawnsForColor(board, brd.Color.Black, phase);

    result.mg = white_eval.mg - black_eval.mg;
    result.eg = white_eval.eg - black_eval.eg;

    return result;
}

fn evalPawnsForColor(board: *brd.Board, color: brd.Color, phase: i32) PawnEval {

    if (pawn_tt.pawn_tt.get(board.game_state.pawn_hash)) |e| {
        return PawnEval{
            .mg = e.mg,
            .eg = e.eg,
        };
    }

    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    var result = PawnEval{ .mg = 0, .eg = 0 };

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];

    var file_counts = [_]u8{0} ** 8;
    var temp_bb = our_pawns;
    while (temp_bb != 0) {
        const sq = brd.getLSB(temp_bb);
        const file = @mod(sq, 8);
        file_counts[file] += 1;
        brd.popBit(&temp_bb, sq);
    }

    temp_bb = our_pawns;
    while (temp_bb != 0) {
        const sq = brd.getLSB(temp_bb);
        const file = @mod(sq, 8);
        const rank = @divTrunc(sq, 8);

        const relative_rank: usize = if (color == brd.Color.White) rank else 7 - rank;

        const left_mask: u64 = if (file > 0) @as(u64, 0x0101010101010101) << @intCast(file - 1) else 0;
        const right_mask: u64 = if (file < 7) @as(u64, 0x0101010101010101) << @intCast(file + 1) else 0;
        const adjacent_files = left_mask | right_mask;

        // Connected and backward pawns evaluation 
        // currently reduce elo
        // const rank_mask_connected = @as(u64, 0xFF) << @intCast(rank * 8);
        // const phalanx_mask = (left_mask | right_mask) & rank_mask_connected;
        // const support_mask = if (color == brd.Color.White)
        // ((left_mask | right_mask) >> 8)
        //     else
        // ((left_mask | right_mask) << 8);
        //
        // const is_connected = (our_pawns & (phalanx_mask | support_mask)) != 0;
        //
        // if (is_connected) {
        //     // Reward connected pawns, slightly increasing with rank
        //     const bonus = connected_pawn_bonus + @as(i32, @intCast(relative_rank)) * 2;
        //     result.mg += bonus;
        //     result.eg += bonus * 2; // Connected pawns are monsters in endgames
        // }
        // const is_backward = blk: {
        //     const support_mask_back: u64 = if (color == brd.Color.White)
        //         ~(@as(u64, 0xFFFFFFFFFFFFFFFF) << @intCast((rank + 1) * 8))
        //         else
        //         ~(@as(u64, 0xFFFFFFFFFFFFFFFF) >> @intCast((8 - rank) * 8));
        //
        //     const has_support = (our_pawns & adjacent_files & support_mask_back) != 0;
        //     if (has_support) break :blk false;
        //
        //     const stop_sq = if (color == brd.Color.White) sq + 8 else sq - 8;
        //     if (stop_sq < 0 or stop_sq > 63) break :blk false;
        //
        //     const stop_file = @mod(stop_sq, 8);
        //     const stop_rank = @divTrunc(stop_sq, 8);
        //
        //     var enemy_control = false;
        //
        //     if (color == brd.Color.White) {
        //         if (stop_rank < 7) {
        //             if (stop_sq + 7 < 64 and (opp_pawns & (@as(u64, 1) << @intCast(stop_sq + 7))) != 0 and stop_file > 0) enemy_control = true;
        //             if (stop_sq + 9 < 64 and (opp_pawns & (@as(u64, 1) << @intCast(stop_sq + 9))) != 0 and stop_file < 7) enemy_control = true;
        //         }
        //     } else {
        //         if (stop_sq >= 7 and (opp_pawns & (@as(u64, 1) << @intCast(stop_sq - 7))) != 0 and stop_file < 7) enemy_control = true;
        //         if (stop_sq >= 9 and (opp_pawns & (@as(u64, 1) << @intCast(stop_sq - 9))) != 0 and stop_file > 0) enemy_control = true;
        //     }
        //
        //     break :blk enemy_control;
        // };
        //
        // if (is_backward) {
        //     result.mg += backward_pawn_penalty;
        //     result.eg += backward_pawn_penalty;
        // }

        const is_passed = blk: {
            const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
            const forward_mask = file_mask | left_mask | right_mask;

            const blocking_pawns = if (color == brd.Color.White) blk2: {
                const rank_mask: u64 = (@as(u64, 0xFFFFFFFFFFFFFFFF) << @intCast((rank + 1) * 8));
                break :blk2 opp_pawns & forward_mask & rank_mask;
            } else blk2: {
                const rank_mask: u64 = if (rank > 0) (@as(u64, 0xFFFFFFFFFFFFFFFF) >> @intCast((8 - rank) * 8)) else 0;
                break :blk2 opp_pawns & forward_mask & rank_mask;
            };

            break :blk blocking_pawns == 0;
        };

        if (is_passed) {
            const mg_bonus = mg_passed_bonus[relative_rank];
            var eg_bonus = passed_pawn_bonus[relative_rank];
            if (phase < 12) {
                eg_bonus = @divTrunc(eg_bonus * 3, 2); 
            }

            const advancement_bonus = if (relative_rank >= 5)
                @divTrunc((total_phase - phase) * @as(i32, @intCast(relative_rank)) * 3, total_phase)
            else
                0;

            result.mg += mg_bonus;
            result.eg += eg_bonus + advancement_bonus;
        }

        const is_protected = blk: {
            const protection_sqs = if (color == brd.Color.White) blk2: {
                var sqs: [2]?usize = .{ null, null };
                if (sq >= 9 and file > 0) sqs[0] = sq - 9;
                if (sq >= 7 and file < 7) sqs[1] = sq - 7;
                break :blk2 sqs;
            } else blk2: {
                var sqs: [2]?usize = .{ null, null };
                if (sq <= 54 and file > 0) sqs[0] = sq + 7;
                if (sq <= 56 and file < 7) sqs[1] = sq + 9;
                break :blk2 sqs;
            };

            var protected = false;
            for (protection_sqs) |maybe_sq| {
                if (maybe_sq) |prot_sq| {
                    const mask: u64 = @as(u64, 1) << @intCast(prot_sq);
                    if ((our_pawns & mask) != 0) {
                        protected = true;
                        break;
                    }
                }
            }
            break :blk protected;
        };

        if (is_protected) {
            result.mg += protected_pawn_bonus;
            result.eg += protected_pawn_bonus;
        }

        const is_isolated = blk: {
            break :blk (our_pawns & adjacent_files) == 0;
        };

        if (is_isolated) {
            result.mg += isolated_pawn_penalty;
            result.eg += isolated_pawn_penalty;
        }

        if (file_counts[file] > 1) {
            result.mg += doubled_pawn_penalty;
            result.eg += doubled_pawn_penalty;
        }

        brd.popBit(&temp_bb, sq);
    }

    pawn_tt.pawn_tt.set(pawn_tt.Entry{
        .hash = board.game_state.pawn_hash,
        .mg = result.mg,
        .eg = result.eg,
    });

    return result;
}

fn evalEndgame(board: *brd.Board, phase: i32) i32 {
    var score: i32 = 0;

    const white_material = countMaterial(board, brd.Color.White);
    const black_material = countMaterial(board, brd.Color.Black);
    const material_diff = white_material - black_material;

    if (@abs(material_diff) > 200) {
        const winning_side = if (material_diff > 0) brd.Color.White else brd.Color.Black;
        const losing_side = if (material_diff > 0) brd.Color.Black else brd.Color.White;

        const winner_idx = @intFromEnum(winning_side);
        const loser_idx = @intFromEnum(losing_side);

        const winner_king_bb = board.piece_bb[winner_idx][@intFromEnum(brd.Pieces.King)];
        const loser_king_bb = board.piece_bb[loser_idx][@intFromEnum(brd.Pieces.King)];

        if (winner_king_bb != 0 and loser_king_bb != 0) {
            const winner_king_sq = brd.getLSB(winner_king_bb);
            const loser_king_sq = brd.getLSB(loser_king_bb);

            // Drive losing king to the edge
            const edge_score = centerDistance(loser_king_sq) * 10;

            // Bring winning king closer to losing king
            const king_proximity = (14 - manhattanDistance(winner_king_sq, loser_king_sq)) * 4;

            const mopup_score = edge_score + king_proximity;

            if (material_diff > 0) {
                score += mopup_score;
            } else {
                score -= mopup_score;
            }
        }
    }

    // King activity in endgame - centralized king is strong
    score += evalKingActivity(board, brd.Color.White, phase);
    score -= evalKingActivity(board, brd.Color.Black, phase);

    // Rook activity in endgame
    score += evalRookEndgame(board, brd.Color.White);
    score -= evalRookEndgame(board, brd.Color.Black);

    return score;
}

fn countMaterial(board: *brd.Board, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    var material: i32 = 0;

    material += @as(i32, @intCast(@popCount(board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)]))) * mg_pawn;
    material += @as(i32, @intCast(@popCount(board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)]))) * mg_knight;
    material += @as(i32, @intCast(@popCount(board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)]))) * mg_bishop;
    material += @as(i32, @intCast(@popCount(board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)]))) * mg_rook;
    material += @as(i32, @intCast(@popCount(board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Queen)]))) * mg_queen;

    return material;
}

// King activity bonus in endgame (centralized, active king)
fn evalKingActivity(board: *brd.Board, color: brd.Color, phase: i32) i32 {
    _ = phase;
    const c_idx = @intFromEnum(color);
    var score: i32 = 0;

    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return 0;

    const king_sq = brd.getLSB(king_bb);

    // Bonus for centralized king in endgame
    const centralization = 7 - centerDistance(king_sq);
    score += centralization * 2;

    // Bonus for king being close to passed pawns
    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[1 - c_idx][@intFromEnum(brd.Pieces.Pawn)];

    // if (our_pawns != 0) {
    //     var closest_dist: i32 = 100;
    //     var temp_pawns = our_pawns;
    //     while (temp_pawns != 0) {
    //         const p_sq = brd.getLSB(temp_pawns);
    //         const dist = manhattanDistance(king_sq, p_sq);
    //         if (dist < closest_dist) closest_dist = dist;
    //         brd.popBit(&temp_pawns, p_sq);
    //     }
    //     // Reward being close to the "action" (your pawn mass)
    //     score += (10 - closest_dist) * 2; 
    // }

    // Check proximity to our passed pawns
    var pawn_bb = our_pawns;
    while (pawn_bb != 0) {
        const pawn_sq = brd.getLSB(pawn_bb);
        const is_passed = checkPassedPawn(board, pawn_sq, color);

        if (is_passed) {
            const dist = manhattanDistance(king_sq, pawn_sq);
            if (dist <= 3) {
                score += king_pawn_proximity * (6 - dist);
            }
        }

        brd.popBit(&pawn_bb, pawn_sq);
    }

    // Penalty for being far from opponent's passed pawns
    pawn_bb = opp_pawns;
    while (pawn_bb != 0) {
        const pawn_sq = brd.getLSB(pawn_bb);
        const opp_color = if (color == brd.Color.White) brd.Color.Black else brd.Color.White;
        const is_passed = checkPassedPawn(board, pawn_sq, opp_color);

        if (is_passed) {
            const dist = manhattanDistance(king_sq, pawn_sq);
            if (dist > 4) {
                score -= 3;
            }
        }

        brd.popBit(&pawn_bb, pawn_sq);
    }

    return score;
}

fn checkPassedPawn(board: *brd.Board, sq: usize, color: brd.Color) bool {
    const file = @mod(sq, 8);
    const rank = @divTrunc(sq, 8);
    const opp_idx = if (color == brd.Color.White) @as(usize, 1) else @as(usize, 0);
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];

    const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
    const left_mask: u64 = if (file > 0) @as(u64, 0x0101010101010101) << @intCast(file - 1) else 0;
    const right_mask: u64 = if (file < 7) @as(u64, 0x0101010101010101) << @intCast(file + 1) else 0;
    const forward_mask = file_mask | left_mask | right_mask;

    const blocking_pawns = if (color == brd.Color.White) blk: {
        const rank_mask: u64 = (@as(u64, 0xFFFFFFFFFFFFFFFF) << @intCast((rank + 1) * 8));
        break :blk opp_pawns & forward_mask & rank_mask;
    } else blk: {
        const rank_mask: u64 = if (rank > 0) (@as(u64, 0xFFFFFFFFFFFFFFFF) >> @intCast((8 - rank) * 8)) else 0;
        break :blk opp_pawns & forward_mask & rank_mask;
    };

    return blocking_pawns == 0;
}

// Rook endgame evaluation
fn evalRookEndgame(board: *brd.Board, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    var score: i32 = 0;

    const rook_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];

    var temp_rook_bb = rook_bb;
    while (temp_rook_bb != 0) {
        const rook_sq = brd.getLSB(temp_rook_bb);
        const rook_rank = @divTrunc(rook_sq, 8);
        const rook_file = @mod(rook_sq, 8);

        // Rook on 7th rank bonus
        const seventh_rank: i32 = if (color == brd.Color.White) 6 else 1;
        if (rook_rank == seventh_rank) {
            score += rook_on_7th_bonus;
        }

        // Rook behind passed pawn
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(rook_file);
        const pawns_on_file = our_pawns & file_mask;

        var pawn_bb = pawns_on_file;
        while (pawn_bb != 0) {
            const pawn_sq = brd.getLSB(pawn_bb);
            const pawn_rank = @divTrunc(pawn_sq, 8);

            // Check if rook is behind the pawn and pawn is passed
            const rook_behind = if (color == brd.Color.White)
                rook_rank < pawn_rank
            else
                rook_rank > pawn_rank;

            if (rook_behind and checkPassedPawn(board, pawn_sq, color)) {
                score += rook_behind_passer_bonus;
            }

            brd.popBit(&pawn_bb, pawn_sq);
        }

        brd.popBit(&temp_rook_bb, rook_sq);
    }

    return score;
}

fn evalMobility(sq: usize, piece: brd.Pieces, board: *brd.Board, move_gen: *mvs.MoveGen, opp_pawn_attacks: u64, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    const our_pieces = board.color_bb[c_idx];

    const attacks: u64 = switch (piece) {
        .Knight => move_gen.knights[sq],
        .Bishop => move_gen.getBishopAttacks(sq, board.occupancy()),
        .Rook => move_gen.getRookAttacks(sq, board.occupancy()),
        .Queen => move_gen.getQueenAttacks(sq, board.occupancy()),
        else => 0,
    };

    const safe_mobility = attacks & ~our_pieces & ~opp_pawn_attacks;
    const count = @popCount(safe_mobility);

    const knight_bonus = [_]i32{ -8, -4, 0, 4, 8, 12, 16, 18, 20 };
    const bishop_bonus = [_]i32{ -12, -8, -4, 0, 4, 8, 12, 16, 20, 22, 24, 26, 28, 30 };
    const rook_bonus = [_]i32{ -10, -6, -2, 2, 6, 10, 14, 18, 20, 22, 24, 26, 28, 30, 32 };
    const queen_bonus = [_]i32{ -12, -8, -4, 0, 4, 8, 12, 16, 20, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60 };

    return switch (piece) {
        .Knight => if (count < knight_bonus.len) knight_bonus[count] else knight_bonus[knight_bonus.len - 1],
        .Bishop => if (count < bishop_bonus.len) bishop_bonus[count] else bishop_bonus[bishop_bonus.len - 1],
        .Rook => if (count < rook_bonus.len) rook_bonus[count] else rook_bonus[rook_bonus.len - 1],
        .Queen => if (count < queen_bonus.len) queen_bonus[count] else queen_bonus[queen_bonus.len - 1],
        else => 0,
    };
}

inline fn getKingZone(king_sq: usize, _: brd.Color, move_gen: *mvs.MoveGen) u64 {
    return move_gen.kings[king_sq] | (@as(u64, 1) << @intCast(king_sq));
}

fn evalThreats(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    var score: i32 = 0;

    // Get opponent's attack maps
    const opp_pawn_attacks = getAllPawnAttacks(board, brd.flipColor(color));
    const opp_knight_attacks = getAllKnightAttacks(board, move_gen, brd.flipColor(color));
    const opp_bishop_attacks = getAllBishopAttacks(board, move_gen, brd.flipColor(color));
    const opp_rook_attacks = getAllRookAttacks(board, move_gen, brd.flipColor(color));

    // Get our defense map
    const our_defenses = getAllDefenses(board, move_gen, color);

    // Check each of our pieces
    const pieces = [_]brd.Pieces{ .Knight, .Bishop, .Rook, .Queen };

    for (pieces) |piece| {
        var piece_bb = board.piece_bb[c_idx][@intFromEnum(piece)];

        while (piece_bb != 0) {
            const sq = brd.getLSB(piece_bb);
            const sq_mask = @as(u64, 1) << @intCast(sq);

            // Check if piece is hanging (attacked but not defended)
            const is_defended = (our_defenses & sq_mask) != 0;

            // Penalize based on what's attacking it
            if ((opp_pawn_attacks & sq_mask) != 0) {
                if (!is_defended) {
                    score -= hanging_piece_penalty + attacked_by_pawn_penalty;
                } else {
                    score -= attacked_by_pawn_penalty / 2;
                }
            }

            if ((opp_knight_attacks & sq_mask) != 0 or (opp_bishop_attacks & sq_mask) != 0) {
                if (!is_defended and piece == .Rook or piece == .Queen) {
                    score -= attacked_by_minor_penalty;
                }
            }

            if ((opp_rook_attacks & sq_mask) != 0 and piece == .Queen) {
                if (!is_defended) {
                    score -= attacked_by_rook_penalty;
                }
            }

            brd.popBit(&piece_bb, sq);
        }
    }

    return score;
}

fn getAllPawnAttacks(board: *brd.Board, color: brd.Color) u64 {
    const c_idx = @intFromEnum(color);
    const pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];

    if (color == brd.Color.White) {
        const left_attacks = (pawns << 7) & ~@as(u64, 0x8080808080808080);
        const right_attacks = (pawns << 9) & ~@as(u64, 0x0101010101010101);
        return left_attacks | right_attacks;
    } else {
        const left_attacks = (pawns >> 7) & ~@as(u64, 0x0101010101010101);
        const right_attacks = (pawns >> 9) & ~@as(u64, 0x8080808080808080);
        return left_attacks | right_attacks;
    }
}

fn getAllKnightAttacks(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) u64 {
    const c_idx = @intFromEnum(color);
    var attacks: u64 = 0;
    var knights = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];

    while (knights != 0) {
        const sq = brd.getLSB(knights);
        attacks |= move_gen.knights[sq];
        brd.popBit(&knights, sq);
    }

    return attacks;
}

fn getAllBishopAttacks(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) u64 {
    const c_idx = @intFromEnum(color);
    var attacks: u64 = 0;
    const occ = board.occupancy();
    var bishops = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];

    while (bishops != 0) {
        const sq = brd.getLSB(bishops);
        attacks |= move_gen.getBishopAttacks(sq, occ);
        brd.popBit(&bishops, sq);
    }

    return attacks;
}

fn getAllRookAttacks(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) u64 {
    const c_idx = @intFromEnum(color);
    var attacks: u64 = 0;
    const occ = board.occupancy();
    var rooks = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];

    while (rooks != 0) {
        const sq = brd.getLSB(rooks);
        attacks |= move_gen.getRookAttacks(sq, occ);
        brd.popBit(&rooks, sq);
    }

    return attacks;
}

fn getAllQueenAttacks(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) u64 {
    const c_idx = @intFromEnum(color);
    var attacks: u64 = 0;
    const occ = board.occupancy();
    var queens = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Queen)];

    while (queens != 0) {
        const sq = brd.getLSB(queens);
        attacks |= move_gen.getQueenAttacks(sq, occ);
        brd.popBit(&queens, sq);
    }

    return attacks;
}

fn getAllAttacks(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) u64 {
    var attacks: u64 = 0;
    attacks |= getAllPawnAttacks(board, color);
    attacks |= getAllKnightAttacks(board, move_gen, color);
    attacks |= getAllBishopAttacks(board, move_gen, color);
    attacks |= getAllRookAttacks(board, move_gen, color);
    attacks |= getAllQueenAttacks(board, move_gen, color);

    const c_idx = @intFromEnum(color);
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb != 0) {
        const king_sq = brd.getLSB(king_bb);
        attacks |= move_gen.kings[king_sq];
    }

    return attacks;
}

fn getAllDefenses(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) u64 {
    return getAllAttacks(board, move_gen, color);
}

fn evalSpace(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    var score: i32 = 0;

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];

    const center: u64 = 0x0000001818000000;
    const extended_center: u64 = 0x00003C3C3C3C0000;

    const our_half: u64 = if (color == brd.Color.White) 
        0x00000000FFFFFFFF 
        else 
        0xFFFFFFFF00000000;

    var pawn_bb = our_pawns;
    while (pawn_bb != 0) {
        const sq = brd.getLSB(pawn_bb);
        const rank = @divTrunc(sq, 8);

        // Bonus for advanced pawns
        const advance_bonus = if (color == brd.Color.White) 
            @as(i32, @intCast(rank)) - 1
            else 
            @as(i32, @intCast(6 - rank));

        if (advance_bonus > 0) {
            score += advance_bonus;
        }

        brd.popBit(&pawn_bb, sq);
    }

    const our_attacks = getAllAttacks(board, move_gen, color);
    const controlled_space = @popCount(our_attacks & our_half);
    score += @as(i32, @intCast(controlled_space)) * space_per_square;

    // Bonus for center control
    const center_control = @popCount(our_attacks & center);
    score += @as(i32, @intCast(center_control)) * center_control_bonus;

    const extended_control = @popCount(our_attacks & extended_center);
    score += @as(i32, @intCast(extended_control)) * extended_center_bonus;

    return score;
}

pub fn almostMate(score: i32) bool {
    return @abs(score) > mate_score - 256;
}

