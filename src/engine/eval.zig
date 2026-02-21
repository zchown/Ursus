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

pub var mg_pawn: i32 = 77;
pub var eg_pawn: i32 = 111;
pub var mg_knight: i32 = 299;
pub var eg_knight: i32 = 426;
pub var mg_bishop: i32 = 309;
pub var eg_bishop: i32 = 453;
pub var mg_rook: i32 = 409;
pub var eg_rook: i32 = 765;
pub var mg_queen: i32 = 905;
pub var eg_queen: i32 = 1463;
pub var mg_king: i32 = 0;
pub var eg_king: i32 = 0;

pub var mg_pawn_table = [64]i32{
       0,   0,   0,   0,   0,   0,   0,   0,
      -14,  -13,  -14,   -7,   -8,  19,  28,  -10,
      -16,  -19,  -11,   -8,   3,   -1,   5,  -14,
      -14,  -11,   0,   3,  12,  10,   6,  -14,
      -11,   4,   0,  12,  29,  39,  24,   1,
       -8,  20,  36,  28,  38, 105,  64,   9,
     120, 125,  97, 120, 101,  61,  -59,  -52,
       0,   0,   0,   0,   0,   0,   0,   0,
};
pub var eg_pawn_table = [64]i32{
       0,   0,   0,   0,   0,   0,   0,   0,
      26,  24,  21,  15,  28,  22,   7,   -1,
      20,  14,   7,   4,   9,  12,   2,   1,
      27,  24,   1,   -5,   -5,   2,   6,   5,
      47,  32,  19,  -11,   -5,   -1,  18,  18,
      73,  69,  39,   7,   4,  14,  38,  49,
     166, 159, 157, 112, 110, 124, 178, 180,
       0,   0,   0,   0,   0,   0,   0,   0,
};
pub var mg_knight_table = [64]i32{
      -88,  -22,  -42,  -16,   -7,   -4,  -20,  -58,
      -38,  -32,  -10,   7,   4,   5,   -6,   -5,
      -28,   -3,   1,  18,  23,  11,   8,   -4,
       -8,   -2,  10,  17,  26,  13,  32,  10,
       7,  10,  27,  46,   8,  39,   4,  35,
      -18,  10,  42,  41,  80,  83,  40,  22,
       -8,  -11,  25,  44,  33,  69,  -14,  27,
     -190, -148, -104,  -33,  18, -123,  -94, -147,
};
pub var eg_knight_table = [64]i32{
      -44,  -53,  -17,   -8,  -10,  -18,  -33,  -49,
      -22,   0,   -7,   -1,   6,  -10,  -11,  -16,
      -30,   3,  12,  31,  25,   5,   3,  -16,
       1,  13,  36,  38,  42,  34,  18,   2,
       -2,  15,  34,  43,  47,  36,  33,   6,
       -8,   8,  25,  26,  10,  19,   3,  -11,
      -20,   -3,   -4,  12,   7,  -21,   0,  -32,
      -66,   2,  21,   1,   0,  30,   1,  -91,
};
pub var mg_bishop_table = [64]i32{
       9,  15,   -8,  -18,  -15,   -3,   -1,   5,
       6,   9,  18,   -1,   6,  11,  26,  11,
      -10,  11,   9,  10,   8,  11,   9,  14,
       -5,   -6,   3,  23,  24,   -4,   3,   6,
       -8,  12,   9,  41,  21,  24,   9,   -6,
       0,  10,  32,  19,  31,  48,  37,   4,
      -29,   -3,  -11,  -26,  -15,   0,  -36,  -28,
      -58,  -56, -105, -110, -102, -134,  -18,  -58,
};
pub var eg_bishop_table = [64]i32{
      -22,   -4,   -8,   2,   3,   5,   -9,  -30,
       -3,  -14,   -3,  11,   9,   -1,   -6,  -32,
       5,  16,  21,  25,  32,  18,   7,   2,
       9,  20,  33,  31,  29,  32,  21,   4,
      21,  27,  26,  30,  34,  26,  32,  25,
      21,  25,  24,  20,  21,  30,  21,  22,
       8,  21,  23,  24,  21,  19,  27,   9,
      23,  24,  32,  40,  33,  33,  10,  13,
};
pub var mg_rook_table = [64]i32{
      -21,  -16,  -10,   1,   3,   1,   8,  -14,
      -53,  -34,  -21,  -16,  -13,   -3,   8,  -34,
      -40,  -30,  -33,  -25,  -21,  -23,   8,  -15,
      -32,  -32,  -29,  -18,  -18,  -24,   3,  -16,
      -17,   -2,   6,  27,  18,  26,  31,  20,
       -9,  28,  16,  36,  59,  76, 100,  41,
       2,   -7,  18,  33,  26,  63,  42,  66,
      31,  31,   -1,  16,  14,  47,  66,  73,
};
pub var eg_rook_table = [64]i32{
      12,   9,   8,   0,   -6,   5,   -3,   1,
       6,   5,   4,   -5,   -5,  -10,  -12,   -3,
       7,  17,  11,   4,   4,   0,   -4,   -7,
      26,  37,  30,  20,  19,  23,  18,  16,
      34,  31,  29,  21,  15,  16,  13,  24,
      38,  24,  31,  15,   7,  14,   0,  19,
      42,  50,  41,  35,  37,  18,  29,  23,
      46,  49,  55,  44,  49,  48,  47,  48,
};
pub var mg_queen_table = [64]i32{
       -2,   1,   6,  11,  15,   -5,   -5,   -8,
       -1,   0,   8,  11,  10,  26,  23,  18,
       -8,   -2,   0,   -7,   1,   1,   7,  10,
       -5,  -10,  -19,  -15,  -17,   -4,   -2,  11,
      -12,  -16,  -27,  -31,  -23,   -8,   6,   5,
      -18,  -16,  -21,  -21,   -4,  47,  56,  18,
      -29,  -61,  -36,  -59,  -54,  18,  -26,  47,
      -39,  -30,  -26,  -12,   -6,  23,  48,  28,
};
pub var eg_queen_table = [64]i32{
      -28,  -44,  -39,  -20,  -43,  -43,  -59,  -28,
      -24,  -19,  -28,  -15,  -16,  -65,  -80,  -63,
       -8,  11,  22,  19,  20,  24,   9,  -11,
      11,  43,  45,  71,  70,  64,  54,  54,
      21,  59,  63,  92, 109, 118, 110,  92,
      34,  40,  72,  95, 114, 108,  84,  96,
      52,  87,  95, 137, 165, 112, 121,  75,
      61,  82,  96, 100, 109, 105,  77,  78,
};
pub var mg_king_table = [64]i32{
       -7,  27,   4,  -71,  -24,  -69,   9,  15,
      12,   -5,  -16,  -47,  -36,  -39,  13,  15,
      -45,   9,   -2,   -8,   3,   -9,   5,  -39,
      -50,  20,  31,  -21,   5,  18,  27,  -89,
      -40,  37,  24,  -28,   -9,  29,  31,  -69,
      -58,  91,  75,   3,  39,  90,  62,  -59,
      -88,  42,  40, 107,  40,  46,  34,  -74,
     119, 161, 141,  58,  25,  64, 125, 169,
};
pub var eg_king_table = [64]i32{
      -42,  -21,   -6,   -6,  -31,   8,  -22,  -69,
       2,   9,  13,   9,   9,  16,   -1,  -17,
       -4,   3,   9,  10,   5,   8,   -3,   -2,
      -19,   0,   6,   8,   1,   4,   -2,   1,
       1,  11,  19,  10,   8,  16,  21,   8,
      24,  31,  21,  22,  17,  36,  47,  29,
      15,  39,  29,   -5,  13,  34,  61,  29,
     -135,  -59,  -38,   -9,  -22,  -10,   2, -126,
};

pub var knight_mobility_bonus = [9]i32{ -16, 0, 9, 15, 19, 25, 29, 31, 21, };
pub var bishop_mobility_bonus = [14]i32{ -17, -11, -2, 5, 12, 18, 21, 23, 27, 27, 25, 23, 28, 11, };
pub var rook_mobility_bonus = [15]i32{ -7, 4, 9, 11, 13, 18, 21, 25, 28, 31, 34, 35, 35, 28, 20, };
pub var queen_mobility_bonus = [28]i32{ -13, -4, -2, 0, 3, 5, 9, 13, 18, 19, 24, 26, 28, 29, 32, 32, 34, 34, 35, 37, 38, 37, 37, 31, 37, 37, 38, 28, };
pub var mg_passed_bonus = [8]i32{ 0, 4, 0, 4, 34, 57, 62, 0, };
pub var passed_pawn_bonus = [8]i32{ 0, -22, -15, 6, 26, 86, 53, 0, };
pub var safety_table = [16]i32{ 39, 14, 17, 21, 21, 20, 14, 42, 18, 66, 18, 156, 35, 233, 10, 227, };
pub var castled_bonus: i32 = 1;
pub var pawn_shield_bonus: i32 = 11;
pub var open_file_penalty: i32 = -45;
pub var semi_open_penalty: i32 = -13;
pub var knight_attack_bonus: i32 = 0;
pub var bishop_attack_bonus: i32 = 0;
pub var rook_attack_bonus: i32 = -4757;
pub var queen_attack_bonus: i32 = -5492;
pub var rook_on_7th_bonus: i32 = 2;
pub var rook_behind_passer_bonus: i32 = 7;
pub var king_pawn_proximity: i32 = 6;
pub var protected_pawn_bonus: i32 = 10;
pub var doubled_pawn_penalty: i32 = -7;
pub var isolated_pawn_penalty: i32 = -11;
pub var rook_on_open_file_bonus: i32 = 25;
pub var rook_on_semi_open_file_bonus: i32 = 15;
pub var minor_threat_penalty: i32 = 32;
pub var rook_threat_penalty: i32 = 11;
pub var queen_threat_penalty: i32 = 14;
pub var rook_on_queen_bonus: i32 = 7;
pub var rook_on_king_bonus: i32 = 0;
pub var queen_on_king_bonus: i32 = 4;
pub var bad_bishop_penalty: i32 = 5;
pub var bishop_on_queen_bonus: i32 = 26;
pub var bishop_on_king_bonus: i32 = -5;
pub var hanging_piece_penalty: i32 = -22;
pub var attacked_by_pawn_penalty: i32 = 13;
pub var attacked_by_minor_penalty: i32 = 29;
pub var attacked_by_rook_penalty: i32 = 35;
pub var tempo_bonus: i32 = 16;
pub var bishop_pair_bonus: i32 = 43;
pub var knight_outpost_bonus: i32 = 10;
pub var space_per_square: i32 = 0;
pub var center_control_bonus: i32 = 1;
pub var extended_center_bonus: i32 = 2;
pub var exchange_avoidance_weight: i32 = 2;
pub var mopup_edge_weight: i32 = 10;
pub var mopup_proximity_weight: i32 = -8;
pub var king_centralization_weight: i32 = 10;
pub var king_far_pawn_penalty: i32 = 36;
pub var defended_by_pawn_penalty: i32 = 1;
pub var pawn_advancement_scaler: i32 = -8;
pub var pawn_storm_penalty: i32 = -9;
pub var king_zone_attack_weight: i32 = 10;
pub var king_defender_bonus: i32 = 0;
pub var rule_of_square_bonus: i32 = 149;
pub var trapped_piece_penalty: i32 = 0;

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

    // STAGE 1
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

    // STAGE 2
    const attack_cache = populateAttackCache(board, move_gen);

    const white_activity = evalPieceActivity(board, brd.Color.White, move_gen, attack_cache);
    const black_activity = evalPieceActivity(board, brd.Color.Black, move_gen, attack_cache);

    mg_score += white_activity.mg - black_activity.mg;
    eg_score += white_activity.eg - black_activity.eg;

    mg_score += evalKingSafety(board, brd.Color.White);
    mg_score -= evalKingSafety(board, brd.Color.Black);

    // Pawn storm (mg-only king safety feature)
    mg_score += evalPawnStorm(board, brd.Color.White);
    mg_score -= evalPawnStorm(board, brd.Color.Black);

    // King zone control and defenders (mg-weighted features)
    mg_score += evalKingZoneControl(board, brd.Color.White, move_gen, attack_cache);
    mg_score -= evalKingZoneControl(board, brd.Color.Black, move_gen, attack_cache);
    mg_score += evalKingDefenders(board, brd.Color.White, move_gen, attack_cache);
    mg_score -= evalKingDefenders(board, brd.Color.Black, move_gen, attack_cache);

    if (!got_pawns) {
        const pawn_eval = evalPawnStructure(board, current_phase);
        mg_score += pawn_eval.mg;
        eg_score += pawn_eval.eg;
    }

    if (current_phase < total_phase / 2) {
        const eg_eval = evalEndgame(board, current_phase);
        eg_score += eg_eval;

        // Rule of the Square (endgame only - when few pieces)
        eg_score += evalRuleOfSquare(board, brd.Color.White);
        eg_score -= evalRuleOfSquare(board, brd.Color.Black);
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

    // Trapped pieces (applies all game)
    global_score += evalTrappedPieces(board, brd.Color.White, move_gen, attack_cache);
    global_score -= evalTrappedPieces(board, brd.Color.Black, move_gen, attack_cache);

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

        if (bishop_mask & opp_queen_bb != 0) {
            score += bishop_on_queen_bonus;
        }
        if (bishop_mask & opp_king_bb != 0) {
            score += bishop_on_king_bonus;
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
        const index = @as(usize, @intCast(std.math.clamp(attack_units, 0, 15)));
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
                @divTrunc((total_phase - phase) * @as(i32, @intCast(relative_rank)) * pawn_advancement_scaler, total_phase)
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
            const edge_score = centerDistance(loser_king_sq) * mopup_edge_weight;
            // Bring winning king closer to losing king
            const king_proximity = (14 - manhattanDistance(winner_king_sq, loser_king_sq)) * mopup_proximity_weight;
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
    score += centralization * king_centralization_weight;

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
                score -= king_far_pawn_penalty;
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
                    score -= defended_by_pawn_penalty;
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
    return sign * total_pieces * exchange_avoidance_weight;
}

// Pawn Storm: penalize opponent pawns advancing toward our castled king
fn evalPawnStorm(board: *brd.Board, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return 0;

    const king_sq = brd.getLSB(king_bb);
    const king_file: i32 = @intCast(@mod(king_sq, 8));
    const king_rank: i32 = @intCast(@divTrunc(king_sq, 8));

    // Only relevant when king is on flanks (castled position)
    if (king_file > 2 and king_file < 5) return 0;

    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];
    var penalty: i32 = 0;

    const files = [3]i32{ king_file - 1, king_file, king_file + 1 };
    for (files) |file| {
        if (file < 0 or file > 7) continue;
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        var pawns = opp_pawns & file_mask;
        while (pawns != 0) {
            const sq = brd.getLSB(pawns);
            const pawn_rank: i32 = @intCast(@divTrunc(sq, 8));
            // How close is the pawn to our king's rank?
            const advance = if (color == brd.Color.White)
                7 - pawn_rank // For white king, black pawns advance by decreasing rank
            else
                pawn_rank; // For black king, white pawns advance by increasing rank
            // More advanced pawns = more dangerous
            if (advance >= 4) {
                penalty += (advance - 3) * pawn_storm_penalty;
            }
            brd.popBit(&pawns, sq);
        }
    }
    _ = king_rank;
    return -penalty;
}

// King Zone Control: penalize based on how many squares around king the opponent controls
fn evalKingZoneControl(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen, cache: AttackCache) i32 {
    const c_idx = @intFromEnum(color);
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return 0;

    const king_sq = brd.getLSB(king_bb);
    const king_zone = getKingZone(king_sq, color, move_gen);

    var opp_attacks: u64 = 0;
    if (color == .White) {
        opp_attacks = cache.opp_pawn_attacks | cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks;
    } else {
        opp_attacks = cache.our_pawn_attacks | cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks;
    }

    const attacked_zone_squares = @popCount(opp_attacks & king_zone);
    return -@as(i32, @intCast(attacked_zone_squares)) * king_zone_attack_weight;
}

// King Defenders: bonus for friendly pieces defending the king zone
fn evalKingDefenders(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen, cache: AttackCache) i32 {
    const c_idx = @intFromEnum(color);
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return 0;

    const king_sq = brd.getLSB(king_bb);
    const king_zone = getKingZone(king_sq, color, move_gen);

    var our_attacks: u64 = 0;
    if (color == .White) {
        our_attacks = cache.our_pawn_attacks | cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks;
    } else {
        our_attacks = cache.opp_pawn_attacks | cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks;
    }

    const defended_zone_squares = @popCount(our_attacks & king_zone);
    return @as(i32, @intCast(defended_zone_squares)) * king_defender_bonus;
}

// Rule of the Square: massive bonus for unstoppable passed pawns
fn evalRuleOfSquare(board: *brd.Board, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    var score: i32 = 0;

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_king_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.King)];
    if (opp_king_bb == 0) return 0;
    const opp_king_sq = brd.getLSB(opp_king_bb);

    // Only apply when opponent has no pieces other than king and pawns
    const opp_knights = @popCount(board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Knight)]);
    const opp_bishops = @popCount(board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Bishop)]);
    const opp_rooks = @popCount(board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Rook)]);
    const opp_queens = @popCount(board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Queen)]);
    if (opp_knights + opp_bishops + opp_rooks + opp_queens > 0) return 0;

    var pawn_bb = our_pawns;
    while (pawn_bb != 0) {
        const sq = brd.getLSB(pawn_bb);
        if (checkPassedPawn(board, sq, color)) {
            const rank: i32 = @intCast(@divTrunc(sq, 8));
            const file: i32 = @intCast(@mod(sq, 8));
            const promo_rank: i32 = if (color == brd.Color.White) 7 else 0;
            const promo_sq_file = file;
            const pawn_dist = @abs(promo_rank - rank);

            // Adjust for tempo: if it's opponent's turn, they get one extra move
            const tempo_adjust: i32 = if (board.toMove() != color) 1 else 0;

            const king_rank: i32 = @intCast(@divTrunc(opp_king_sq, 8));
            const king_file: i32 = @intCast(@mod(opp_king_sq, 8));
            const king_dist = @as(i32, @intCast(@max(@abs(king_rank - promo_rank), @abs(king_file - promo_sq_file))));

            if (pawn_dist < king_dist - tempo_adjust) {
                score += rule_of_square_bonus;
            }
        }
        brd.popBit(&pawn_bb, sq);
    }

    return score;
}

// Trapped Pieces: penalize pieces with very low mobility
fn evalTrappedPieces(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen, cache: AttackCache) i32 {
    const c_idx = @intFromEnum(color);
    const our_pieces = board.color_bb[c_idx];
    const occupancy = cache.occupancy;
    var score: i32 = 0;

    var opp_pawn_attacks: u64 = 0;
    if (color == .White) {
        opp_pawn_attacks = cache.opp_pawn_attacks;
    } else {
        opp_pawn_attacks = cache.our_pawn_attacks;
    }

    // Knights
    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const attacks = move_gen.knights[sq];
        const safe = attacks & ~our_pieces & ~opp_pawn_attacks;
        if (@popCount(safe) == 0) {
            score -= trapped_piece_penalty;
        }
        brd.popBit(&bb, sq);
    }

    // Bishops
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const attacks = move_gen.getBishopAttacks(sq, occupancy);
        const safe = attacks & ~our_pieces & ~opp_pawn_attacks;
        if (@popCount(safe) == 0) {
            score -= trapped_piece_penalty;
        }
        brd.popBit(&bb, sq);
    }

    // Rooks
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const attacks = move_gen.getRookAttacks(sq, occupancy);
        const safe = attacks & ~our_pieces & ~opp_pawn_attacks;
        if (@popCount(safe) <= 1) {
            score -= trapped_piece_penalty;
        }
        brd.popBit(&bb, sq);
    }

    return score;
}

pub fn almostMate(score: i32) bool {
    return @abs(score) > mate_score - 256;
}

// TEXEL TUNER INFRASTRUCTURE
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
pub const P_ROOK_OPEN_FILE: usize = P_ISOLATED_PAWN + 1;
pub const P_ROOK_SEMI_OPEN: usize = P_ROOK_OPEN_FILE + 1;
pub const P_MINOR_THREAT: usize = P_ROOK_SEMI_OPEN + 1;
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

// Newly exposed parameters
pub const P_EXCHANGE_AVOIDANCE: usize = P_EXTENDED_CENTER + 1;
pub const P_MOPUP_EDGE: usize = P_EXCHANGE_AVOIDANCE + 1;
pub const P_MOPUP_PROXIMITY: usize = P_MOPUP_EDGE + 1;
pub const P_KING_CENTRALIZATION: usize = P_MOPUP_PROXIMITY + 1;
pub const P_KING_FAR_PAWN: usize = P_KING_CENTRALIZATION + 1;
pub const P_DEFENDED_BY_PAWN: usize = P_KING_FAR_PAWN + 1;
pub const P_PAWN_ADVANCEMENT: usize = P_DEFENDED_BY_PAWN + 1;

// New feature parameters
pub const P_PAWN_STORM: usize = P_PAWN_ADVANCEMENT + 1;
pub const P_KING_ZONE_ATTACK: usize = P_PAWN_STORM + 1;
pub const P_KING_DEFENDER: usize = P_KING_ZONE_ATTACK + 1;
pub const P_RULE_OF_SQUARE: usize = P_KING_DEFENDER + 1;
pub const P_TRAPPED_PIECE: usize = P_RULE_OF_SQUARE + 1;

pub const NUM_PARAMS: usize = P_TRAPPED_PIECE + 1;

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
    buf[P_ROOK_OPEN_FILE] = rook_on_open_file_bonus;
    buf[P_ROOK_SEMI_OPEN] = rook_on_semi_open_file_bonus;
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
    buf[P_EXCHANGE_AVOIDANCE] = exchange_avoidance_weight;
    buf[P_MOPUP_EDGE] = mopup_edge_weight;
    buf[P_MOPUP_PROXIMITY] = mopup_proximity_weight;
    buf[P_KING_CENTRALIZATION] = king_centralization_weight;
    buf[P_KING_FAR_PAWN] = king_far_pawn_penalty;
    buf[P_DEFENDED_BY_PAWN] = defended_by_pawn_penalty;
    buf[P_PAWN_ADVANCEMENT] = pawn_advancement_scaler;
    buf[P_PAWN_STORM] = pawn_storm_penalty;
    buf[P_KING_ZONE_ATTACK] = king_zone_attack_weight;
    buf[P_KING_DEFENDER] = king_defender_bonus;
    buf[P_RULE_OF_SQUARE] = rule_of_square_bonus;
    buf[P_TRAPPED_PIECE] = trapped_piece_penalty;
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
    rook_on_open_file_bonus = buf[P_ROOK_OPEN_FILE];
    rook_on_semi_open_file_bonus = buf[P_ROOK_SEMI_OPEN];
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
    exchange_avoidance_weight = buf[P_EXCHANGE_AVOIDANCE];
    mopup_edge_weight = buf[P_MOPUP_EDGE];
    mopup_proximity_weight = buf[P_MOPUP_PROXIMITY];
    king_centralization_weight = buf[P_KING_CENTRALIZATION];
    king_far_pawn_penalty = buf[P_KING_FAR_PAWN];
    defended_by_pawn_penalty = buf[P_DEFENDED_BY_PAWN];
    pawn_advancement_scaler = buf[P_PAWN_ADVANCEMENT];
    pawn_storm_penalty = buf[P_PAWN_STORM];
    king_zone_attack_weight = buf[P_KING_ZONE_ATTACK];
    king_defender_bonus = buf[P_KING_DEFENDER];
    rule_of_square_bonus = buf[P_RULE_OF_SQUARE];
    trapped_piece_penalty = buf[P_TRAPPED_PIECE];
}

pub fn evalTuner(board: *brd.Board, move_gen: *mvs.MoveGen) i32 {
    const raw = evaluate(board, move_gen, -mate_score, mate_score, true);
    return if (board.toMove() == .White) raw else -raw;
}

pub fn computeCoefficients(board: *brd.Board, move_gen: *mvs.MoveGen) [NUM_PARAMS]f64 {
    var mg_c = std.mem.zeroes([NUM_PARAMS]f64);
    var eg_c = std.mem.zeroes([NUM_PARAMS]f64);

    var current_phase: i32 = 0;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][1]) + @popCount(board.piece_bb[1][1]))) * knight_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][2]) + @popCount(board.piece_bb[1][2]))) * bishop_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][3]) + @popCount(board.piece_bb[1][3]))) * rook_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][4]) + @popCount(board.piece_bb[1][4]))) * queen_phase;
    current_phase = std.math.clamp(current_phase, 0, total_phase);

    coeffsBase(board, .White, &mg_c, &eg_c, 1.0);
    coeffsBase(board, .Black, &mg_c, &eg_c, -1.0);

    const cache = populateAttackCache(board, move_gen);
    coeffsActivity(board, .White, move_gen, cache, &mg_c, &eg_c, 1.0);
    coeffsActivity(board, .Black, move_gen, cache, &mg_c, &eg_c, -1.0);

    coeffsKingSafety(board, .White, &mg_c, 1.0);
    coeffsKingSafety(board, .Black, &mg_c, -1.0);

    coeffsPawnStructure(board, .White, current_phase, &mg_c, &eg_c, 1.0);
    coeffsPawnStructure(board, .Black, current_phase, &mg_c, &eg_c, -1.0);

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

    if (current_phase < @divTrunc(total_phase, 2)) {
        coeffsEndgame(board, &eg_c);
    }

    coeffsThreats(board, .White, cache, &mg_c, &eg_c, 1.0);
    coeffsThreats(board, .Black, cache, &mg_c, &eg_c, -1.0);

    coeffsSpace(board, .White, cache, &mg_c, &eg_c, 1.0);
    coeffsSpace(board, .Black, cache, &mg_c, &eg_c, -1.0);

    // Exchange avoidance coefficients
    coeffsExchangeAvoidance(board, &mg_c, &eg_c);

    // Pawn storm coefficients (mg only)
    coeffsPawnStorm(board, .White, &mg_c, 1.0);
    coeffsPawnStorm(board, .Black, &mg_c, -1.0);

    // King zone control coefficients (mg only)
    coeffsKingZoneControl(board, .White, move_gen, cache, &mg_c, 1.0);
    coeffsKingZoneControl(board, .Black, move_gen, cache, &mg_c, -1.0);

    // King defender coefficients (mg only)
    coeffsKingDefenders(board, .White, move_gen, cache, &mg_c, 1.0);
    coeffsKingDefenders(board, .Black, move_gen, cache, &mg_c, -1.0);

    // Rule of square coefficients (eg only)
    if (current_phase < @divTrunc(total_phase, 2)) {
        coeffsRuleOfSquare(board, .White, &eg_c, 1.0);
        coeffsRuleOfSquare(board, .Black, &eg_c, -1.0);
    }

    // Trapped pieces coefficients (both mg and eg)
    coeffsTrappedPieces(board, .White, move_gen, cache, &mg_c, &eg_c, 1.0);
    coeffsTrappedPieces(board, .Black, move_gen, cache, &mg_c, &eg_c, -1.0);

    var coeffs: [NUM_PARAMS]f64 = undefined;
    const ph: f64 = @floatFromInt(current_phase);
    const inv_ph: f64 = 24.0 - ph;
    for (0..NUM_PARAMS) |i| {
        coeffs[i] = (mg_c[i] * ph + eg_c[i] * inv_ph) / 24.0;
    }

    coeffs[P_TEMPO_BONUS] = if (board.toMove() == .White) 1.0 else -1.0;

    return coeffs;
}

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
        mg_c[P_MG_KING] += sign;
        eg_c[P_EG_KING] += sign;
    }
}

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

    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);

        const rank = @divTrunc(sq, 8);
        const relative_rank = if (color == .White) rank else 7 - rank;
        const is_supported = (our_pawn_attacks & (@as(u64, 1) << @intCast(sq))) != 0;
        if (is_supported and relative_rank >= 3 and relative_rank <= 5) {
            mg_c[P_KNIGHT_OUTPOST] += sign;
            eg_c[P_KNIGHT_OUTPOST] += sign;
        }

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_c[P_MINOR_THREAT] -= sign; 
            eg_c[P_MINOR_THREAT] -= sign;
        }

        coeffsMobility(sq, .Knight, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        const attack_mask = move_gen.knights[@as(usize, @intCast(sq))];
        if (attack_mask & opp_king_zone != 0) {
            attack_units += knight_attack_bonus;
            attacker_count += 1;
            n_knights_atk += 1;
        }

        brd.popBit(&bb, sq);
    }

    // Bishops 
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);

        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_c[P_MINOR_THREAT] -= sign;
            eg_c[P_MINOR_THREAT] -= sign;
        }

        const bishop_mask: u64 = move_gen.getBishopAttacks(sq, occupancy);
        const blocking_pawns: i32 = @as(i32, @intCast(@popCount(our_pawns & bishop_mask)));
        if (blocking_pawns > 1) {
            const count_f: f64 = @floatFromInt(blocking_pawns - 1);
            mg_c[P_BAD_BISHOP] -= sign * count_f;
            eg_c[P_BAD_BISHOP] -= sign * count_f;
        }

        if (bishop_mask & opp_queen_bb != 0) {
            mg_c[P_BISHOP_ON_QUEEN] += sign;
            eg_c[P_BISHOP_ON_QUEEN] += sign;
        }
        if (bishop_mask & opp_king_bb != 0) {
            mg_c[P_BISHOP_ON_KING] += sign;
            eg_c[P_BISHOP_ON_KING] += sign;
        }

        coeffsMobility(sq, .Bishop, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        const attack_mask = move_gen.getBishopAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            attack_units += bishop_attack_bonus;
            attacker_count += 1;
            n_bishops_atk += 1;
        }

        brd.popBit(&bb, sq);
    }

    // Rooks 
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

    // Queens 
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

    if (attacker_count > 1) {
        const idx = @as(usize, @intCast(std.math.clamp(attack_units, 0, 15)));
        mg_c[P_SAFETY_TABLE + idx] += sign;

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

            const eg_scale: f64 = if (phase < 12) 1.5 else 1.0;
            eg_c[P_EG_PASSED + relative_rank] += sign * eg_scale;

            // Pawn advancement scaler coefficient (eg only, for relative_rank >= 5)
            if (relative_rank >= 5) {
                const tp: f64 = @floatFromInt(total_phase);
                const ph: f64 = @floatFromInt(phase);
                const rr: f64 = @floatFromInt(relative_rank);
                eg_c[P_PAWN_ADVANCEMENT] += sign * (tp - ph) * rr / tp;
            }
        }

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

        if ((our_pawns & adjacent_files) == 0) {
            mg_c[P_ISOLATED_PAWN] += sign;
            eg_c[P_ISOLATED_PAWN] += sign;
        }

        if (file_counts[file] > 1) {
            mg_c[P_DOUBLED_PAWN] += sign;
            eg_c[P_DOUBLED_PAWN] += sign;
        }

        brd.popBit(&temp_bb, sq);
    }
}

fn coeffsEndgame(board: *brd.Board, eg_c: []f64) void {
    // evalRookEndgame for white (+1) and black (-1)
    coeffsRookEndgame(board, .White, eg_c, 1.0);
    coeffsRookEndgame(board, .Black, eg_c, -1.0);

    // evalKingActivity king_pawn_proximity for white (+1) and black (-1)
    coeffsKingActivity(board, .White, eg_c, 1.0);
    coeffsKingActivity(board, .Black, eg_c, -1.0);

    // Mop-up coefficients
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

            const sign: f64 = if (material_diff > 0) 1.0 else -1.0;
            eg_c[P_MOPUP_EDGE] += sign * @as(f64, @floatFromInt(centerDistance(loser_king_sq)));
            eg_c[P_MOPUP_PROXIMITY] += sign * @as(f64, @floatFromInt(14 - manhattanDistance(winner_king_sq, loser_king_sq)));
        }
    }
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

    // King centralization coefficient
    const centralization = 7 - centerDistance(king_sq);
    eg_c[P_KING_CENTRALIZATION] += sign * @as(f64, @floatFromInt(centralization));

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

    // King far from opponent's passed pawns
    pawn_bb = board.piece_bb[1 - c_idx][@intFromEnum(brd.Pieces.Pawn)];
    while (pawn_bb != 0) {
        const pawn_sq = brd.getLSB(pawn_bb);
        const opp_color = if (color == brd.Color.White) brd.Color.Black else brd.Color.White;
        if (checkPassedPawn(board, pawn_sq, opp_color)) {
            const dist = manhattanDistance(king_sq, pawn_sq);
            if (dist > 4) {
                eg_c[P_KING_FAR_PAWN] -= sign;
            }
        }
        brd.popBit(&pawn_bb, pawn_sq);
    }
}

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
                    // score -= defended_by_pawn_penalty
                    mg_c[P_DEFENDED_BY_PAWN] -= sign;
                    eg_c[P_DEFENDED_BY_PAWN] -= sign;
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

fn coeffsExchangeAvoidance(board: *brd.Board, mg_c: []f64, eg_c: []f64) void {
    const white_mat = countMaterial(board, brd.Color.White);
    const black_mat = countMaterial(board, brd.Color.Black);
    const diff = white_mat - black_mat;
    if (@abs(diff) < 100) return;

    const white_pieces = @popCount(board.color_bb[@intFromEnum(brd.Color.White)]);
    const black_pieces = @popCount(board.color_bb[@intFromEnum(brd.Color.Black)]);
    const total_pieces: f64 = @floatFromInt(white_pieces + black_pieces);

    const sign: f64 = if (diff > 0) 1.0 else -1.0;
    mg_c[P_EXCHANGE_AVOIDANCE] += sign * total_pieces;
    eg_c[P_EXCHANGE_AVOIDANCE] += sign * total_pieces;
}

fn coeffsPawnStorm(board: *brd.Board, color: brd.Color, mg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return;

    const king_sq = brd.getLSB(king_bb);
    const king_file: i32 = @intCast(@mod(king_sq, 8));

    if (king_file > 2 and king_file < 5) return;

    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];
    const files = [3]i32{ king_file - 1, king_file, king_file + 1 };
    for (files) |file| {
        if (file < 0 or file > 7) continue;
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        var pawns = opp_pawns & file_mask;
        while (pawns != 0) {
            const sq = brd.getLSB(pawns);
            const pawn_rank: i32 = @intCast(@divTrunc(sq, 8));
            const advance = if (color == brd.Color.White) 7 - pawn_rank else pawn_rank;
            if (advance >= 4) {
                const storm_val: f64 = @floatFromInt(advance - 3);
                mg_c[P_PAWN_STORM] -= sign * storm_val;
            }
            brd.popBit(&pawns, sq);
        }
    }
}

fn coeffsKingZoneControl(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen, cache: AttackCache, mg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return;

    const king_sq = brd.getLSB(king_bb);
    const king_zone = getKingZone(king_sq, color, move_gen);

    var opp_attacks: u64 = 0;
    if (color == .White) {
        opp_attacks = cache.opp_pawn_attacks | cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks;
    } else {
        opp_attacks = cache.our_pawn_attacks | cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks;
    }

    const attacked: f64 = @floatFromInt(@popCount(opp_attacks & king_zone));
    mg_c[P_KING_ZONE_ATTACK] -= sign * attacked;
}

fn coeffsKingDefenders(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen, cache: AttackCache, mg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return;

    const king_sq = brd.getLSB(king_bb);
    const king_zone = getKingZone(king_sq, color, move_gen);

    var our_attacks: u64 = 0;
    if (color == .White) {
        our_attacks = cache.our_pawn_attacks | cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks;
    } else {
        our_attacks = cache.opp_pawn_attacks | cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks;
    }

    const defended: f64 = @floatFromInt(@popCount(our_attacks & king_zone));
    mg_c[P_KING_DEFENDER] += sign * defended;
}

fn coeffsRuleOfSquare(board: *brd.Board, color: brd.Color, eg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_king_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.King)];
    if (opp_king_bb == 0) return;
    const opp_king_sq = brd.getLSB(opp_king_bb);

    const opp_knights = @popCount(board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Knight)]);
    const opp_bishops = @popCount(board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Bishop)]);
    const opp_rooks = @popCount(board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Rook)]);
    const opp_queens = @popCount(board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Queen)]);
    if (opp_knights + opp_bishops + opp_rooks + opp_queens > 0) return;

    var pawn_bb = our_pawns;
    while (pawn_bb != 0) {
        const sq = brd.getLSB(pawn_bb);
        if (checkPassedPawn(board, sq, color)) {
            const rank: i32 = @intCast(@divTrunc(sq, 8));
            const file: i32 = @intCast(@mod(sq, 8));
            const promo_rank: i32 = if (color == brd.Color.White) 7 else 0;
            const pawn_dist = @abs(promo_rank - rank);
            const tempo_adjust: i32 = if (board.toMove() != color) 1 else 0;

            const king_rank: i32 = @intCast(@divTrunc(opp_king_sq, 8));
            const king_file: i32 = @intCast(@mod(opp_king_sq, 8));
            const king_dist = @as(i32, @intCast(@max(@abs(king_rank - promo_rank), @abs(king_file - file))));

            if (pawn_dist < king_dist - tempo_adjust) {
                eg_c[P_RULE_OF_SQUARE] += sign;
            }
        }
        brd.popBit(&pawn_bb, sq);
    }
}

fn coeffsTrappedPieces(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen, cache: AttackCache, mg_c: []f64, eg_c: []f64, sign: f64) void {
    const c_idx = @intFromEnum(color);
    const our_pieces = board.color_bb[c_idx];
    const occupancy = cache.occupancy;

    var opp_pawn_attacks: u64 = 0;
    if (color == .White) {
        opp_pawn_attacks = cache.opp_pawn_attacks;
    } else {
        opp_pawn_attacks = cache.our_pawn_attacks;
    }

    // Knights
    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const attacks = move_gen.knights[sq];
        const safe = attacks & ~our_pieces & ~opp_pawn_attacks;
        if (@popCount(safe) == 0) {
            mg_c[P_TRAPPED_PIECE] -= sign;
            eg_c[P_TRAPPED_PIECE] -= sign;
        }
        brd.popBit(&bb, sq);
    }

    // Bishops
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const attacks = move_gen.getBishopAttacks(sq, occupancy);
        const safe = attacks & ~our_pieces & ~opp_pawn_attacks;
        if (@popCount(safe) == 0) {
            mg_c[P_TRAPPED_PIECE] -= sign;
            eg_c[P_TRAPPED_PIECE] -= sign;
        }
        brd.popBit(&bb, sq);
    }

    // Rooks
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        const attacks = move_gen.getRookAttacks(sq, occupancy);
        const safe = attacks & ~our_pieces & ~opp_pawn_attacks;
        if (@popCount(safe) <= 1) {
            mg_c[P_TRAPPED_PIECE] -= sign;
            eg_c[P_TRAPPED_PIECE] -= sign;
        }
        brd.popBit(&bb, sq);
    }
}
