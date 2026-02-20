const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const zob = @import("zobrist");
const pawn_tt = @import("pawn_tt");

pub const mate_score: i32 = 888888;

pub var lazy_margin: i32 = 810;

const total_phase: i32 = 24;
const pawn_phase: i32 = 0;
const knight_phase: i32 = 1;
const bishop_phase: i32 = 1;
const rook_phase: i32 = 2;
const queen_phase: i32 = 4;

pub var mg_pawn: i32 = 107;
pub var eg_pawn: i32 = 319;
pub var mg_knight: i32 = 455;
pub var eg_knight: i32 = 1136;
pub var mg_bishop: i32 = 496;
pub var eg_bishop: i32 = 1247;
pub var mg_rook: i32 = 619;
pub var eg_rook: i32 = 1990;
pub var mg_queen: i32 = 1843;
pub var eg_queen: i32 = 3709;
pub var mg_king: i32 = 20000;
pub var eg_king: i32 = 20000;

pub var mg_pawn_table = [64]i32{
       0,   0,   0,   0,   0,   0,   0,   0,
       1,  -24,  -19,   -7,  -17, 103, 131,  22,
      -13,  -27,   -3,   9,  33,  46,  54,  11,
       3,  11,  23,  31,  71,  72,  70,  21,
      24,  59,  37,  76, 129, 177, 118,  42,
      30, 106, 158, 112, 188, 404, 189,  57,
     315, 320, 247, 324, 353, 188, -341, -197,
       0,   0,   0,   0,   0,   0,   0,   0,
};

pub var eg_pawn_table = [64]i32{
       0,   0,   0,   0,   0,   0,   0,   0,
     129,  86, 102,  83, 112, 105,  55,   5,
      89,  79,  56,  34,  53,  55,  30,  21,
     130, 117,  27,   5,  13,  30,  38,  35,
     196, 149,  84,   -7,   -1,  15,  76,  79,
     312, 277, 184,  60,  25,  78, 149, 180,
     225, 216, 150,  15,  -24,  43, 230, 209,
       0,   0,   0,   0,   0,   0,   0,   0,
};

pub var mg_knight_table = [64]i32{
     -230,  -39, -119,  -34,   7,  14,  -14, -198,
      -62,  -85,  -12,  45,  29,  21,   -4,   5,
      -55,  13,  23,  83,  84,  63,  40,   9,
       -6,  19,  51,  59,  80,  61, 139,  46,
      69,  41, 101, 145,  72, 150,  84, 156,
      -29,  60, 166, 155, 278, 279, 173, 132,
      10,   3, 101, 177, 182, 242,  -48, 120,
     -484, -358, -289,   -8, 142, -281, -152, -387,
};

pub var eg_knight_table = [64]i32{
     -169, -155,  -31,  19,   -5,  -11,  -90, -268,
      -46,  41,  28,  51,  79,   8,  20,  -28,
      -78,  64, 100, 160, 154,  88,  70,   -5,
      38,  99, 196, 200, 196, 188, 118,  87,
      37, 106, 176, 230, 239, 205, 165,  85,
      24, 111, 158, 161, 124, 164,  98,  35,
      -52,  42,  53, 141, 116,  10,  69,  -46,
     -130,  79, 136,  91,  91, 221,  71, -203,
};

pub var mg_bishop_table = [64]i32{
      35,  52,  -16,  -76,  -75,   -2,  -26,  37,
      36,  40,  44,   0,  15,  26,  89,  37,
      -10,  33,  15,  38,  12,  45,  28,  57,
       5,   -9,  18,  63,  67,  -17,  23,   8,
      -31,  54,  19, 143,  75, 101,  44,   9,
      14,  52, 131,  51, 138, 149, 149,  24,
     -112,  -15,  -25,  -83,  -47,  28,  -93,  -58,
     -172, -150, -352, -288, -262, -385,   -2, -111,
};

pub var eg_bishop_table = [64]i32{
      -24,  13,   -3,  49,  54,  40,  10,  -28,
      48,   3,  43,  72,  76,  50,  23,  -76,
      60, 102, 109, 131, 144,  97,  76,  53,
      78, 107, 165, 152, 153, 154, 111,  80,
     116, 133, 135, 138, 179, 142, 187, 135,
     113, 140, 121, 116, 132, 178, 126, 130,
      85, 129, 147, 137, 133, 132, 163,  93,
     146, 146, 156, 174, 148, 173,  85,  95,
};

pub var mg_rook_table = [64]i32{
      -35,  -19,   1,  23,  23,  27,  57,  -14,
     -176,  -80,  -56,  -49,  -28,  15,  32, -142,
      -93,  -73,  -80,  -54,  -62,  -49,  47,  -51,
      -74,  -73,  -75,  -38,  -58,  -36,  35,   3,
      -27,  14,  42, 128,  81, 121, 148, 121,
      -12, 125,  75, 159, 252, 328, 363, 179,
      31,   1, 109, 153, 166, 285, 191, 292,
     139, 155,  44, 102,  93, 164, 288, 322,
};

pub var eg_rook_table = [64]i32{
     183, 187, 181, 157, 155, 189, 165, 122,
     172, 163, 162, 149, 137, 114, 123, 164,
     152, 210, 192, 173, 185, 177, 183, 161,
     247, 291, 270, 257, 248, 259, 247, 229,
     284, 272, 271, 234, 233, 236, 234, 266,
     300, 258, 272, 229, 202, 227, 174, 255,
     321, 333, 297, 288, 295, 208, 262, 252,
     325, 336, 350, 339, 367, 351, 342, 331,
};

pub var mg_queen_table = [64]i32{
    -28, 0,   29,  12,  59,  44,  43,  45,
    -24, -39, -5,  1,   -16, 57,  28,  54,
    -13, -17, 7,   8,   29,  56,  47,  57,
    -27, -27, -16, -16, -1,  17,  -2,  1,
    -9,  -26, -9,  -10, -2,  -4,  3,   -3,
    -14, 2,   -11, -2,  -5,  2,   14,  5,
    -35, -8,  11,  2,   8,   15,  -3,  1,
    -1,  -18, -9,  10,  -15, -25, -31, -50,
};
pub var eg_queen_table = [64]i32{
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
pub var mg_king_table = [64]i32{
    -65, 23,  16,  -15, -56, -34, 2,   13,
    29,  -1,  -20, -7,  -8,  -4,  -38, -29,
    -9,  24,  2,   -16, -20, 6,   22,  -22,
    -17, -20, -12, -27, -30, -25, -14, -36,
    -49, -1,  -27, -39, -46, -44, -33, -51,
    -14, -14, -22, -46, -44, -30, -15, -27,
    1,   7,   -8,  -64, -43, -16, 9,   8,
    -15, 36,  12,  -54, 8,   -28, 24,  14,
};
pub var eg_king_table = [64]i32{ -74, -35, -18, -18, -11, 15, 4, -17, -12, 17, 14, 17, 17, 38, 23, 11, 10, 17, 23, 15, 20, 45, 44, 13, -8, 22, 24, 27, 26, 33, 26, 3, -18, -4, 21, 24, 27, 23, 9, -11, -19, -3, 11, 21, 23, 16, 7, -9, -27, -11, 4, 13, 14, 4, -5, -17, -53, -34, -21, -11, -28, -14, -24, -43 };

pub var knight_mobility_bonus = [9]i32{ 58, 101, 121, 140, 153, 160, 174, 175, 149, };
pub var bishop_mobility_bonus = [14]i32{ 50, 65, 84, 101, 126, 137, 147, 153, 160, 166, 167, 160, 178, 123, };
pub var rook_mobility_bonus = [15]i32{ 166, 183, 197, 206, 214, 225, 236, 253, 259, 273, 282, 287, 295, 266, 234, };
pub var queen_mobility_bonus = [28]i32{ 205, 219, 239, 246, 249, 261, 272, 280, 296, 310, 323, 322, 336, 336, 345, 353, 356, 337, 350, 362, 366, 332, 333, 302, 303, 322, 331, 363, };
pub var mg_passed_bonus = [8]i32{ 0, -1, 1, 14, 124, 256, 433, 0, };
pub var passed_pawn_bonus = [8]i32{ 0, 3, 14, 70, 113, 201, 314, 0, };
pub var safety_table = [16]i32{ 77, 74, 90, 77, 121, 86, 97, 86, 81, 97, 110, 161, 97, 236, 216, 146, };
pub var castled_bonus: i32 = 22;
pub var pawn_shield_bonus: i32 = 26;
pub var open_file_penalty: i32 = -132;
pub var semi_open_penalty: i32 = -15;
pub var knight_attack_bonus: i32 = 1348;
pub var bishop_attack_bonus: i32 = 51;
pub var rook_attack_bonus: i32 = -3927;
pub var queen_attack_bonus: i32 = -3558;
pub var rook_on_7th_bonus: i32 = 14;
pub var rook_behind_passer_bonus: i32 = 26;
pub var king_pawn_proximity: i32 = 16;
pub var protected_pawn_bonus: i32 = 28;
pub var doubled_pawn_penalty: i32 = -25;
pub var isolated_pawn_penalty: i32 = -39;
pub var connected_pawn_bonus: i32 = 10;
pub var backward_pawn_penalty: i32 = -15;
pub var rook_on_open_file_bonus: i32 = 77;
pub var rook_on_semi_open_file_bonus: i32 = 44;
pub var trapped_rook_penalty: i32 = 50;
pub var minor_threat_penalty: i32 = 77;
pub var rook_threat_penalty: i32 = 19;
pub var queen_threat_penalty: i32 = 27;
pub var rook_on_queen_bonus: i32 = 20;
pub var rook_on_king_bonus: i32 = -7;
pub var queen_on_king_bonus: i32 = 10;
pub var bad_bishop_penalty: i32 = 15;
pub var bishop_on_queen_bonus: i32 = 25;
pub var bishop_on_king_bonus: i32 = 15;
pub var hanging_piece_penalty: i32 = 40;
pub var attacked_by_pawn_penalty: i32 = 35;
pub var attacked_by_minor_penalty: i32 = 25;
pub var attacked_by_rook_penalty: i32 = 20;

// Miscellaneous Bonuses
pub var tempo_bonus: i32 = 10;
pub var bishop_pair_bonus: i32 = 30;
pub var knight_outpost_bonus: i32 = 30;
pub var space_per_square: i32 = 2;
pub var center_control_bonus: i32 = 10;
pub var extended_center_bonus: i32 = 5;

const EvalStruct = struct {
    mg: i32,
    eg: i32,
};

const AttackCache = struct {
    occupancy: u64 = 0,

    our_pawn_attacks: u64 = 0,
    opp_pawn_attacks: u64 = 0,

    our_knight_attacks: u64 = 0,
    opp_knight_attacks: u64 = 0,

    our_bishop_attacks: u64 = 0,
    opp_bishop_attacks: u64 = 0,

    our_rook_attacks: u64 = 0,
    opp_rook_attacks: u64 = 0,

    our_queen_attacks: u64 = 0,
    opp_queen_attacks: u64 = 0,

    our_defenses: u64 = 0,
    opp_defenses: u64 = 0,
};

fn populateAttackCache(board: *brd.Board, move_gen: *mvs.MoveGen) AttackCache {
    var cache = AttackCache{};

    cache.occupancy = board.occupancy();

    cache.our_pawn_attacks = getPawnAttacks(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Pawn)], brd.Color.White);
    cache.opp_pawn_attacks = getPawnAttacks(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Pawn)], brd.Color.Black);

    cache.our_knight_attacks = getAllKnightAttacks(board, move_gen, brd.Color.White);
    cache.opp_knight_attacks = getAllKnightAttacks(board, move_gen, brd.Color.Black);

    cache.our_bishop_attacks = getAllBishopAttacks(board, move_gen, brd.Color.White);
    cache.opp_bishop_attacks = getAllBishopAttacks(board, move_gen, brd.Color.Black);

    cache.our_rook_attacks = getAllRookAttacks(board, move_gen, brd.Color.White);
    cache.opp_rook_attacks = getAllRookAttacks(board, move_gen, brd.Color.Black);

    cache.our_queen_attacks = getAllQueenAttacks(board, move_gen, brd.Color.White);
    cache.opp_queen_attacks = getAllQueenAttacks(board, move_gen, brd.Color.Black);

    cache.our_defenses = (cache.our_pawn_attacks | cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks);

    const c_idx = @intFromEnum(brd.Color.White);
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb != 0) {
        const king_sq = brd.getLSB(king_bb);
        cache.our_defenses |= move_gen.kings[king_sq];
    }

    cache.opp_defenses = (cache.opp_pawn_attacks | cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks);

    const c_idx_black = @intFromEnum(brd.Color.Black);
    const opp_king_bb = board.piece_bb[c_idx_black][@intFromEnum(brd.Pieces.King)];
    if (opp_king_bb != 0) {
        const opp_king_sq = brd.getLSB(opp_king_bb);
        cache.opp_defenses |= move_gen.kings[opp_king_sq];
    }

    return cache;
}


// Mirror array for black to flip the square index
const mirror_sq = initMirror();
fn initMirror() [64]usize {
    var table: [64]usize = undefined;
    for (0..64) |i| {
        table[i] = i ^ 56; // Flip Rank (a1 <-> a8)
    }
    return table;
}

// Distance allowing diagonal moves
fn kingDistance(king_sq: usize, sq: usize) i32 {
    const file1: i32 = @intCast(@mod(king_sq, 8));
    const rank1: i32 = @intCast(@divTrunc(king_sq, 8));
    const file2: i32 = @intCast(@mod(sq, 8));
    const rank2: i32 = @intCast(@divTrunc(sq, 8));
    return @as(i32, @intCast(@max(@abs(file1 - file2), @abs(rank1 - rank2))));
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

// Main Evaluate Function - Now with Lazy Evaluation support
// Pass alpha and beta to allow early exits if the position is clearly decided by material
pub fn evaluate(board: *brd.Board, move_gen: *mvs.MoveGen, alpha: i32, beta: i32, exact: bool) i32 {
    var current_phase: i32 = 0;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][1]) + @popCount(board.piece_bb[1][1]))) * knight_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][2]) + @popCount(board.piece_bb[1][2]))) * bishop_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][3]) + @popCount(board.piece_bb[1][3]))) * rook_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][4]) + @popCount(board.piece_bb[1][4]))) * queen_phase;
    current_phase = std.math.clamp(current_phase, 0, total_phase);

    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

    // STAGE 1: Lazy Evaluation
    const white_base = evalBase(board, brd.Color.White);
    const black_base = evalBase(board, brd.Color.Black);

    pawn_tt.pawn_tt.prefetch(board.game_state.pawn_hash ^ zob.ZobristKeys.eval_phase[@as(usize, @intCast(current_phase))]);
    mg_score += white_base.mg - black_base.mg;
    eg_score += white_base.eg - black_base.eg;

    // checking pawn_tt is fast so if we get a hit we use it
    var got_pawns = false;
    if (pawn_tt.pawn_tt.get(board.game_state.pawn_hash ^ zob.ZobristKeys.eval_phase[@as(usize, @intCast(current_phase))])) |e| {
        mg_score += e.mg;
        eg_score += e.eg;
        got_pawns = true;
    }

    var score = (mg_score * current_phase + eg_score * (total_phase - current_phase));
    score = @divTrunc(score, total_phase);

    var lazy_score = score;
    if (board.toMove() == brd.Color.Black) {
        lazy_score = -score;
    }

    // Lazy Cutoff
    if (!exact and lazy_score + lazy_margin <= alpha) {
        return lazy_score + lazy_margin;
    }
    if (!exact and lazy_score - lazy_margin >= beta) {
        return lazy_score - lazy_margin;
    }

    // --- STAGE 2
    const attack_cache = populateAttackCache(board, move_gen);

    const white_activity = evalPieceActivity(board, brd.Color.White, move_gen, attack_cache);
    const black_activity = evalPieceActivity(board, brd.Color.Black, move_gen, attack_cache);

    mg_score += white_activity.mg - black_activity.mg;
    eg_score += white_activity.eg - black_activity.eg;

    mg_score += evalKingSafety(board, brd.Color.White);
    mg_score -= evalKingSafety(board, brd.Color.Black);

    if (!got_pawns) {
        const pawn_eval = evalPawnStructure(board, current_phase);
        mg_score += pawn_eval.mg;
        eg_score += pawn_eval.eg;
    }

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

    var global_score: i32 = 0;
    global_score += evalThreats(board, brd.Color.White, attack_cache);
    global_score -= evalThreats(board, brd.Color.Black, attack_cache);

    global_score += evalSpace(board, brd.Color.White, attack_cache);
    global_score -= evalSpace(board, brd.Color.Black, attack_cache);

    global_score += evalExchangeAvoidance(board);

    mg_score += global_score;
    eg_score += global_score;

    var final_score = (mg_score * current_phase + eg_score * (total_phase - current_phase));
    final_score = @divTrunc(final_score, total_phase);

    if (board.toMove() == brd.Color.White) {
        return final_score + tempo_bonus;
    } else {
        return -final_score + tempo_bonus;
    }
}

// Stage 1
fn evalBase(board: *brd.Board, color: brd.Color) EvalStruct {
    const c_idx = @intFromEnum(color);
    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

    const getPst = struct {
        fn get(sq: usize, table: [64]i32, c: brd.Color) i32 {
            if (c == brd.Color.White) return table[sq];
            return table[mirror_sq[sq]];
        }
    }.get;

    // Pawns
    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_pawn + getPst(sq, mg_pawn_table, color);
        eg_score += eg_pawn + getPst(sq, eg_pawn_table, color);
        brd.popBit(&bb, sq);
    }

    // Knights
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_knight + getPst(sq, mg_knight_table, color);
        eg_score += eg_knight + getPst(sq, eg_knight_table, color);
        brd.popBit(&bb, sq);
    }

    // Bishops
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_bishop + getPst(sq, mg_bishop_table, color);
        eg_score += eg_bishop + getPst(sq, eg_bishop_table, color);
        brd.popBit(&bb, sq);
    }

    // Rooks
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_rook + getPst(sq, mg_rook_table, color);
        eg_score += eg_rook + getPst(sq, eg_rook_table, color);
        brd.popBit(&bb, sq);
    }

    // Queens
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Queen)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_queen + getPst(sq, mg_queen_table, color);
        eg_score += eg_queen + getPst(sq, eg_queen_table, color);
        brd.popBit(&bb, sq);
    }

    // King
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (bb != 0) {
        const sq = brd.getLSB(bb);
        mg_score += mg_king + getPst(sq, mg_king_table, color);
        eg_score += eg_king + getPst(sq, eg_king_table, color);
    }

    return EvalStruct{ .mg = mg_score, .eg = eg_score };
}

// Stage 2
fn evalPieceActivity(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen, cache: AttackCache) EvalStruct {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    var score: i32 = 0;

    var attack_units: i32 = 0;
    var attacker_count: i32 = 0;

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];

    // const our_pawn_attacks = cache.our_pawn_attacks;
    // const opp_pawn_attacks = cache.opp_pawn_attacks;
    var our_pawn_attacks: u64 = 0;
    var opp_pawn_attacks: u64 = 0;
    if (color == .White) {
        our_pawn_attacks = cache.our_pawn_attacks;
        opp_pawn_attacks = cache.opp_pawn_attacks;
    } else {
        our_pawn_attacks = cache.opp_pawn_attacks;
        opp_pawn_attacks = cache.our_pawn_attacks;
    }

    const opp_king_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.King)];
    const opp_queen_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Queen)];
    const occupancy = cache.occupancy;
    const opp_king_sq = brd.getLSB(opp_king_bb);
    const opp_king_zone = getKingZone(opp_king_sq, color.opposite(), move_gen);

    // Knights
    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);

        const rank = @divTrunc(sq, 8);
        const relative_rank = if (color == brd.Color.White) rank else 7 - rank;
        const is_supported = (our_pawn_attacks & (@as(u64, 1) << @intCast(sq))) != 0;

        if (is_supported and relative_rank >= 3 and relative_rank <= 5) {
            score += knight_outpost_bonus;
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

        brd.popBit(&bb, sq);
    }

    // Queens
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Queen)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);

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

        brd.popBit(&bb, sq);
    }

    var safety_bonus: i32 = 0;
    if (attacker_count > 1) {
        const index = @as(usize, @intCast(@min(attack_units, 15)));
        safety_bonus = safety_table[index];
    }

    return EvalStruct{
        .mg = score + safety_bonus,
        .eg = score,
    };
}

// King Safety evaluation
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
            break :blk king_sq == 6 or king_sq == 2;
        } else {
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
            safety += open_file_penalty;
        } else if (our_pawns_on_file == 0 and their_pawns_on_file != 0) {
            safety += semi_open_penalty;
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

    pawn_tt.pawn_tt.set(pawn_tt.Entry{
        .hash = board.game_state.pawn_hash ^ zob.ZobristKeys.eval_phase[@as(usize, @intCast(phase))],
        .mg = result.mg,
        .eg = result.eg,
    });

    return result;
}

fn evalPawnsForColor(board: *brd.Board, color: brd.Color, phase: i32) PawnEval {
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
    pawn_bb = board.piece_bb[1 - c_idx][@intFromEnum(brd.Pieces.Pawn)];
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
    return switch (piece) {
        .Knight => if (count < knight_mobility_bonus.len) knight_mobility_bonus[count] else knight_mobility_bonus[knight_mobility_bonus.len - 1],
        .Bishop => if (count < bishop_mobility_bonus.len) bishop_mobility_bonus[count] else bishop_mobility_bonus[bishop_mobility_bonus.len - 1],
        .Rook => if (count < rook_mobility_bonus.len) rook_mobility_bonus[count] else rook_mobility_bonus[rook_mobility_bonus.len - 1],
        .Queen => if (count < queen_mobility_bonus.len) queen_mobility_bonus[count] else queen_mobility_bonus[queen_mobility_bonus.len - 1],
        else => 0,
    };
}

inline fn getKingZone(king_sq: usize, _: brd.Color, move_gen: *mvs.MoveGen) u64 {
    return move_gen.kings[king_sq] | (@as(u64, 1) << @intCast(king_sq));
}

fn evalThreats(board: *brd.Board, color: brd.Color, cache: AttackCache) i32 {
    const c_idx = @intFromEnum(color);
    var score: i32 = 0;

    var opp_pawn_attacks: u64 = 0;
    var opp_knight_attacks: u64 = 0;
    var opp_bishop_attacks: u64 = 0;
    var opp_rook_attacks: u64 = 0;

    var our_defenses: u64 = 0;

    if (color == .White) {
        opp_pawn_attacks = cache.opp_pawn_attacks;
        opp_knight_attacks = cache.opp_knight_attacks;
        opp_bishop_attacks = cache.opp_bishop_attacks;
        opp_rook_attacks = cache.opp_rook_attacks;
        our_defenses = cache.our_defenses;
    } else {
        opp_pawn_attacks = cache.our_pawn_attacks;
        opp_knight_attacks = cache.our_knight_attacks;
        opp_bishop_attacks = cache.our_bishop_attacks;
        opp_rook_attacks = cache.our_rook_attacks;
        our_defenses = cache.opp_defenses;
    }

    // Get our defense map
    // const our_defenses = getAllDefenses(board, move_gen, color);
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
                    score -= @divTrunc(attacked_by_pawn_penalty, 2);
                }
            }

            if ((opp_knight_attacks & sq_mask) != 0 or (opp_bishop_attacks & sq_mask) != 0) {
                if (!is_defended and (piece == .Rook or piece == .Queen)) {
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

fn evalSpace(board: *brd.Board, color: brd.Color, cache: AttackCache) i32 {
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

    // const our_attacks = getAllAttacks(board, move_gen, color);
    var our_attacks: u64 = 0;
    if (color == .White) {
        our_attacks = cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks | cache.our_defenses;
    } else {
        our_attacks = cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks | cache.opp_defenses;
    }

    const controlled_space = @popCount(our_attacks & our_half);
    score += @as(i32, @intCast(controlled_space)) * space_per_square;
    // Bonus for center control
    const center_control = @popCount(our_attacks & center);
    score += @as(i32, @intCast(center_control)) * center_control_bonus;
    const extended_control = @popCount(our_attacks & extended_center);
    score += @as(i32, @intCast(extended_control)) * extended_center_bonus;

    return score;
}

// Exchange avoidance: reward keeping pieces when material-ahead
fn evalExchangeAvoidance(board: *brd.Board) i32 {
    const white_mat = countMaterial(board, brd.Color.White);
    const black_mat = countMaterial(board, brd.Color.Black);
    const diff = white_mat - black_mat;
    if (@abs(diff) < 100) return 0; // Only applies when meaningfully ahead

    const white_pieces = @popCount(board.color_bb[@intFromEnum(brd.Color.White)]);
    const black_pieces = @popCount(board.color_bb[@intFromEnum(brd.Color.Black)]);
    const total_pieces: i32 = @intCast(white_pieces + black_pieces);

    // The winning side wants more pieces on the board
    const sign: i32 = if (diff > 0) 1 else -1;
    return sign * @divTrunc(total_pieces * 5, 1);
}

pub fn almostMate(score: i32) bool {
    return @abs(score) > mate_score - 256;
}

// =============================================================================
// TEXEL TUNER INFRASTRUCTURE
// =============================================================================

// ---------------------------------------------------------------------------
// Parameter layout — flat array of all tunable integers.
// Any change here must be mirrored in exportParams / importParams.
// ---------------------------------------------------------------------------
pub const P_MG_PAWN: usize = 0;
pub const P_EG_PAWN: usize = 1;
pub const P_MG_KNIGHT: usize = 2;
pub const P_EG_KNIGHT: usize = 3;
pub const P_MG_BISHOP: usize = 4;
pub const P_EG_BISHOP: usize = 5;
pub const P_MG_ROOK: usize = 6;
pub const P_EG_ROOK: usize = 7;
pub const P_MG_QUEEN: usize = 8;
pub const P_EG_QUEEN: usize = 9;
pub const P_MG_KING: usize = 10;
pub const P_EG_KING: usize = 11;

// PST blocks — 12 tables * 64 squares = 768 params
pub const P_MG_PAWN_TABLE: usize = 12;
pub const P_EG_PAWN_TABLE: usize = P_MG_PAWN_TABLE + 64;
pub const P_MG_KNIGHT_TABLE: usize = P_EG_PAWN_TABLE + 64;
pub const P_EG_KNIGHT_TABLE: usize = P_MG_KNIGHT_TABLE + 64;
pub const P_MG_BISHOP_TABLE: usize = P_EG_KNIGHT_TABLE + 64;
pub const P_EG_BISHOP_TABLE: usize = P_MG_BISHOP_TABLE + 64;
pub const P_MG_ROOK_TABLE: usize = P_EG_BISHOP_TABLE + 64;
pub const P_EG_ROOK_TABLE: usize = P_MG_ROOK_TABLE + 64;
pub const P_MG_QUEEN_TABLE: usize = P_EG_ROOK_TABLE + 64;
pub const P_EG_QUEEN_TABLE: usize = P_MG_QUEEN_TABLE + 64;
pub const P_MG_KING_TABLE: usize = P_EG_QUEEN_TABLE + 64;
pub const P_EG_KING_TABLE: usize = P_MG_KING_TABLE + 64;

// Mobility tables
pub const P_KNIGHT_MOB: usize = P_EG_KING_TABLE + 64; // 9 entries
pub const P_BISHOP_MOB: usize = P_KNIGHT_MOB + 9;     // 14 entries
pub const P_ROOK_MOB: usize = P_BISHOP_MOB + 14;      // 15 entries
pub const P_QUEEN_MOB: usize = P_ROOK_MOB + 15;       // 28 entries

// Passed pawn tables
pub const P_MG_PASSED: usize = P_QUEEN_MOB + 28; // 8 entries
pub const P_EG_PASSED: usize = P_MG_PASSED + 8;  // 8 entries

// Safety table
pub const P_SAFETY_TABLE: usize = P_EG_PASSED + 8; // 16 entries

// Scalar bonuses/penalties
pub const P_CASTLED_BONUS: usize = P_SAFETY_TABLE + 16;
pub const P_PAWN_SHIELD_BONUS: usize = P_CASTLED_BONUS + 1;
pub const P_OPEN_FILE_PENALTY: usize = P_PAWN_SHIELD_BONUS + 1;
pub const P_SEMI_OPEN_PENALTY: usize = P_OPEN_FILE_PENALTY + 1;
pub const P_KNIGHT_ATTACK_BONUS: usize = P_SEMI_OPEN_PENALTY + 1;
pub const P_BISHOP_ATTACK_BONUS: usize = P_KNIGHT_ATTACK_BONUS + 1;
pub const P_ROOK_ATTACK_BONUS: usize = P_BISHOP_ATTACK_BONUS + 1;
pub const P_QUEEN_ATTACK_BONUS: usize = P_ROOK_ATTACK_BONUS + 1;
pub const P_ROOK_7TH_BONUS: usize = P_QUEEN_ATTACK_BONUS + 1;
pub const P_ROOK_PASSER_BONUS: usize = P_ROOK_7TH_BONUS + 1;
pub const P_KING_PAWN_PROXIMITY: usize = P_ROOK_PASSER_BONUS + 1;
pub const P_PROTECTED_PAWN: usize = P_KING_PAWN_PROXIMITY + 1;
pub const P_DOUBLED_PAWN: usize = P_PROTECTED_PAWN + 1;
pub const P_ISOLATED_PAWN: usize = P_DOUBLED_PAWN + 1;
pub const P_CONNECTED_PAWN: usize = P_ISOLATED_PAWN + 1;
pub const P_BACKWARD_PAWN: usize = P_CONNECTED_PAWN + 1;
pub const P_ROOK_OPEN_FILE: usize = P_BACKWARD_PAWN + 1;
pub const P_ROOK_SEMI_OPEN: usize = P_ROOK_OPEN_FILE + 1;
pub const P_TRAPPED_ROOK: usize = P_ROOK_SEMI_OPEN + 1;
pub const P_MINOR_THREAT: usize = P_TRAPPED_ROOK + 1;
pub const P_ROOK_THREAT: usize = P_MINOR_THREAT + 1;
pub const P_QUEEN_THREAT: usize = P_ROOK_THREAT + 1;
pub const P_ROOK_ON_QUEEN: usize = P_QUEEN_THREAT + 1;
pub const P_ROOK_ON_KING: usize = P_ROOK_ON_QUEEN + 1;
pub const P_QUEEN_ON_KING: usize = P_ROOK_ON_KING + 1;
pub const P_BAD_BISHOP: usize = P_QUEEN_ON_KING + 1;
pub const P_BISHOP_ON_QUEEN: usize = P_BAD_BISHOP + 1;
pub const P_BISHOP_ON_KING: usize = P_BISHOP_ON_QUEEN + 1;
pub const P_HANGING_PIECE: usize = P_BISHOP_ON_KING + 1;
pub const P_ATK_BY_PAWN: usize = P_HANGING_PIECE + 1;
pub const P_ATK_BY_MINOR: usize = P_ATK_BY_PAWN + 1;
pub const P_ATK_BY_ROOK: usize = P_ATK_BY_MINOR + 1;
pub const P_TEMPO_BONUS: usize = P_ATK_BY_ROOK + 1;
pub const P_BISHOP_PAIR: usize = P_TEMPO_BONUS + 1;
pub const P_KNIGHT_OUTPOST: usize = P_BISHOP_PAIR + 1;
pub const P_SPACE_PER_SQ: usize = P_KNIGHT_OUTPOST + 1;
pub const P_CENTER_CTRL: usize = P_SPACE_PER_SQ + 1;
pub const P_EXTENDED_CENTER: usize = P_CENTER_CTRL + 1;

pub const NUM_PARAMS: usize = P_EXTENDED_CENTER + 1;

/// Serialize all tunable parameters into a flat i32 buffer.
pub fn exportParams(buf: []i32) void {
    std.debug.assert(buf.len >= NUM_PARAMS);

    buf[P_MG_PAWN] = mg_pawn;
    buf[P_EG_PAWN] = eg_pawn;
    buf[P_MG_KNIGHT] = mg_knight;
    buf[P_EG_KNIGHT] = eg_knight;
    buf[P_MG_BISHOP] = mg_bishop;
    buf[P_EG_BISHOP] = eg_bishop;
    buf[P_MG_ROOK] = mg_rook;
    buf[P_EG_ROOK] = eg_rook;
    buf[P_MG_QUEEN] = mg_queen;
    buf[P_EG_QUEEN] = eg_queen;
    buf[P_MG_KING] = mg_king;
    buf[P_EG_KING] = eg_king;

    for (0..64) |i| buf[P_MG_PAWN_TABLE + i] = mg_pawn_table[i];
    for (0..64) |i| buf[P_EG_PAWN_TABLE + i] = eg_pawn_table[i];
    for (0..64) |i| buf[P_MG_KNIGHT_TABLE + i] = mg_knight_table[i];
    for (0..64) |i| buf[P_EG_KNIGHT_TABLE + i] = eg_knight_table[i];
    for (0..64) |i| buf[P_MG_BISHOP_TABLE + i] = mg_bishop_table[i];
    for (0..64) |i| buf[P_EG_BISHOP_TABLE + i] = eg_bishop_table[i];
    for (0..64) |i| buf[P_MG_ROOK_TABLE + i] = mg_rook_table[i];
    for (0..64) |i| buf[P_EG_ROOK_TABLE + i] = eg_rook_table[i];
    for (0..64) |i| buf[P_MG_QUEEN_TABLE + i] = mg_queen_table[i];
    for (0..64) |i| buf[P_EG_QUEEN_TABLE + i] = eg_queen_table[i];
    for (0..64) |i| buf[P_MG_KING_TABLE + i] = mg_king_table[i];
    for (0..64) |i| buf[P_EG_KING_TABLE + i] = eg_king_table[i];

    for (0..9) |i| buf[P_KNIGHT_MOB + i] = knight_mobility_bonus[i];
    for (0..14) |i| buf[P_BISHOP_MOB + i] = bishop_mobility_bonus[i];
    for (0..15) |i| buf[P_ROOK_MOB + i] = rook_mobility_bonus[i];
    for (0..28) |i| buf[P_QUEEN_MOB + i] = queen_mobility_bonus[i];

    for (0..8) |i| buf[P_MG_PASSED + i] = mg_passed_bonus[i];
    for (0..8) |i| buf[P_EG_PASSED + i] = passed_pawn_bonus[i];

    for (0..16) |i| buf[P_SAFETY_TABLE + i] = safety_table[i];

    buf[P_CASTLED_BONUS] = castled_bonus;
    buf[P_PAWN_SHIELD_BONUS] = pawn_shield_bonus;
    buf[P_OPEN_FILE_PENALTY] = open_file_penalty;
    buf[P_SEMI_OPEN_PENALTY] = semi_open_penalty;
    buf[P_KNIGHT_ATTACK_BONUS] = knight_attack_bonus;
    buf[P_BISHOP_ATTACK_BONUS] = bishop_attack_bonus;
    buf[P_ROOK_ATTACK_BONUS] = rook_attack_bonus;
    buf[P_QUEEN_ATTACK_BONUS] = queen_attack_bonus;
    buf[P_ROOK_7TH_BONUS] = rook_on_7th_bonus;
    buf[P_ROOK_PASSER_BONUS] = rook_behind_passer_bonus;
    buf[P_KING_PAWN_PROXIMITY] = king_pawn_proximity;
    buf[P_PROTECTED_PAWN] = protected_pawn_bonus;
    buf[P_DOUBLED_PAWN] = doubled_pawn_penalty;
    buf[P_ISOLATED_PAWN] = isolated_pawn_penalty;
    buf[P_CONNECTED_PAWN] = connected_pawn_bonus;
    buf[P_BACKWARD_PAWN] = backward_pawn_penalty;
    buf[P_ROOK_OPEN_FILE] = rook_on_open_file_bonus;
    buf[P_ROOK_SEMI_OPEN] = rook_on_semi_open_file_bonus;
    buf[P_TRAPPED_ROOK] = trapped_rook_penalty;
    buf[P_MINOR_THREAT] = minor_threat_penalty;
    buf[P_ROOK_THREAT] = rook_threat_penalty;
    buf[P_QUEEN_THREAT] = queen_threat_penalty;
    buf[P_ROOK_ON_QUEEN] = rook_on_queen_bonus;
    buf[P_ROOK_ON_KING] = rook_on_king_bonus;
    buf[P_QUEEN_ON_KING] = queen_on_king_bonus;
    buf[P_BAD_BISHOP] = bad_bishop_penalty;
    buf[P_BISHOP_ON_QUEEN] = bishop_on_queen_bonus;
    buf[P_BISHOP_ON_KING] = bishop_on_king_bonus;
    buf[P_HANGING_PIECE] = hanging_piece_penalty;
    buf[P_ATK_BY_PAWN] = attacked_by_pawn_penalty;
    buf[P_ATK_BY_MINOR] = attacked_by_minor_penalty;
    buf[P_ATK_BY_ROOK] = attacked_by_rook_penalty;
    buf[P_TEMPO_BONUS] = tempo_bonus;
    buf[P_BISHOP_PAIR] = bishop_pair_bonus;
    buf[P_KNIGHT_OUTPOST] = knight_outpost_bonus;
    buf[P_SPACE_PER_SQ] = space_per_square;
    buf[P_CENTER_CTRL] = center_control_bonus;
    buf[P_EXTENDED_CENTER] = extended_center_bonus;
}

/// Load parameters from a flat buffer back into the eval globals.
pub fn importParams(buf: []const i32) void {
    std.debug.assert(buf.len >= NUM_PARAMS);

    mg_pawn = buf[P_MG_PAWN];
    eg_pawn = buf[P_EG_PAWN];
    mg_knight = buf[P_MG_KNIGHT];
    eg_knight = buf[P_EG_KNIGHT];
    mg_bishop = buf[P_MG_BISHOP];
    eg_bishop = buf[P_EG_BISHOP];
    mg_rook = buf[P_MG_ROOK];
    eg_rook = buf[P_EG_ROOK];
    mg_queen = buf[P_MG_QUEEN];
    eg_queen = buf[P_EG_QUEEN];
    mg_king = buf[P_MG_KING];
    eg_king = buf[P_EG_KING];

    for (0..64) |i| mg_pawn_table[i] = buf[P_MG_PAWN_TABLE + i];
    for (0..64) |i| eg_pawn_table[i] = buf[P_EG_PAWN_TABLE + i];
    for (0..64) |i| mg_knight_table[i] = buf[P_MG_KNIGHT_TABLE + i];
    for (0..64) |i| eg_knight_table[i] = buf[P_EG_KNIGHT_TABLE + i];
    for (0..64) |i| mg_bishop_table[i] = buf[P_MG_BISHOP_TABLE + i];
    for (0..64) |i| eg_bishop_table[i] = buf[P_EG_BISHOP_TABLE + i];
    for (0..64) |i| mg_rook_table[i] = buf[P_MG_ROOK_TABLE + i];
    for (0..64) |i| eg_rook_table[i] = buf[P_EG_ROOK_TABLE + i];
    for (0..64) |i| mg_queen_table[i] = buf[P_MG_QUEEN_TABLE + i];
    for (0..64) |i| eg_queen_table[i] = buf[P_EG_QUEEN_TABLE + i];
    for (0..64) |i| mg_king_table[i] = buf[P_MG_KING_TABLE + i];
    for (0..64) |i| eg_king_table[i] = buf[P_EG_KING_TABLE + i];

    for (0..9) |i| knight_mobility_bonus[i] = buf[P_KNIGHT_MOB + i];
    for (0..14) |i| bishop_mobility_bonus[i] = buf[P_BISHOP_MOB + i];
    for (0..15) |i| rook_mobility_bonus[i] = buf[P_ROOK_MOB + i];
    for (0..28) |i| queen_mobility_bonus[i] = buf[P_QUEEN_MOB + i];

    for (0..8) |i| mg_passed_bonus[i] = buf[P_MG_PASSED + i];
    for (0..8) |i| passed_pawn_bonus[i] = buf[P_EG_PASSED + i];

    for (0..16) |i| safety_table[i] = buf[P_SAFETY_TABLE + i];

    castled_bonus = buf[P_CASTLED_BONUS];
    pawn_shield_bonus = buf[P_PAWN_SHIELD_BONUS];
    open_file_penalty = buf[P_OPEN_FILE_PENALTY];
    semi_open_penalty = buf[P_SEMI_OPEN_PENALTY];
    knight_attack_bonus = buf[P_KNIGHT_ATTACK_BONUS];
    bishop_attack_bonus = buf[P_BISHOP_ATTACK_BONUS];
    rook_attack_bonus = buf[P_ROOK_ATTACK_BONUS];
    queen_attack_bonus = buf[P_QUEEN_ATTACK_BONUS];
    rook_on_7th_bonus = buf[P_ROOK_7TH_BONUS];
    rook_behind_passer_bonus = buf[P_ROOK_PASSER_BONUS];
    king_pawn_proximity = buf[P_KING_PAWN_PROXIMITY];
    protected_pawn_bonus = buf[P_PROTECTED_PAWN];
    doubled_pawn_penalty = buf[P_DOUBLED_PAWN];
    isolated_pawn_penalty = buf[P_ISOLATED_PAWN];
    connected_pawn_bonus = buf[P_CONNECTED_PAWN];
    backward_pawn_penalty = buf[P_BACKWARD_PAWN];
    rook_on_open_file_bonus = buf[P_ROOK_OPEN_FILE];
    rook_on_semi_open_file_bonus = buf[P_ROOK_SEMI_OPEN];
    trapped_rook_penalty = buf[P_TRAPPED_ROOK];
    minor_threat_penalty = buf[P_MINOR_THREAT];
    rook_threat_penalty = buf[P_ROOK_THREAT];
    queen_threat_penalty = buf[P_QUEEN_THREAT];
    rook_on_queen_bonus = buf[P_ROOK_ON_QUEEN];
    rook_on_king_bonus = buf[P_ROOK_ON_KING];
    queen_on_king_bonus = buf[P_QUEEN_ON_KING];
    bad_bishop_penalty = buf[P_BAD_BISHOP];
    bishop_on_queen_bonus = buf[P_BISHOP_ON_QUEEN];
    bishop_on_king_bonus = buf[P_BISHOP_ON_KING];
    hanging_piece_penalty = buf[P_HANGING_PIECE];
    attacked_by_pawn_penalty = buf[P_ATK_BY_PAWN];
    attacked_by_minor_penalty = buf[P_ATK_BY_MINOR];
    attacked_by_rook_penalty = buf[P_ATK_BY_ROOK];
    tempo_bonus = buf[P_TEMPO_BONUS];
    bishop_pair_bonus = buf[P_BISHOP_PAIR];
    knight_outpost_bonus = buf[P_KNIGHT_OUTPOST];
    space_per_square = buf[P_SPACE_PER_SQ];
    center_control_bonus = buf[P_CENTER_CTRL];
    extended_center_bonus = buf[P_EXTENDED_CENTER];
}

pub fn evalTuner(board: *brd.Board, move_gen: *mvs.MoveGen) i32 {
    const raw = evaluate(board, move_gen, -mate_score, mate_score, true);
    // convert to white's perspective.
    return if (board.toMove() == .White) raw else -raw;
}

// =========================================================================
// Analytical gradient support — coefficient vector extraction
// =========================================================================
//
// computeCoefficients mirrors the evaluate() logic and returns, for each
// tunable parameter, the partial derivative d(evalTuner) / d(param[i]).
//
// Because the eval is almost entirely a linear combination of parameters
// weighted by board-derived features, the derivative for most parameters
// is simply the "coefficient" — how many times that parameter is added to
// the final score.  The only non-linear interaction is the safety_table
// lookup; we handle that with a discrete approximation.
//
// The returned vector is from WHITE's perspective (matching evalTuner).
// =========================================================================

pub fn computeCoefficients(board: *brd.Board, move_gen: *mvs.MoveGen) [NUM_PARAMS]f64 {
    // mg[i] = how much param[i] contributes to mg_score (white-relative)
    // eg[i] = how much param[i] contributes to eg_score (white-relative)
    var mg_c = std.mem.zeroes([NUM_PARAMS]f64);
    var eg_c = std.mem.zeroes([NUM_PARAMS]f64);

    // Phase (same computation as evaluate)
    var current_phase: i32 = 0;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][1]) + @popCount(board.piece_bb[1][1]))) * knight_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][2]) + @popCount(board.piece_bb[1][2]))) * bishop_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][3]) + @popCount(board.piece_bb[1][3]))) * rook_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][4]) + @popCount(board.piece_bb[1][4]))) * queen_phase;
    current_phase = std.math.clamp(current_phase, 0, total_phase);

    // ---- Stage 1: evalBase (material + PST) ----
    coeffsBase(board, .White, &mg_c, &eg_c, 1.0);
    coeffsBase(board, .Black, &mg_c, &eg_c, -1.0);

    // ---- Stage 2: evalPieceActivity (mobility, outposts, piece-level threats, safety) ----
    const cache = populateAttackCache(board, move_gen);
    coeffsActivity(board, .White, move_gen, cache, &mg_c, &eg_c, 1.0);
    coeffsActivity(board, .Black, move_gen, cache, &mg_c, &eg_c, -1.0);

    // ---- King safety (mg only) ----
    coeffsKingSafety(board, .White, &mg_c, 1.0);
    coeffsKingSafety(board, .Black, &mg_c, -1.0);

    // ---- Pawn structure ----
    coeffsPawnStructure(board, .White, current_phase, &mg_c, &eg_c, 1.0);
    coeffsPawnStructure(board, .Black, current_phase, &mg_c, &eg_c, -1.0);

    // ---- Bishop pair (both mg and eg) ----
    const wb = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)]);
    const bb_cnt = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)]);
    if (wb >= 2) {
        mg_c[P_BISHOP_PAIR] += 1.0;
        eg_c[P_BISHOP_PAIR] += 1.0;
    }
    if (bb_cnt >= 2) {
        mg_c[P_BISHOP_PAIR] -= 1.0;
        eg_c[P_BISHOP_PAIR] -= 1.0;
    }

    // ---- Endgame terms (eg only, phase < total_phase/2) ----
    if (current_phase < @divTrunc(total_phase, 2)) {
        coeffsEndgame(board, &eg_c);
    }

    // ---- Threats (global — added to both mg and eg equally) ----
    coeffsThreats(board, .White, cache, &mg_c, &eg_c, 1.0);
    coeffsThreats(board, .Black, cache, &mg_c, &eg_c, -1.0);

    // ---- Space (global — added to both mg and eg equally) ----
    coeffsSpace(board, .White, cache, &mg_c, &eg_c, 1.0);
    coeffsSpace(board, .Black, cache, &mg_c, &eg_c, -1.0);

    // ---- evalExchangeAvoidance: output doesn't depend on tunable params ----
    // (uses fixed constant 5 * total_pieces * sign; sign depends on material
    //  but flipping requires large param changes — gradient ≈ 0)

    // ---- Phase-blend: final[i] = (mg[i]*phase + eg[i]*(24-phase)) / 24 ----
    var coeffs: [NUM_PARAMS]f64 = undefined;
    const ph: f64 = @floatFromInt(current_phase);
    const inv_ph: f64 = 24.0 - ph;
    for (0..NUM_PARAMS) |i| {
        coeffs[i] = (mg_c[i] * ph + eg_c[i] * inv_ph) / 24.0;
    }

    // ---- Tempo is outside the phase blend ----
    // evalTuner from white's perspective: +tempo if white-to-move, -tempo if black
    coeffs[P_TEMPO_BONUS] = if (board.toMove() == .White) 1.0 else -1.0;

    return coeffs;
}

// ---------------------------------------------------------------------------
// coeffsBase — mirrors evalBase (material + PST)
// ---------------------------------------------------------------------------
fn coeffsBase(board: *brd.Board, color: brd.Color, mg_c: []f64, eg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);

    const pstSq = struct {
        fn get(sq: usize, c: brd.Color) usize {
            return if (c == .White) sq else mirror_sq[sq];
        }
    }.get;

    // Pawns
    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const psq = pstSq(sq, color);
        mg_c[P_MG_PAWN] += sign;
        eg_c[P_EG_PAWN] += sign;
        mg_c[P_MG_PAWN_TABLE + psq] += sign;
        eg_c[P_EG_PAWN_TABLE + psq] += sign;
        brd.popBit(&bb, sq);
    }

    // Knights
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const psq = pstSq(sq, color);
        mg_c[P_MG_KNIGHT] += sign;
        eg_c[P_EG_KNIGHT] += sign;
        mg_c[P_MG_KNIGHT_TABLE + psq] += sign;
        eg_c[P_EG_KNIGHT_TABLE + psq] += sign;
        brd.popBit(&bb, sq);
    }

    // Bishops
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const psq = pstSq(sq, color);
        mg_c[P_MG_BISHOP] += sign;
        eg_c[P_EG_BISHOP] += sign;
        mg_c[P_MG_BISHOP_TABLE + psq] += sign;
        eg_c[P_EG_BISHOP_TABLE + psq] += sign;
        brd.popBit(&bb, sq);
    }

    // Rooks
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const psq = pstSq(sq, color);
        mg_c[P_MG_ROOK] += sign;
        eg_c[P_EG_ROOK] += sign;
        mg_c[P_MG_ROOK_TABLE + psq] += sign;
        eg_c[P_EG_ROOK_TABLE + psq] += sign;
        brd.popBit(&bb, sq);
    }

    // Queens
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Queen)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const psq = pstSq(sq, color);
        mg_c[P_MG_QUEEN] += sign;
        eg_c[P_EG_QUEEN] += sign;
        mg_c[P_MG_QUEEN_TABLE + psq] += sign;
        eg_c[P_EG_QUEEN_TABLE + psq] += sign;
        brd.popBit(&bb, sq);
    }

    // King
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (bb != 0) {
        const sq = brd.getLSB(bb);
        const psq = pstSq(sq, color);
        mg_c[P_MG_KING_TABLE + psq] += sign;
        eg_c[P_EG_KING_TABLE + psq] += sign;
        // mg_king and eg_king are always 0 but included for completeness
        mg_c[P_MG_KING] += sign;
        eg_c[P_EG_KING] += sign;
    }
}

// ---------------------------------------------------------------------------
// coeffsActivity — mirrors evalPieceActivity
// The `score` variable in evalPieceActivity goes into BOTH .mg and .eg.
// The safety_bonus goes into .mg ONLY.
// ---------------------------------------------------------------------------
fn coeffsActivity(
    board: *brd.Board,
    color: brd.Color,
    move_gen: *mvs.MoveGen,
    cache: AttackCache,
    mg_c: []f64,
    eg_c: []f64,
    sign: f64,
) void {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;

    var attack_units: i32 = 0;
    var attacker_count: i32 = 0;

    // Track per-piece-type attack counts for safety table gradient
    var n_knights_atk: i32 = 0;
    var n_bishops_atk: i32 = 0;
    var n_rooks_atk: i32 = 0;
    var n_queens_atk: i32 = 0;

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];

    var our_pawn_attacks: u64 = undefined;
    var opp_pawn_attacks: u64 = undefined;
    if (color == .White) {
        our_pawn_attacks = cache.our_pawn_attacks;
        opp_pawn_attacks = cache.opp_pawn_attacks;
    } else {
        our_pawn_attacks = cache.opp_pawn_attacks;
        opp_pawn_attacks = cache.our_pawn_attacks;
    }

    const opp_king_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.King)];
    const opp_queen_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Queen)];
    const occupancy = cache.occupancy;
    const opp_king_sq = brd.getLSB(opp_king_bb);
    const opp_king_zone = getKingZone(opp_king_sq, color.opposite(), move_gen);

    // ---- Knights ----
    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);

        // Outpost
        const rank = @divTrunc(sq, 8);
        const relative_rank = if (color == .White) rank else 7 - rank;
        const is_supported = (our_pawn_attacks & (@as(u64, 1) << @intCast(sq))) != 0;
        if (is_supported and relative_rank >= 3 and relative_rank <= 5) {
            mg_c[P_KNIGHT_OUTPOST] += sign;
            eg_c[P_KNIGHT_OUTPOST] += sign;
        }

        // Minor threatened by pawn
        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_c[P_MINOR_THREAT] -= sign; // penalty is subtracted in eval
            eg_c[P_MINOR_THREAT] -= sign;
        }

        // Mobility
        coeffsMobility(sq, .Knight, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        // King zone attack
        const attack_mask = move_gen.knights[@as(usize, @intCast(sq))];
        if (attack_mask & opp_king_zone != 0) {
            attack_units += knight_attack_bonus;
            attacker_count += 1;
            n_knights_atk += 1;
        }

        brd.popBit(&bb, sq);
    }

    // ---- Bishops ----
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);

        // Minor threatened by pawn
        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_c[P_MINOR_THREAT] -= sign;
            eg_c[P_MINOR_THREAT] -= sign;
        }

        // Bad bishop
        const bishop_mask: u64 = move_gen.getBishopAttacks(sq, occupancy);
        const blocking_pawns: i32 = @as(i32, @intCast(@popCount(our_pawns & bishop_mask)));
        if (blocking_pawns > 1) {
            const count_f: f64 = @floatFromInt(blocking_pawns - 1);
            mg_c[P_BAD_BISHOP] -= sign * count_f;
            eg_c[P_BAD_BISHOP] -= sign * count_f;
        }

        // Mobility
        coeffsMobility(sq, .Bishop, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        // King zone attack
        const attack_mask = move_gen.getBishopAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            attack_units += bishop_attack_bonus;
            attacker_count += 1;
            n_bishops_atk += 1;
        }

        brd.popBit(&bb, sq);
    }

    // ---- Rooks ----
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const file = @mod(sq, 8);
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        const our_pawns_on_file = (our_pawns & file_mask) != 0;
        const opp_pawns_on_file = (opp_pawns & file_mask) != 0;

        if (!our_pawns_on_file) {
            if (!opp_pawns_on_file) {
                mg_c[P_ROOK_OPEN_FILE] += sign;
                eg_c[P_ROOK_OPEN_FILE] += sign;
            } else {
                mg_c[P_ROOK_SEMI_OPEN] += sign;
                eg_c[P_ROOK_SEMI_OPEN] += sign;
            }
        }

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_c[P_ROOK_THREAT] -= sign;
            eg_c[P_ROOK_THREAT] -= sign;
        }

        if (file_mask & opp_queen_bb != 0) {
            mg_c[P_ROOK_ON_QUEEN] += sign;
            eg_c[P_ROOK_ON_QUEEN] += sign;
        }
        if (file_mask & opp_king_bb != 0) {
            mg_c[P_ROOK_ON_KING] += sign;
            eg_c[P_ROOK_ON_KING] += sign;
        }

        coeffsMobility(sq, .Rook, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        const attack_mask = move_gen.getRookAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            attack_units += rook_attack_bonus;
            attacker_count += 1;
            n_rooks_atk += 1;
        }

        brd.popBit(&bb, sq);
    }

    // ---- Queens ----
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Queen)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);

        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_c[P_QUEEN_THREAT] -= sign;
            eg_c[P_QUEEN_THREAT] -= sign;
        }

        const file = @mod(sq, 8);
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        if (file_mask & opp_king_bb != 0) {
            mg_c[P_QUEEN_ON_KING] += sign;
            eg_c[P_QUEEN_ON_KING] += sign;
        }

        coeffsMobility(sq, .Queen, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        const attack_mask = move_gen.getQueenAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            attack_units += queen_attack_bonus;
            attacker_count += 1;
            n_queens_atk += 1;
        }

        brd.popBit(&bb, sq);
    }

    // ---- Safety table (mg only) ----
    if (attacker_count > 1) {
        const idx = @as(usize, @intCast(@min(attack_units, 15)));
        // The selected safety_table entry has coefficient 1 (mg only)
        mg_c[P_SAFETY_TABLE + idx] += sign;

        // Gradient of attack bonus params through the safety table.
        // d(safety_table[idx])/d(bonus) ≈ count * discrete_derivative
        const idx_i: i32 = @intCast(idx);
        const deriv: f64 = blk: {
            if (idx == 0) break :blk @as(f64, @floatFromInt(safety_table[1] - safety_table[0]));
            if (idx == 15) break :blk @as(f64, @floatFromInt(safety_table[15] - safety_table[14]));
            break :blk @as(f64, @floatFromInt(safety_table[@as(usize, @intCast(idx_i + 1))] - safety_table[@as(usize, @intCast(idx_i - 1))])) / 2.0;
        };
        mg_c[P_KNIGHT_ATTACK_BONUS] += sign * @as(f64, @floatFromInt(n_knights_atk)) * deriv;
        mg_c[P_BISHOP_ATTACK_BONUS] += sign * @as(f64, @floatFromInt(n_bishops_atk)) * deriv;
        mg_c[P_ROOK_ATTACK_BONUS] += sign * @as(f64, @floatFromInt(n_rooks_atk)) * deriv;
        mg_c[P_QUEEN_ATTACK_BONUS] += sign * @as(f64, @floatFromInt(n_queens_atk)) * deriv;
    }
}

// ---------------------------------------------------------------------------
// coeffsMobility — mirrors evalMobility
// Mobility bonus goes into BOTH mg and eg (it is part of `score` in
// evalPieceActivity which feeds both .mg and .eg).
// ---------------------------------------------------------------------------
fn coeffsMobility(
    sq: usize,
    piece: brd.Pieces,
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    opp_pawn_attacks: u64,
    color: brd.Color,
    mg_c: []f64,
    eg_c: []f64,
    sign: f64,
) void {
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

    // The mobility table entry at `count` has coefficient +sign
    switch (piece) {
        .Knight => {
            const idx = if (count < knight_mobility_bonus.len) count else knight_mobility_bonus.len - 1;
            mg_c[P_KNIGHT_MOB + idx] += sign;
            eg_c[P_KNIGHT_MOB + idx] += sign;
        },
        .Bishop => {
            const idx = if (count < bishop_mobility_bonus.len) count else bishop_mobility_bonus.len - 1;
            mg_c[P_BISHOP_MOB + idx] += sign;
            eg_c[P_BISHOP_MOB + idx] += sign;
        },
        .Rook => {
            const idx = if (count < rook_mobility_bonus.len) count else rook_mobility_bonus.len - 1;
            mg_c[P_ROOK_MOB + idx] += sign;
            eg_c[P_ROOK_MOB + idx] += sign;
        },
        .Queen => {
            const idx = if (count < queen_mobility_bonus.len) count else queen_mobility_bonus.len - 1;
            mg_c[P_QUEEN_MOB + idx] += sign;
            eg_c[P_QUEEN_MOB + idx] += sign;
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// coeffsKingSafety — mirrors evalKingSafety (mg only)
// ---------------------------------------------------------------------------
fn coeffsKingSafety(board: *brd.Board, color: brd.Color, mg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return;

    const king_sq = brd.getLSB(king_bb);
    const king_file = @mod(king_sq, 8);
    const king_rank = @divTrunc(king_sq, 8);

    const has_castled = blk: {
        if (color == .White) break :blk (king_sq == 6 or king_sq == 2);
        break :blk (king_sq == 62 or king_sq == 58);
    };
    if (has_castled) {
        mg_c[P_CASTLED_BONUS] += sign;
    }

    // Pawn shield
    const pawn_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const shield_files = [3]i32{
        @as(i32, @intCast(king_file)) - 1,
        @as(i32, @intCast(king_file)),
        @as(i32, @intCast(king_file)) + 1,
    };

    for (shield_files) |file| {
        if (file < 0 or file > 7) continue;
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        const pawns_on_file = pawn_bb & file_mask;

        var temp_bb = pawns_on_file;
        while (temp_bb != 0) {
            const pawn_sq = brd.getLSB(temp_bb);
            const pawn_rank = @divTrunc(pawn_sq, 8);
            const is_shield = if (color == .White)
                pawn_rank > king_rank and pawn_rank <= king_rank + 2
            else
                pawn_rank < king_rank and pawn_rank >= king_rank - 2;
            if (is_shield) {
                mg_c[P_PAWN_SHIELD_BONUS] += sign;
            }
            brd.popBit(&temp_bb, pawn_sq);
        }
    }

    // Open / semi-open file penalties
    const all_pawns = board.piece_bb[0][@intFromEnum(brd.Pieces.Pawn)] |
        board.piece_bb[1][@intFromEnum(brd.Pieces.Pawn)];
    for (shield_files) |file| {
        if (file < 0 or file > 7) continue;
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        const our_pawns_on_file = pawn_bb & file_mask;
        const their_pawns_on_file = (all_pawns & file_mask) ^ our_pawns_on_file;

        if (our_pawns_on_file == 0 and their_pawns_on_file == 0) {
            mg_c[P_OPEN_FILE_PENALTY] += sign;
        } else if (our_pawns_on_file == 0 and their_pawns_on_file != 0) {
            mg_c[P_SEMI_OPEN_PENALTY] += sign;
        }
    }
}

// ---------------------------------------------------------------------------
// coeffsPawnStructure — mirrors evalPawnsForColor
// Passed pawn bonuses, protected/isolated/doubled
// ---------------------------------------------------------------------------
fn coeffsPawnStructure(
    board: *brd.Board,
    color: brd.Color,
    phase: i32,
    mg_c: []f64,
    eg_c: []f64,
    sign: f64,
) void {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];

    // File counts for doubled pawn detection
    var file_counts = [_]u8{0} ** 8;
    var tmp = our_pawns;
    while (tmp != 0) {
        const sq = brd.getLSB(tmp);
        file_counts[@mod(sq, 8)] += 1;
        brd.popBit(&tmp, sq);
    }

    var temp_bb = our_pawns;
    while (temp_bb != 0) {
        const sq = brd.getLSB(temp_bb);
        const file = @mod(sq, 8);
        const rank = @divTrunc(sq, 8);
        const relative_rank: usize = if (color == .White) rank else 7 - rank;

        const left_mask: u64 = if (file > 0) @as(u64, 0x0101010101010101) << @intCast(file - 1) else 0;
        const right_mask: u64 = if (file < 7) @as(u64, 0x0101010101010101) << @intCast(file + 1) else 0;
        const adjacent_files = left_mask | right_mask;

        // ---- Passed pawn ----
        const is_passed = blk: {
            const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
            const forward_mask = file_mask | left_mask | right_mask;
            const blocking = if (color == .White) blk2: {
                const rank_mask: u64 = @as(u64, 0xFFFFFFFFFFFFFFFF) << @intCast((rank + 1) * 8);
                break :blk2 opp_pawns & forward_mask & rank_mask;
            } else blk2: {
                const rank_mask: u64 = if (rank > 0) (@as(u64, 0xFFFFFFFFFFFFFFFF) >> @intCast((8 - rank) * 8)) else 0;
                break :blk2 opp_pawns & forward_mask & rank_mask;
            };
            break :blk blocking == 0;
        };
        if (is_passed) {
            mg_c[P_MG_PASSED + relative_rank] += sign;

            // EG passed pawn bonus, potentially scaled by 3/2 if phase < 12
            const eg_scale: f64 = if (phase < 12) 1.5 else 1.0;
            eg_c[P_EG_PASSED + relative_rank] += sign * eg_scale;
            // advancement_bonus does not depend on tunable params
        }

        // ---- Protected pawn (both mg and eg) ----
        const is_protected = blk: {
            const protection_sqs = if (color == .White) blk2: {
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
            var prot = false;
            for (protection_sqs) |maybe_sq| {
                if (maybe_sq) |prot_sq| {
                    const mask: u64 = @as(u64, 1) << @intCast(prot_sq);
                    if ((our_pawns & mask) != 0) { prot = true; break; }
                }
            }
            break :blk prot;
        };
        if (is_protected) {
            mg_c[P_PROTECTED_PAWN] += sign;
            eg_c[P_PROTECTED_PAWN] += sign;
        }

        // ---- Isolated pawn (both) ----
        if ((our_pawns & adjacent_files) == 0) {
            mg_c[P_ISOLATED_PAWN] += sign;
            eg_c[P_ISOLATED_PAWN] += sign;
        }

        // ---- Doubled pawn (both) ----
        if (file_counts[file] > 1) {
            mg_c[P_DOUBLED_PAWN] += sign;
            eg_c[P_DOUBLED_PAWN] += sign;
        }

        brd.popBit(&temp_bb, sq);
    }
}

// ---------------------------------------------------------------------------
// coeffsEndgame — mirrors evalEndgame (eg only, called when phase < 12)
// Only the rook and king-pawn-proximity terms depend on tunable params.
// Mop-up and king centralization use fixed constants.
// ---------------------------------------------------------------------------
fn coeffsEndgame(board: *brd.Board, eg_c: []f64) void {
    // evalRookEndgame for white (+1) and black (-1)
    coeffsRookEndgame(board, .White, eg_c, 1.0);
    coeffsRookEndgame(board, .Black, eg_c, -1.0);

    // evalKingActivity king_pawn_proximity for white (+1) and black (-1)
    coeffsKingActivity(board, .White, eg_c, 1.0);
    coeffsKingActivity(board, .Black, eg_c, -1.0);
}

fn coeffsRookEndgame(board: *brd.Board, color: brd.Color, eg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);
    const rook_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];

    var temp_rook_bb = rook_bb;
    while (temp_rook_bb != 0) {
        const rook_sq = brd.getLSB(temp_rook_bb);
        const rook_rank = @divTrunc(rook_sq, 8);
        const rook_file = @mod(rook_sq, 8);

        const seventh_rank: i32 = if (color == .White) 6 else 1;
        if (rook_rank == seventh_rank) {
            eg_c[P_ROOK_7TH_BONUS] += sign;
        }

        // Rook behind passed pawn
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(rook_file);
        var pawn_bb = our_pawns & file_mask;
        while (pawn_bb != 0) {
            const pawn_sq = brd.getLSB(pawn_bb);
            const pawn_rank = @divTrunc(pawn_sq, 8);
            const rook_behind = if (color == .White) rook_rank < pawn_rank else rook_rank > pawn_rank;
            if (rook_behind and checkPassedPawn(board, pawn_sq, color)) {
                eg_c[P_ROOK_PASSER_BONUS] += sign;
            }
            brd.popBit(&pawn_bb, pawn_sq);
        }

        brd.popBit(&temp_rook_bb, rook_sq);
    }
}

fn coeffsKingActivity(board: *brd.Board, color: brd.Color, eg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return;
    const king_sq = brd.getLSB(king_bb);

    // King centralization uses fixed constant (2), not tunable — skip.

    // King proximity to our passed pawns — uses king_pawn_proximity
    var pawn_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    while (pawn_bb != 0) {
        const pawn_sq = brd.getLSB(pawn_bb);
        if (checkPassedPawn(board, pawn_sq, color)) {
            const dist = manhattanDistance(king_sq, pawn_sq);
            if (dist <= 3) {
                eg_c[P_KING_PAWN_PROXIMITY] += sign * @as(f64, @floatFromInt(6 - dist));
            }
        }
        brd.popBit(&pawn_bb, pawn_sq);
    }
    // Penalty for being far from opponent's passed pawns uses fixed constant 3 — skip.
}

// ---------------------------------------------------------------------------
// coeffsThreats — mirrors evalThreats (global → both mg and eg)
// ---------------------------------------------------------------------------
fn coeffsThreats(
    board: *brd.Board,
    color: brd.Color,
    cache: AttackCache,
    mg_c: []f64,
    eg_c: []f64,
    sign: f64,
) void {
    const c_idx = @intFromEnum(color);

    var opp_pawn_attacks: u64 = undefined;
    var opp_knight_attacks: u64 = undefined;
    var opp_bishop_attacks: u64 = undefined;
    var opp_rook_attacks: u64 = undefined;
    var our_defenses: u64 = undefined;

    if (color == .White) {
        opp_pawn_attacks = cache.opp_pawn_attacks;
        opp_knight_attacks = cache.opp_knight_attacks;
        opp_bishop_attacks = cache.opp_bishop_attacks;
        opp_rook_attacks = cache.opp_rook_attacks;
        our_defenses = cache.our_defenses;
    } else {
        opp_pawn_attacks = cache.our_pawn_attacks;
        opp_knight_attacks = cache.our_knight_attacks;
        opp_bishop_attacks = cache.our_bishop_attacks;
        opp_rook_attacks = cache.our_rook_attacks;
        our_defenses = cache.opp_defenses;
    }

    const pieces = [_]brd.Pieces{ .Knight, .Bishop, .Rook, .Queen };
    for (pieces) |piece| {
        var piece_bb = board.piece_bb[c_idx][@intFromEnum(piece)];
        while (piece_bb != 0) {
            const sq = brd.getLSB(piece_bb);
            const sq_mask = @as(u64, 1) << @intCast(sq);
            const is_defended = (our_defenses & sq_mask) != 0;

            // Attacked by pawn
            if ((opp_pawn_attacks & sq_mask) != 0) {
                if (!is_defended) {
                    // score -= hanging_piece_penalty + attacked_by_pawn_penalty
                    mg_c[P_HANGING_PIECE] -= sign;
                    eg_c[P_HANGING_PIECE] -= sign;
                    mg_c[P_ATK_BY_PAWN] -= sign;
                    eg_c[P_ATK_BY_PAWN] -= sign;
                } else {
                    // score -= @divTrunc(attacked_by_pawn_penalty, 2)
                    mg_c[P_ATK_BY_PAWN] -= sign * 0.5;
                    eg_c[P_ATK_BY_PAWN] -= sign * 0.5;
                }
            }

            // Attacked by minor (only rooks/queens)
            if (((opp_knight_attacks | opp_bishop_attacks) & sq_mask) != 0) {
                if (!is_defended and (piece == .Rook or piece == .Queen)) {
                    mg_c[P_ATK_BY_MINOR] -= sign;
                    eg_c[P_ATK_BY_MINOR] -= sign;
                }
            }

            // Attacked by rook (only queens)
            if ((opp_rook_attacks & sq_mask) != 0 and piece == .Queen) {
                if (!is_defended) {
                    mg_c[P_ATK_BY_ROOK] -= sign;
                    eg_c[P_ATK_BY_ROOK] -= sign;
                }
            }

            brd.popBit(&piece_bb, sq);
        }
    }
}

// ---------------------------------------------------------------------------
// coeffsSpace — mirrors evalSpace (global → both mg and eg)
// Only the tunable parts: space_per_square, center_control_bonus,
// extended_center_bonus.  The pawn advance bonus uses a fixed constant.
// ---------------------------------------------------------------------------
fn coeffsSpace(
    _: *brd.Board,
    color: brd.Color,
    cache: AttackCache,
    mg_c: []f64,
    eg_c: []f64,
    sign: f64,
) void {
    const our_half: u64 = if (color == .White) 0x00000000FFFFFFFF else 0xFFFFFFFF00000000;
    const center: u64 = 0x0000001818000000;
    const extended_center: u64 = 0x00003C3C3C3C0000;

    var our_attacks: u64 = undefined;
    if (color == .White) {
        our_attacks = cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks | cache.our_defenses;
    } else {
        our_attacks = cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks | cache.opp_defenses;
    }

    const controlled: f64 = @floatFromInt(@popCount(our_attacks & our_half));
    mg_c[P_SPACE_PER_SQ] += sign * controlled;
    eg_c[P_SPACE_PER_SQ] += sign * controlled;

    const center_ctrl: f64 = @floatFromInt(@popCount(our_attacks & center));
    mg_c[P_CENTER_CTRL] += sign * center_ctrl;
    eg_c[P_CENTER_CTRL] += sign * center_ctrl;

    const ext_ctrl: f64 = @floatFromInt(@popCount(our_attacks & extended_center));
    mg_c[P_EXTENDED_CENTER] += sign * ext_ctrl;
    eg_c[P_EXTENDED_CENTER] += sign * ext_ctrl;
}
