const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const zob = @import("zobrist");
const pawn_tt = @import("pawn_tt");

pub const mate_score: i32 = 888888;
pub const tb_win_score: i32 = mate_score - 1024;

pub var lazy_margin: i32 = 810;

const total_phase: i32 = 24;
const pawn_phase: i32 = 0;
const knight_phase: i32 = 1;
const bishop_phase: i32 = 1;
const rook_phase: i32 = 2;
const queen_phase: i32 = 4;

pub var mg_pawn: i32 = 81;
pub var eg_pawn: i32 = 78;
pub var mg_knight: i32 = 333;
pub var eg_knight: i32 = 303;
pub var mg_bishop: i32 = 349;
pub var eg_bishop: i32 = 305;
pub var mg_rook: i32 = 451;
pub var eg_rook: i32 = 550;
pub var mg_queen: i32 = 949;
pub var eg_queen: i32 = 997;
pub var mg_king: i32 = 0;
pub var eg_king: i32 = 0;
pub var mg_pawn_table = [64]i32{
       0,   0,   0,   0,   0,   0,   0,   0,
      -14,  -12,   -9,   -7,   1,  18,  35,  -14,
      -22,  -17,   -9,   -9,   7,   -8,   7,  -19,
      -15,   -8,   2,  12,  16,  11,   4,  -18,
      -14,   5,   5,   8,  32,  34,  22,   4,
       2,  17,  37,  29,  41,  98,  69,  10,
     104, 116,  85, 123, 100,  62,  -51,  -55,
       0,   0,   0,   0,   0,   0,   0,   0,
};
pub var eg_pawn_table = [64]i32{
       0,   0,   0,   0,   0,   0,   0,   0,
      19,  15,  10,  11,  21,  13,   -3,   -8,
      16,  10,   2,   2,   3,   8,   -5,   -3,
      23,  24,   0,  -12,   -9,   -2,   7,   2,
      46,  35,  16,   -8,   -7,   1,  20,  15,
      81,  84,  41,   5,   -1,  12,  53,  59,
     176, 162, 175, 115, 111, 127, 183, 187,
       0,   0,   0,   0,   0,   0,   0,   0,
};
pub var mg_knight_table = [64]i32{
      -85,  -26,  -36,  -14,   -4,   2,  -21,  -52,
      -39,  -31,  -13,  10,   9,   6,   -5,   -1,
      -32,   -8,   0,  14,  29,  11,  13,   -3,
       -3,   -3,  14,  21,  29,  21,  31,  14,
      14,  13,  29,  60,  29,  61,  17,  53,
       -4,  24,  50,  57,  93,  91,  50,  24,
       -5,   0,  21,  49,  23,  74,   -9,  30,
     -185, -153,  -95,  -37,  16, -108, -121, -135,
};
pub var eg_knight_table = [64]i32{
      -28,  -42,  -16,   -7,   -7,  -22,  -33,  -20,
      -22,   -6,  -11,  -11,   -8,  -16,  -17,   -9,
      -28,  -10,   -5,  20,  15,  -10,  -15,  -14,
       -2,   -2,  18,  23,  29,  10,   -5,   -1,
       -2,   2,  16,  21,  23,  13,  10,   -6,
      -13,  -10,   3,   7,   -8,  -14,  -21,  -27,
      -25,  -10,  -15,   -8,  -19,  -35,   -8,  -42,
      -88,  -13,   0,  -18,  -18,   -7,  -11, -105,
};
pub var mg_bishop_table = [64]i32{
       0,  22,   -7,  -11,   -2,   -6,   6,  15,
       5,  12,  22,   2,  13,  22,  32,  18,
      -10,  11,  13,  10,  13,  17,  15,  19,
       1,  -12,   2,  32,  25,   1,   0,  20,
       -3,   9,  14,  36,  25,  24,   7,   -1,
       4,  15,  27,  23,  23,  51,  32,   9,
      -16,   3,   -7,  -30,  -10,   -3,  -38,  -32,
      -52,  -64, -101, -119, -106, -131,  -40,  -73,
};
pub var eg_bishop_table = [64]i32{
      -25,   2,  -13,   -5,   -2,   4,  -15,  -35,
       -2,  -21,  -16,   1,   -3,   -9,  -15,  -28,
       -6,   8,   8,  14,  20,   6,   -1,  -14,
       -6,  11,  19,  19,  18,  11,   7,  -18,
       1,  13,   8,  24,  16,  11,   9,   3,
       7,   5,   2,   -4,   -1,   8,   3,   4,
       -9,   -4,   0,   7,   -2,   -2,   6,   -6,
      10,  11,  15,  18,  15,   9,   2,   -5,
};
pub var mg_rook_table = [64]i32{
      -19,  -14,  -13,   -3,   6,   7,   6,   -8,
      -41,  -30,  -22,  -17,  -10,   3,  16,  -22,
      -37,  -35,  -35,  -28,  -16,  -13,  18,   -1,
      -31,  -36,  -32,  -21,  -21,  -23,   2,   -9,
      -13,   -5,   -7,   8,   5,  25,  31,  22,
      -13,  20,   4,  17,  48,  66, 107,  48,
       8,   -3,  17,  41,  30,  68,  56,  78,
      30,  32,   -1,  15,  17,  52,  71,  83,
};
pub var eg_rook_table = [64]i32{
       -3,   -1,   8,   -8,  -16,   -7,  -11,  -23,
       -3,   -1,   2,   -5,  -12,  -18,  -23,  -18,
       8,  12,  10,   3,   -2,   -4,  -13,  -16,
      19,  24,  24,  15,  14,  14,   8,   3,
      27,  24,  30,  18,   9,   5,   9,   8,
      32,  24,  30,  15,   6,   4,   -2,   7,
      33,  44,  45,  30,  30,  20,  19,  10,
      22,  23,  41,  25,  24,  26,  19,  13,
};
pub var mg_queen_table = [64]i32{
       -8,   -5,   -1,   5,  12,   -8,   1,   -7,
       -3,   -3,   4,   9,   6,  25,  22,  23,
       -8,   -6,   -6,  -11,   -4,   0,   6,  10,
       -3,  -17,  -20,  -17,  -17,   -8,   -5,  13,
       -3,  -16,  -20,  -28,  -24,   -8,   0,   9,
       -4,   -8,  -13,  -15,   -7,  40,  44,  28,
       -7,  -38,  -30,  -55,  -56,  12,   -9,  59,
      -42,  -35,  -30,   -4,   0,  20,  57,  10,
};
pub var eg_queen_table = [64]i32{
      -39,  -41,  -32,  -20,  -41,  -46,  -62,  -49,
      -34,  -29,  -34,  -21,  -16,  -60,  -79,  -70,
      -18,   4,  19,  16,  23,  19,  11,   -6,
       -6,  36,  40,  66,  65,  57,  51,  39,
       5,  45,  55,  87, 103,  97,  96,  67,
      16,  27,  66,  84, 106,  91,  63,  78,
      15,  54,  81, 121, 147,  92,  88,  52,
      24,  42,  74,  66,  69,  72,  23,  35,
};
pub var mg_king_table = [64]i32{
      18,  50,  10,  -68,  -10,  -45,  13,  35,
      36,   1,  -12,  -51,  -48,  -34,  22,  30,
      -41,   8,  -21,  -36,  -26,  -38,  -12,  -51,
      -61,   -3,   0,  -65,  -37,  -12,   -7, -111,
      -58,  11,  -11,  -72,  -59,   -3,   3,  -91,
      -90,  67,  32,  -33,  10,  72,  37,  -62,
     -100,  19,   7,  86,  20,  12,  10,  -73,
     110, 132, 112,  27,   3,  29, 100, 194,
};
pub var eg_king_table = [64]i32{
      -34,  -24,  -12,   -5,  -33,   0,  -23,  -60,
       -6,  10,  12,   7,   8,  12,   0,  -16,
      -13,   0,   4,   3,   2,   7,   2,   -3,
      -29,   -7,   -3,   5,   -4,   -1,   -3,   -4,
      -11,   9,  12,   8,   8,  18,  25,   9,
      24,  33,  25,  25,  26,  43,  61,  34,
      26,  47,  36,   4,  27,  58,  76,  49,
      -97,  -37,  -26,   -5,  -11,   8,  15,  -98,
};
pub var mg_knight_mobility = [9]i32{ -7, -3, 9, 14, 19, 26, 34, 41, 41, };
pub var mg_bishop_mobility = [14]i32{ -10, -9, 0, 6, 13, 17, 20, 21, 23, 26, 27, 27, 27, 27, };
pub var mg_rook_mobility = [15]i32{ -7, 3, 4, 6, 6, 9, 10, 12, 16, 18, 21, 22, 22, 22, 22, };
pub var mg_queen_mobility = [28]i32{ 8, 8, 8, 9, 10, 13, 15, 17, 20, 23, 24, 25, 27, 27, 27, 28, 30, 31, 39, 40, 48, 50, 50, 51, 54, 55, 69, 69, };
pub var eg_knight_mobility = [9]i32{ -121, -120, -90, -73, -63, -54, -54, -55, -55, };
pub var eg_bishop_mobility = [14]i32{ -125, -124, -103, -86, -71, -57, -49, -45, -45, -45, -45, -45, -45, -45, };
pub var eg_rook_mobility = [15]i32{ -75, -46, -44, -32, -25, -15, -6, -1, 3, 7, 10, 10, 10, 10, 10, };
pub var eg_queen_mobility = [28]i32{ -224, -193, -158, -129, -101, -86, -70, -49, -43, -36, -27, -20, -15, -10, -5, -2, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, };
pub var mg_passed_bonus = [8]i32{ 0, -13, -16, -14, 20, 42, 48, 0, };
pub var passed_pawn_bonus = [8]i32{ 0, -27, -16, 8, 31, 73, 49, 0, };
pub var safety_quadratic_a: i32 = 24;
pub var safety_quadratic_b: i32 = -42;
pub var mg_knight_king_atk: i32 = -8;
pub var mg_bishop_king_atk: i32 = 6;
pub var mg_rook_king_atk: i32 = -10;
pub var mg_queen_king_atk: i32 = 3;
pub var castled_bonus: i32 = 15;
pub var pawn_shield_bonus: i32 = 11;
pub var open_file_penalty: i32 = -53;
pub var semi_open_penalty: i32 = -17;
pub var mg_protected_pawn: i32 = 11;
pub var eg_protected_pawn: i32 = 9;
pub var mg_doubled_pawn: i32 = -4;
pub var eg_doubled_pawn: i32 = -24;
pub var mg_isolated_pawn: i32 = -10;
pub var eg_isolated_pawn: i32 = -12;
pub var mg_rook_open_file: i32 = 45;
pub var eg_rook_open_file: i32 = 8;
pub var mg_rook_semi_open: i32 = 15;
pub var eg_rook_semi_open: i32 = 22;
pub var mg_minor_threat: i32 = 35;
pub var eg_minor_threat: i32 = 21;
pub var mg_rook_threat: i32 = 11;
pub var eg_rook_threat: i32 = 2;
pub var mg_queen_threat: i32 = 11;
pub var eg_queen_threat: i32 = -4;
pub var mg_rook_on_queen: i32 = 14;
pub var eg_rook_on_queen: i32 = -5;
pub var mg_rook_on_king: i32 = 20;
pub var eg_rook_on_king: i32 = -26;
pub var mg_queen_on_king: i32 = 9;
pub var eg_queen_on_king: i32 = -7;
pub var mg_bad_bishop: i32 = 2;
pub var eg_bad_bishop: i32 = 12;
pub var mg_bishop_on_queen: i32 = 57;
pub var eg_bishop_on_queen: i32 = 45;
pub var mg_bishop_on_king: i32 = -26;
pub var eg_bishop_on_king: i32 = 14;
pub var mg_hanging_piece: i32 = 7;
pub var eg_hanging_piece: i32 = 0;
pub var mg_atk_by_pawn: i32 = -2;
pub var eg_atk_by_pawn: i32 = -9;
pub var mg_atk_by_minor: i32 = 59;
pub var eg_atk_by_minor: i32 = 21;
pub var mg_atk_by_rook: i32 = 81;
pub var eg_atk_by_rook: i32 = 7;
pub var mg_defended_by_pawn: i32 = 19;
pub var eg_defended_by_pawn: i32 = 5;
pub var mg_knight_outpost: i32 = 3;
pub var eg_knight_outpost: i32 = 28;
pub var mg_bishop_pair: i32 = 30;
pub var eg_bishop_pair: i32 = 82;
pub var mg_space_per_sq: i32 = 0;
pub var eg_space_per_sq: i32 = -2;
pub var mg_center_ctrl: i32 = -2;
pub var eg_center_ctrl: i32 = 4;
pub var mg_extended_center: i32 = 4;
pub var eg_extended_center: i32 = -1;
pub var mg_exchange_avoidance: i32 = -4;
pub var eg_exchange_avoidance: i32 = 21;
pub var mg_trapped_knight: i32 = 11;
pub var eg_trapped_knight: i32 = 58;
pub var mg_trapped_bishop: i32 = 9;
pub var eg_trapped_bishop: i32 = 27;
pub var mg_trapped_rook: i32 = 3;
pub var eg_trapped_rook: i32 = 4;
pub var rook_on_7th_bonus: i32 = -5;
pub var rook_behind_passer_bonus: i32 = 20;
pub var king_pawn_proximity: i32 = 8;
pub var king_far_pawn_penalty: i32 = 42;
pub var king_centralization_weight: i32 = 16;
pub var mopup_edge_weight: i32 = -43;
pub var mopup_proximity_weight: i32 = 7;
pub var rule_of_square_bonus: i32 = 205;
pub var pawn_storm_weight: i32 = -9;
pub var king_zone_attack_weight: i32 = 18;
pub var king_defender_bonus: i32 = 1;
pub var tempo_bonus: i32 = 28;
pub var mg_pawn_advance_space: i32 = 2;
pub var eg_pawn_advance_space: i32 = -4;

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

    mg_score += white_base.mg - black_base.mg;
    eg_score += white_base.eg - black_base.eg;

    
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

    // pawn_tt.pawn_tt.prefetch(board.game_state.pawn_hash ^ zob.ZobristKeys.eval_phase[@as(usize, @intCast(current_phase))]);

    const got_pawns = false;
    // if (pawn_tt.pawn_tt.get(board.game_state.pawn_hash ^ zob.ZobristKeys.eval_phase[@as(usize, @intCast(current_phase))])) |e| {
    //     mg_score += e.mg;
    //     eg_score += e.eg;
    //     got_pawns = true;
    // }

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

    // Endgame features — always computed, phase interpolation handles weighting
    {
        const eg_eval = evalEndgame(board, current_phase);
        eg_score += eg_eval;

        // Rule of the Square (self-gates to pawn-only endgames)
        eg_score += evalRuleOfSquare(board, brd.Color.White);
        eg_score -= evalRuleOfSquare(board, brd.Color.Black);
    }

    const white_bishops = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)]);
    const black_bishops = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)]);
    if (white_bishops >= 2) {
        mg_score += mg_bishop_pair;
        eg_score += eg_bishop_pair;
    }
    if (black_bishops >= 2) {
        mg_score -= mg_bishop_pair;
        eg_score -= eg_bishop_pair;
    }

    const white_threats = evalThreats(board, brd.Color.White, attack_cache);
    const black_threats = evalThreats(board, brd.Color.Black, attack_cache);
    mg_score += white_threats.mg - black_threats.mg;
    eg_score += white_threats.eg - black_threats.eg;

    const white_space = evalSpace(board, brd.Color.White, attack_cache);
    const black_space = evalSpace(board, brd.Color.Black, attack_cache);
    mg_score += white_space.mg - black_space.mg;
    eg_score += white_space.eg - black_space.eg;

    const exchange_eval = evalExchangeAvoidance(board);
    mg_score += exchange_eval.mg;
    eg_score += exchange_eval.eg;

    const white_trapped = evalTrappedPieces(board, brd.Color.White, move_gen, attack_cache);
    const black_trapped = evalTrappedPieces(board, brd.Color.Black, move_gen, attack_cache);
    mg_score += white_trapped.mg - black_trapped.mg;
    eg_score += white_trapped.eg - black_trapped.eg;

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
    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

    var attacker_count: i32 = 0;

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];

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
            mg_score += mg_knight_outpost;
            eg_score += eg_knight_outpost;
        }

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_score -= mg_minor_threat;
            eg_score -= eg_minor_threat;
        }

        const mob = evalMobility(@as(usize, @intCast(sq)), .Knight, board, move_gen, opp_pawn_attacks, color);
        mg_score += mob.mg;
        eg_score += mob.eg;

        const attack_mask = move_gen.knights[@as(usize, @intCast(sq))];
        if (attack_mask & opp_king_zone != 0) {
            mg_score += mg_knight_king_atk;
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
            mg_score -= mg_minor_threat;
            eg_score -= eg_minor_threat;
        }

        const bishop_mask: u64 = move_gen.getBishopAttacks(sq, occupancy);
        const blocking_pawns: i32 = @as(i32, @intCast(@popCount(our_pawns & bishop_mask)));
        if (blocking_pawns > 1) {
            mg_score -= (blocking_pawns - 1) * mg_bad_bishop;
            eg_score -= (blocking_pawns - 1) * eg_bad_bishop;
        }

        if (bishop_mask & opp_queen_bb != 0) {
            mg_score += mg_bishop_on_queen;
            eg_score += eg_bishop_on_queen;
        }
        if (bishop_mask & opp_king_bb != 0) {
            mg_score += mg_bishop_on_king;
            eg_score += eg_bishop_on_king;
        }

        const mob = evalMobility(@as(usize, @intCast(sq)), .Bishop, board, move_gen, opp_pawn_attacks, color);
        mg_score += mob.mg;
        eg_score += mob.eg;

        const attack_mask = move_gen.getBishopAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            mg_score += mg_bishop_king_atk;
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
                mg_score += mg_rook_open_file;
                eg_score += eg_rook_open_file;
            } else {
                mg_score += mg_rook_semi_open;
                eg_score += eg_rook_semi_open;
            }
        }

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_score -= mg_rook_threat;
            eg_score -= eg_rook_threat;
        }

        if (file_mask & opp_queen_bb != 0) {
            mg_score += mg_rook_on_queen;
            eg_score += eg_rook_on_queen;
        }
        if (file_mask & opp_king_bb != 0) {
            mg_score += mg_rook_on_king;
            eg_score += eg_rook_on_king;
        }

        const mob = evalMobility(@as(usize, @intCast(sq)), .Rook, board, move_gen, opp_pawn_attacks, color);
        mg_score += mob.mg;
        eg_score += mob.eg;

        const rook_attack_mask = move_gen.getRookAttacks(sq, occupancy);
        if (rook_attack_mask & opp_king_zone != 0) {
            mg_score += mg_rook_king_atk;
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
            mg_score -= mg_queen_threat;
            eg_score -= eg_queen_threat;
        }

        const file = @mod(sq, 8);
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        if (file_mask & opp_king_bb != 0) {
            mg_score += mg_queen_on_king;
            eg_score += eg_queen_on_king;
        }

        const mob = evalMobility(@as(usize, @intCast(sq)), .Queen, board, move_gen, opp_pawn_attacks, color);
        mg_score += mob.mg;
        eg_score += mob.eg;

        const attack_mask = move_gen.getQueenAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            mg_score += mg_queen_king_atk;
            attacker_count += 1;
        }

        brd.popBit(&bb, sq);
    }

    // Quadratic king safety bonus based on attacker count
    if (attacker_count >= 1) {
        const safety_bonus = safety_quadratic_a * attacker_count * attacker_count + safety_quadratic_b * attacker_count;
        mg_score += safety_bonus;
    }

    return EvalStruct{
        .mg = mg_score,
        .eg = eg_score,
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

fn evalPawnStructure(board: *brd.Board, phase: i32) PawnEval {
    var result = PawnEval{ .mg = 0, .eg = 0 };
    const white_eval = evalPawnsForColor(board, brd.Color.White, phase);
    const black_eval = evalPawnsForColor(board, brd.Color.Black, phase);

    result.mg = white_eval.mg - black_eval.mg;
    result.eg = white_eval.eg - black_eval.eg;

    // pawn_tt.pawn_tt.set(pawn_tt.Entry{
    //     .hash = board.game_state.pawn_hash ^ zob.ZobristKeys.eval_phase[@as(usize, @intCast(phase))],
    //     .mg = result.mg,
    //     .eg = result.eg,
    // });

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
    var penalized_files: u8 = 0;
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

            result.mg += mg_bonus;
            result.eg += eg_bonus;
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
            result.mg += mg_protected_pawn;
            result.eg += eg_protected_pawn;
        }

        const is_isolated = blk: {
            break :blk (our_pawns & adjacent_files) == 0;
        };

        if (is_isolated) {
            result.mg += mg_isolated_pawn;
            result.eg += eg_isolated_pawn;
        }

        // Doubled pawn: penalize per-file (extra pawns), not per-pawn
        const file_bit = @as(u8, 1) << @intCast(file);
        if (file_counts[file] > 1 and (penalized_files & file_bit) == 0) {
            const extra: i32 = @as(i32, file_counts[file]) - 1;
            result.mg += extra * mg_doubled_pawn;
            result.eg += extra * eg_doubled_pawn;
            penalized_files |= file_bit;
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
    if (@abs(material_diff) > 400) {
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
            // Bring winning king closer to losing king (positive weight = reward proximity)
            const king_proximity = (14 - manhattanDistance(winner_king_sq, loser_king_sq)) * mopup_proximity_weight;
            const mopup_score = edge_score + king_proximity;

            if (material_diff > 0) {
                score += mopup_score;
            } else {
                score -= mopup_score;
            }
        }
    }

    score += evalKingActivity(board, brd.Color.White, phase);
    score -= evalKingActivity(board, brd.Color.Black, phase);

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

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];

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
        const seventh_rank: i32 = if (color == brd.Color.White) 6 else 1;
        if (rook_rank == seventh_rank) {
            score += rook_on_7th_bonus;
        }

        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(rook_file);
        const pawns_on_file = our_pawns & file_mask;

        var pawn_bb = pawns_on_file;
        while (pawn_bb != 0) {
            const pawn_sq = brd.getLSB(pawn_bb);
            const pawn_rank = @divTrunc(pawn_sq, 8);

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

fn evalMobility(sq: usize, piece: brd.Pieces, board: *brd.Board, move_gen: *mvs.MoveGen, opp_pawn_attacks: u64, color: brd.Color) EvalStruct {
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
        .Knight => .{
            .mg = if (count < mg_knight_mobility.len) mg_knight_mobility[count] else mg_knight_mobility[mg_knight_mobility.len - 1],
            .eg = if (count < eg_knight_mobility.len) eg_knight_mobility[count] else eg_knight_mobility[eg_knight_mobility.len - 1],
        },
        .Bishop => .{
            .mg = if (count < mg_bishop_mobility.len) mg_bishop_mobility[count] else mg_bishop_mobility[mg_bishop_mobility.len - 1],
            .eg = if (count < eg_bishop_mobility.len) eg_bishop_mobility[count] else eg_bishop_mobility[eg_bishop_mobility.len - 1],
        },
        .Rook => .{
            .mg = if (count < mg_rook_mobility.len) mg_rook_mobility[count] else mg_rook_mobility[mg_rook_mobility.len - 1],
            .eg = if (count < eg_rook_mobility.len) eg_rook_mobility[count] else eg_rook_mobility[eg_rook_mobility.len - 1],
        },
        .Queen => .{
            .mg = if (count < mg_queen_mobility.len) mg_queen_mobility[count] else mg_queen_mobility[mg_queen_mobility.len - 1],
            .eg = if (count < eg_queen_mobility.len) eg_queen_mobility[count] else eg_queen_mobility[eg_queen_mobility.len - 1],
        },
        else => .{ .mg = 0, .eg = 0 },
    };
}

inline fn getKingZone(king_sq: usize, _: brd.Color, move_gen: *mvs.MoveGen) u64 {
    return move_gen.kings[king_sq] | (@as(u64, 1) << @intCast(king_sq));
}

fn evalThreats(board: *brd.Board, color: brd.Color, cache: AttackCache) EvalStruct {
    const c_idx = @intFromEnum(color);
    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

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

            const is_defended = (our_defenses & sq_mask) != 0;
            if ((opp_pawn_attacks & sq_mask) != 0) {
                if (!is_defended) {
                    mg_score -= mg_hanging_piece + mg_atk_by_pawn;
                    eg_score -= eg_hanging_piece + eg_atk_by_pawn;
                } else {
                    mg_score -= mg_defended_by_pawn;
                    eg_score -= eg_defended_by_pawn;
                }
            }

            if ((opp_knight_attacks & sq_mask) != 0 or (opp_bishop_attacks & sq_mask) != 0) {
                if (!is_defended and (piece == .Rook or piece == .Queen)) {
                    mg_score -= mg_atk_by_minor;
                    eg_score -= eg_atk_by_minor;
                }
            }

            if ((opp_rook_attacks & sq_mask) != 0 and piece == .Queen) {
                if (!is_defended) {
                    mg_score -= mg_atk_by_rook;
                    eg_score -= eg_atk_by_rook;
                }
            }

            brd.popBit(&piece_bb, sq);
        }
    }

    return EvalStruct{ .mg = mg_score, .eg = eg_score };
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

fn evalSpace(board: *brd.Board, color: brd.Color, cache: AttackCache) EvalStruct {
    const c_idx = @intFromEnum(color);
    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

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

        const advance_bonus = if (color == brd.Color.White)
            @as(i32, @intCast(rank)) - 1
        else
            @as(i32, @intCast(6 - rank));
        if (advance_bonus > 0) {
            mg_score += advance_bonus * mg_pawn_advance_space;
            eg_score += advance_bonus * eg_pawn_advance_space;
        }

        brd.popBit(&pawn_bb, sq);
    }

    var our_attacks: u64 = 0;
    if (color == .White) {
        our_attacks = cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks | cache.our_defenses;
    } else {
        our_attacks = cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks | cache.opp_defenses;
    }

    const controlled_space: i32 = @intCast(@popCount(our_attacks & our_half));
    mg_score += controlled_space * mg_space_per_sq;
    eg_score += controlled_space * eg_space_per_sq;
    // Bonus for center control
    const center_control: i32 = @intCast(@popCount(our_attacks & center));
    mg_score += center_control * mg_center_ctrl;
    eg_score += center_control * eg_center_ctrl;
    const extended_control: i32 = @intCast(@popCount(our_attacks & extended_center));
    mg_score += extended_control * mg_extended_center;
    eg_score += extended_control * eg_extended_center;

    return EvalStruct{ .mg = mg_score, .eg = eg_score };
}

fn evalExchangeAvoidance(board: *brd.Board) EvalStruct {
    const white_mat = countMaterial(board, brd.Color.White);
    const black_mat = countMaterial(board, brd.Color.Black);
    const diff = white_mat - black_mat;
    const abs_diff = @abs(diff);
    if (abs_diff < 50) return EvalStruct{ .mg = 0, .eg = 0 };

    // Smooth ramp: linearly scales from 0 at 50cp to full at 250cp
    const ramp: i32 = @min(abs_diff - 50, 200);

    const white_pieces = @popCount(board.color_bb[@intFromEnum(brd.Color.White)]);
    const black_pieces = @popCount(board.color_bb[@intFromEnum(brd.Color.Black)]);
    const total_pieces: i32 = @intCast(white_pieces + black_pieces);

    const sign: i32 = if (diff > 0) 1 else -1;
    return EvalStruct{
        .mg = @divTrunc(sign * total_pieces * mg_exchange_avoidance * ramp, 200),
        .eg = @divTrunc(sign * total_pieces * eg_exchange_avoidance * ramp, 200),
    };
}

fn evalPawnStorm(board: *brd.Board, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    const king_bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (king_bb == 0) return 0;

    const king_sq = brd.getLSB(king_bb);
    const king_file: i32 = @intCast(@mod(king_sq, 8));
    const king_rank: i32 = @intCast(@divTrunc(king_sq, 8));

    if (king_file > 2 and king_file < 5) return 0;

    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];
    var score: i32 = 0;

    const files = [3]i32{ king_file - 1, king_file, king_file + 1 };
    for (files) |file| {
        if (file < 0 or file > 7) continue;
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        var pawns = opp_pawns & file_mask;
        while (pawns != 0) {
            const sq = brd.getLSB(pawns);
            const pawn_rank: i32 = @intCast(@divTrunc(sq, 8));
            const advance = if (color == brd.Color.White)
                7 - pawn_rank 
            else
                pawn_rank; 
            if (advance >= 4) {
                score -= (advance - 3) * pawn_storm_weight;
            }
            brd.popBit(&pawns, sq);
        }
    }
    _ = king_rank;
    return score;
}

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

fn evalRuleOfSquare(board: *brd.Board, color: brd.Color) i32 {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    var score: i32 = 0;

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_king_bb = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.King)];
    if (opp_king_bb == 0) return 0;
    const opp_king_sq = brd.getLSB(opp_king_bb);

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

fn evalTrappedPieces(board: *brd.Board, color: brd.Color, move_gen: *mvs.MoveGen, cache: AttackCache) EvalStruct {
    const c_idx = @intFromEnum(color);
    const our_pieces = board.color_bb[c_idx];
    const occupancy = cache.occupancy;
    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

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
            mg_score -= mg_trapped_knight;
            eg_score -= eg_trapped_knight;
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
            mg_score -= mg_trapped_bishop;
            eg_score -= eg_trapped_bishop;
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
            mg_score -= mg_trapped_rook;
            eg_score -= eg_trapped_rook;
        }
        brd.popBit(&bb, sq);
    }

    return EvalStruct{ .mg = mg_score, .eg = eg_score };
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

// Mobility tables — separate mg/eg (9+14+15+28 = 66 per phase, 132 total)
pub const P_MG_KNIGHT_MOB: usize = P_EG_KING_TABLE + 64;
pub const P_MG_BISHOP_MOB: usize = P_MG_KNIGHT_MOB + 9;
pub const P_MG_ROOK_MOB: usize = P_MG_BISHOP_MOB + 14;
pub const P_MG_QUEEN_MOB: usize = P_MG_ROOK_MOB + 15;
pub const P_EG_KNIGHT_MOB: usize = P_MG_QUEEN_MOB + 28;
pub const P_EG_BISHOP_MOB: usize = P_EG_KNIGHT_MOB + 9;
pub const P_EG_ROOK_MOB: usize = P_EG_BISHOP_MOB + 14;
pub const P_EG_QUEEN_MOB: usize = P_EG_ROOK_MOB + 15;

// Passed pawn tables
pub const P_MG_PASSED: usize = P_EG_QUEEN_MOB + 28;
pub const P_EG_PASSED: usize = P_MG_PASSED + 8;

// King safety — quadratic model
pub const P_SAFETY_QUAD_A: usize = P_EG_PASSED + 8;
pub const P_SAFETY_QUAD_B: usize = P_SAFETY_QUAD_A + 1;

// Per-piece king zone attack weights (mg-only)
pub const P_MG_KNIGHT_KING_ATK: usize = P_SAFETY_QUAD_B + 1;
pub const P_MG_BISHOP_KING_ATK: usize = P_MG_KNIGHT_KING_ATK + 1;
pub const P_MG_ROOK_KING_ATK: usize = P_MG_BISHOP_KING_ATK + 1;
pub const P_MG_QUEEN_KING_ATK: usize = P_MG_ROOK_KING_ATK + 1;

// King safety scalars (mg-only)
pub const P_CASTLED_BONUS: usize = P_MG_QUEEN_KING_ATK + 1;
pub const P_PAWN_SHIELD_BONUS: usize = P_CASTLED_BONUS + 1;
pub const P_OPEN_FILE_PENALTY: usize = P_PAWN_SHIELD_BONUS + 1;
pub const P_SEMI_OPEN_PENALTY: usize = P_OPEN_FILE_PENALTY + 1;

// Split scalar bonuses — mg/eg pairs
pub const P_MG_PROTECTED_PAWN: usize = P_SEMI_OPEN_PENALTY + 1;
pub const P_EG_PROTECTED_PAWN: usize = P_MG_PROTECTED_PAWN + 1;
pub const P_MG_DOUBLED_PAWN: usize = P_EG_PROTECTED_PAWN + 1;
pub const P_EG_DOUBLED_PAWN: usize = P_MG_DOUBLED_PAWN + 1;
pub const P_MG_ISOLATED_PAWN: usize = P_EG_DOUBLED_PAWN + 1;
pub const P_EG_ISOLATED_PAWN: usize = P_MG_ISOLATED_PAWN + 1;
pub const P_MG_ROOK_OPEN_FILE: usize = P_EG_ISOLATED_PAWN + 1;
pub const P_EG_ROOK_OPEN_FILE: usize = P_MG_ROOK_OPEN_FILE + 1;
pub const P_MG_ROOK_SEMI_OPEN: usize = P_EG_ROOK_OPEN_FILE + 1;
pub const P_EG_ROOK_SEMI_OPEN: usize = P_MG_ROOK_SEMI_OPEN + 1;
pub const P_MG_MINOR_THREAT: usize = P_EG_ROOK_SEMI_OPEN + 1;
pub const P_EG_MINOR_THREAT: usize = P_MG_MINOR_THREAT + 1;
pub const P_MG_ROOK_THREAT: usize = P_EG_MINOR_THREAT + 1;
pub const P_EG_ROOK_THREAT: usize = P_MG_ROOK_THREAT + 1;
pub const P_MG_QUEEN_THREAT: usize = P_EG_ROOK_THREAT + 1;
pub const P_EG_QUEEN_THREAT: usize = P_MG_QUEEN_THREAT + 1;
pub const P_MG_ROOK_ON_QUEEN: usize = P_EG_QUEEN_THREAT + 1;
pub const P_EG_ROOK_ON_QUEEN: usize = P_MG_ROOK_ON_QUEEN + 1;
pub const P_MG_ROOK_ON_KING: usize = P_EG_ROOK_ON_QUEEN + 1;
pub const P_EG_ROOK_ON_KING: usize = P_MG_ROOK_ON_KING + 1;
pub const P_MG_QUEEN_ON_KING: usize = P_EG_ROOK_ON_KING + 1;
pub const P_EG_QUEEN_ON_KING: usize = P_MG_QUEEN_ON_KING + 1;
pub const P_MG_BAD_BISHOP: usize = P_EG_QUEEN_ON_KING + 1;
pub const P_EG_BAD_BISHOP: usize = P_MG_BAD_BISHOP + 1;
pub const P_MG_BISHOP_ON_QUEEN: usize = P_EG_BAD_BISHOP + 1;
pub const P_EG_BISHOP_ON_QUEEN: usize = P_MG_BISHOP_ON_QUEEN + 1;
pub const P_MG_BISHOP_ON_KING: usize = P_EG_BISHOP_ON_QUEEN + 1;
pub const P_EG_BISHOP_ON_KING: usize = P_MG_BISHOP_ON_KING + 1;
pub const P_MG_HANGING_PIECE: usize = P_EG_BISHOP_ON_KING + 1;
pub const P_EG_HANGING_PIECE: usize = P_MG_HANGING_PIECE + 1;
pub const P_MG_ATK_BY_PAWN: usize = P_EG_HANGING_PIECE + 1;
pub const P_EG_ATK_BY_PAWN: usize = P_MG_ATK_BY_PAWN + 1;
pub const P_MG_ATK_BY_MINOR: usize = P_EG_ATK_BY_PAWN + 1;
pub const P_EG_ATK_BY_MINOR: usize = P_MG_ATK_BY_MINOR + 1;
pub const P_MG_ATK_BY_ROOK: usize = P_EG_ATK_BY_MINOR + 1;
pub const P_EG_ATK_BY_ROOK: usize = P_MG_ATK_BY_ROOK + 1;
pub const P_MG_DEFENDED_BY_PAWN: usize = P_EG_ATK_BY_ROOK + 1;
pub const P_EG_DEFENDED_BY_PAWN: usize = P_MG_DEFENDED_BY_PAWN + 1;
pub const P_MG_KNIGHT_OUTPOST: usize = P_EG_DEFENDED_BY_PAWN + 1;
pub const P_EG_KNIGHT_OUTPOST: usize = P_MG_KNIGHT_OUTPOST + 1;
pub const P_MG_BISHOP_PAIR: usize = P_EG_KNIGHT_OUTPOST + 1;
pub const P_EG_BISHOP_PAIR: usize = P_MG_BISHOP_PAIR + 1;
pub const P_MG_SPACE_PER_SQ: usize = P_EG_BISHOP_PAIR + 1;
pub const P_EG_SPACE_PER_SQ: usize = P_MG_SPACE_PER_SQ + 1;
pub const P_MG_CENTER_CTRL: usize = P_EG_SPACE_PER_SQ + 1;
pub const P_EG_CENTER_CTRL: usize = P_MG_CENTER_CTRL + 1;
pub const P_MG_EXTENDED_CENTER: usize = P_EG_CENTER_CTRL + 1;
pub const P_EG_EXTENDED_CENTER: usize = P_MG_EXTENDED_CENTER + 1;
pub const P_MG_EXCHANGE_AVOIDANCE: usize = P_EG_EXTENDED_CENTER + 1;
pub const P_EG_EXCHANGE_AVOIDANCE: usize = P_MG_EXCHANGE_AVOIDANCE + 1;

// Per-piece-type trapped piece penalties (mg/eg)
pub const P_MG_TRAPPED_KNIGHT: usize = P_EG_EXCHANGE_AVOIDANCE + 1;
pub const P_EG_TRAPPED_KNIGHT: usize = P_MG_TRAPPED_KNIGHT + 1;
pub const P_MG_TRAPPED_BISHOP: usize = P_EG_TRAPPED_KNIGHT + 1;
pub const P_EG_TRAPPED_BISHOP: usize = P_MG_TRAPPED_BISHOP + 1;
pub const P_MG_TRAPPED_ROOK: usize = P_EG_TRAPPED_BISHOP + 1;
pub const P_EG_TRAPPED_ROOK: usize = P_MG_TRAPPED_ROOK + 1;

// Remaining single-phase params
pub const P_ROOK_7TH_BONUS: usize = P_EG_TRAPPED_ROOK + 1;
pub const P_ROOK_PASSER_BONUS: usize = P_ROOK_7TH_BONUS + 1;
pub const P_KING_PAWN_PROXIMITY: usize = P_ROOK_PASSER_BONUS + 1;
pub const P_KING_FAR_PAWN: usize = P_KING_PAWN_PROXIMITY + 1;
pub const P_KING_CENTRALIZATION: usize = P_KING_FAR_PAWN + 1;
pub const P_MOPUP_EDGE: usize = P_KING_CENTRALIZATION + 1;
pub const P_MOPUP_PROXIMITY: usize = P_MOPUP_EDGE + 1;
pub const P_RULE_OF_SQUARE: usize = P_MOPUP_PROXIMITY + 1;
pub const P_PAWN_STORM: usize = P_RULE_OF_SQUARE + 1;
pub const P_KING_ZONE_ATTACK: usize = P_PAWN_STORM + 1;
pub const P_KING_DEFENDER: usize = P_KING_ZONE_ATTACK + 1;
pub const P_TEMPO_BONUS: usize = P_KING_DEFENDER + 1;
pub const P_MG_PAWN_ADVANCE_SPACE: usize = P_TEMPO_BONUS + 1;
pub const P_EG_PAWN_ADVANCE_SPACE: usize = P_MG_PAWN_ADVANCE_SPACE + 1;

pub const NUM_PARAMS: usize = P_EG_PAWN_ADVANCE_SPACE + 1;

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

    for (0..9) |i| buf[P_MG_KNIGHT_MOB + i] = mg_knight_mobility[i];
    for (0..14) |i| buf[P_MG_BISHOP_MOB + i] = mg_bishop_mobility[i];
    for (0..15) |i| buf[P_MG_ROOK_MOB + i] = mg_rook_mobility[i];
    for (0..28) |i| buf[P_MG_QUEEN_MOB + i] = mg_queen_mobility[i];
    for (0..9) |i| buf[P_EG_KNIGHT_MOB + i] = eg_knight_mobility[i];
    for (0..14) |i| buf[P_EG_BISHOP_MOB + i] = eg_bishop_mobility[i];
    for (0..15) |i| buf[P_EG_ROOK_MOB + i] = eg_rook_mobility[i];
    for (0..28) |i| buf[P_EG_QUEEN_MOB + i] = eg_queen_mobility[i];

    for (0..8) |i| buf[P_MG_PASSED + i] = mg_passed_bonus[i];
    for (0..8) |i| buf[P_EG_PASSED + i] = passed_pawn_bonus[i];

    buf[P_SAFETY_QUAD_A] = safety_quadratic_a;
    buf[P_SAFETY_QUAD_B] = safety_quadratic_b;

    buf[P_MG_KNIGHT_KING_ATK] = mg_knight_king_atk;
    buf[P_MG_BISHOP_KING_ATK] = mg_bishop_king_atk;
    buf[P_MG_ROOK_KING_ATK] = mg_rook_king_atk;
    buf[P_MG_QUEEN_KING_ATK] = mg_queen_king_atk;

    buf[P_CASTLED_BONUS] = castled_bonus;
    buf[P_PAWN_SHIELD_BONUS] = pawn_shield_bonus;
    buf[P_OPEN_FILE_PENALTY] = open_file_penalty;
    buf[P_SEMI_OPEN_PENALTY] = semi_open_penalty;

    buf[P_MG_PROTECTED_PAWN] = mg_protected_pawn;
    buf[P_EG_PROTECTED_PAWN] = eg_protected_pawn;
    buf[P_MG_DOUBLED_PAWN] = mg_doubled_pawn;
    buf[P_EG_DOUBLED_PAWN] = eg_doubled_pawn;
    buf[P_MG_ISOLATED_PAWN] = mg_isolated_pawn;
    buf[P_EG_ISOLATED_PAWN] = eg_isolated_pawn;
    buf[P_MG_ROOK_OPEN_FILE] = mg_rook_open_file;
    buf[P_EG_ROOK_OPEN_FILE] = eg_rook_open_file;
    buf[P_MG_ROOK_SEMI_OPEN] = mg_rook_semi_open;
    buf[P_EG_ROOK_SEMI_OPEN] = eg_rook_semi_open;
    buf[P_MG_MINOR_THREAT] = mg_minor_threat;
    buf[P_EG_MINOR_THREAT] = eg_minor_threat;
    buf[P_MG_ROOK_THREAT] = mg_rook_threat;
    buf[P_EG_ROOK_THREAT] = eg_rook_threat;
    buf[P_MG_QUEEN_THREAT] = mg_queen_threat;
    buf[P_EG_QUEEN_THREAT] = eg_queen_threat;
    buf[P_MG_ROOK_ON_QUEEN] = mg_rook_on_queen;
    buf[P_EG_ROOK_ON_QUEEN] = eg_rook_on_queen;
    buf[P_MG_ROOK_ON_KING] = mg_rook_on_king;
    buf[P_EG_ROOK_ON_KING] = eg_rook_on_king;
    buf[P_MG_QUEEN_ON_KING] = mg_queen_on_king;
    buf[P_EG_QUEEN_ON_KING] = eg_queen_on_king;
    buf[P_MG_BAD_BISHOP] = mg_bad_bishop;
    buf[P_EG_BAD_BISHOP] = eg_bad_bishop;
    buf[P_MG_BISHOP_ON_QUEEN] = mg_bishop_on_queen;
    buf[P_EG_BISHOP_ON_QUEEN] = eg_bishop_on_queen;
    buf[P_MG_BISHOP_ON_KING] = mg_bishop_on_king;
    buf[P_EG_BISHOP_ON_KING] = eg_bishop_on_king;
    buf[P_MG_HANGING_PIECE] = mg_hanging_piece;
    buf[P_EG_HANGING_PIECE] = eg_hanging_piece;
    buf[P_MG_ATK_BY_PAWN] = mg_atk_by_pawn;
    buf[P_EG_ATK_BY_PAWN] = eg_atk_by_pawn;
    buf[P_MG_ATK_BY_MINOR] = mg_atk_by_minor;
    buf[P_EG_ATK_BY_MINOR] = eg_atk_by_minor;
    buf[P_MG_ATK_BY_ROOK] = mg_atk_by_rook;
    buf[P_EG_ATK_BY_ROOK] = eg_atk_by_rook;
    buf[P_MG_DEFENDED_BY_PAWN] = mg_defended_by_pawn;
    buf[P_EG_DEFENDED_BY_PAWN] = eg_defended_by_pawn;
    buf[P_MG_KNIGHT_OUTPOST] = mg_knight_outpost;
    buf[P_EG_KNIGHT_OUTPOST] = eg_knight_outpost;
    buf[P_MG_BISHOP_PAIR] = mg_bishop_pair;
    buf[P_EG_BISHOP_PAIR] = eg_bishop_pair;
    buf[P_MG_SPACE_PER_SQ] = mg_space_per_sq;
    buf[P_EG_SPACE_PER_SQ] = eg_space_per_sq;
    buf[P_MG_CENTER_CTRL] = mg_center_ctrl;
    buf[P_EG_CENTER_CTRL] = eg_center_ctrl;
    buf[P_MG_EXTENDED_CENTER] = mg_extended_center;
    buf[P_EG_EXTENDED_CENTER] = eg_extended_center;
    buf[P_MG_EXCHANGE_AVOIDANCE] = mg_exchange_avoidance;
    buf[P_EG_EXCHANGE_AVOIDANCE] = eg_exchange_avoidance;

    buf[P_MG_TRAPPED_KNIGHT] = mg_trapped_knight;
    buf[P_EG_TRAPPED_KNIGHT] = eg_trapped_knight;
    buf[P_MG_TRAPPED_BISHOP] = mg_trapped_bishop;
    buf[P_EG_TRAPPED_BISHOP] = eg_trapped_bishop;
    buf[P_MG_TRAPPED_ROOK] = mg_trapped_rook;
    buf[P_EG_TRAPPED_ROOK] = eg_trapped_rook;

    buf[P_ROOK_7TH_BONUS] = rook_on_7th_bonus;
    buf[P_ROOK_PASSER_BONUS] = rook_behind_passer_bonus;
    buf[P_KING_PAWN_PROXIMITY] = king_pawn_proximity;
    buf[P_KING_FAR_PAWN] = king_far_pawn_penalty;
    buf[P_KING_CENTRALIZATION] = king_centralization_weight;
    buf[P_MOPUP_EDGE] = mopup_edge_weight;
    buf[P_MOPUP_PROXIMITY] = mopup_proximity_weight;
    buf[P_RULE_OF_SQUARE] = rule_of_square_bonus;
    buf[P_PAWN_STORM] = pawn_storm_weight;
    buf[P_KING_ZONE_ATTACK] = king_zone_attack_weight;
    buf[P_KING_DEFENDER] = king_defender_bonus;
    buf[P_TEMPO_BONUS] = tempo_bonus;
    buf[P_MG_PAWN_ADVANCE_SPACE] = mg_pawn_advance_space;
    buf[P_EG_PAWN_ADVANCE_SPACE] = eg_pawn_advance_space;
}

/// Deserialize flat i32 buffer back into tunable globals.
pub fn importParams(buf: []const i32) void {
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

    for (0..9) |i| mg_knight_mobility[i] = buf[P_MG_KNIGHT_MOB + i];
    for (0..14) |i| mg_bishop_mobility[i] = buf[P_MG_BISHOP_MOB + i];
    for (0..15) |i| mg_rook_mobility[i] = buf[P_MG_ROOK_MOB + i];
    for (0..28) |i| mg_queen_mobility[i] = buf[P_MG_QUEEN_MOB + i];
    for (0..9) |i| eg_knight_mobility[i] = buf[P_EG_KNIGHT_MOB + i];
    for (0..14) |i| eg_bishop_mobility[i] = buf[P_EG_BISHOP_MOB + i];
    for (0..15) |i| eg_rook_mobility[i] = buf[P_EG_ROOK_MOB + i];
    for (0..28) |i| eg_queen_mobility[i] = buf[P_EG_QUEEN_MOB + i];

    for (0..8) |i| mg_passed_bonus[i] = buf[P_MG_PASSED + i];
    for (0..8) |i| passed_pawn_bonus[i] = buf[P_EG_PASSED + i];

    safety_quadratic_a = buf[P_SAFETY_QUAD_A];
    safety_quadratic_b = buf[P_SAFETY_QUAD_B];

    mg_knight_king_atk = buf[P_MG_KNIGHT_KING_ATK];
    mg_bishop_king_atk = buf[P_MG_BISHOP_KING_ATK];
    mg_rook_king_atk = buf[P_MG_ROOK_KING_ATK];
    mg_queen_king_atk = buf[P_MG_QUEEN_KING_ATK];

    castled_bonus = buf[P_CASTLED_BONUS];
    pawn_shield_bonus = buf[P_PAWN_SHIELD_BONUS];
    open_file_penalty = buf[P_OPEN_FILE_PENALTY];
    semi_open_penalty = buf[P_SEMI_OPEN_PENALTY];

    mg_protected_pawn = buf[P_MG_PROTECTED_PAWN];
    eg_protected_pawn = buf[P_EG_PROTECTED_PAWN];
    mg_doubled_pawn = buf[P_MG_DOUBLED_PAWN];
    eg_doubled_pawn = buf[P_EG_DOUBLED_PAWN];
    mg_isolated_pawn = buf[P_MG_ISOLATED_PAWN];
    eg_isolated_pawn = buf[P_EG_ISOLATED_PAWN];
    mg_rook_open_file = buf[P_MG_ROOK_OPEN_FILE];
    eg_rook_open_file = buf[P_EG_ROOK_OPEN_FILE];
    mg_rook_semi_open = buf[P_MG_ROOK_SEMI_OPEN];
    eg_rook_semi_open = buf[P_EG_ROOK_SEMI_OPEN];
    mg_minor_threat = buf[P_MG_MINOR_THREAT];
    eg_minor_threat = buf[P_EG_MINOR_THREAT];
    mg_rook_threat = buf[P_MG_ROOK_THREAT];
    eg_rook_threat = buf[P_EG_ROOK_THREAT];
    mg_queen_threat = buf[P_MG_QUEEN_THREAT];
    eg_queen_threat = buf[P_EG_QUEEN_THREAT];
    mg_rook_on_queen = buf[P_MG_ROOK_ON_QUEEN];
    eg_rook_on_queen = buf[P_EG_ROOK_ON_QUEEN];
    mg_rook_on_king = buf[P_MG_ROOK_ON_KING];
    eg_rook_on_king = buf[P_EG_ROOK_ON_KING];
    mg_queen_on_king = buf[P_MG_QUEEN_ON_KING];
    eg_queen_on_king = buf[P_EG_QUEEN_ON_KING];
    mg_bad_bishop = buf[P_MG_BAD_BISHOP];
    eg_bad_bishop = buf[P_EG_BAD_BISHOP];
    mg_bishop_on_queen = buf[P_MG_BISHOP_ON_QUEEN];
    eg_bishop_on_queen = buf[P_EG_BISHOP_ON_QUEEN];
    mg_bishop_on_king = buf[P_MG_BISHOP_ON_KING];
    eg_bishop_on_king = buf[P_EG_BISHOP_ON_KING];
    mg_hanging_piece = buf[P_MG_HANGING_PIECE];
    eg_hanging_piece = buf[P_EG_HANGING_PIECE];
    mg_atk_by_pawn = buf[P_MG_ATK_BY_PAWN];
    eg_atk_by_pawn = buf[P_EG_ATK_BY_PAWN];
    mg_atk_by_minor = buf[P_MG_ATK_BY_MINOR];
    eg_atk_by_minor = buf[P_EG_ATK_BY_MINOR];
    mg_atk_by_rook = buf[P_MG_ATK_BY_ROOK];
    eg_atk_by_rook = buf[P_EG_ATK_BY_ROOK];
    mg_defended_by_pawn = buf[P_MG_DEFENDED_BY_PAWN];
    eg_defended_by_pawn = buf[P_EG_DEFENDED_BY_PAWN];
    mg_knight_outpost = buf[P_MG_KNIGHT_OUTPOST];
    eg_knight_outpost = buf[P_EG_KNIGHT_OUTPOST];
    mg_bishop_pair = buf[P_MG_BISHOP_PAIR];
    eg_bishop_pair = buf[P_EG_BISHOP_PAIR];
    mg_space_per_sq = buf[P_MG_SPACE_PER_SQ];
    eg_space_per_sq = buf[P_EG_SPACE_PER_SQ];
    mg_center_ctrl = buf[P_MG_CENTER_CTRL];
    eg_center_ctrl = buf[P_EG_CENTER_CTRL];
    mg_extended_center = buf[P_MG_EXTENDED_CENTER];
    eg_extended_center = buf[P_EG_EXTENDED_CENTER];
    mg_exchange_avoidance = buf[P_MG_EXCHANGE_AVOIDANCE];
    eg_exchange_avoidance = buf[P_EG_EXCHANGE_AVOIDANCE];

    mg_trapped_knight = buf[P_MG_TRAPPED_KNIGHT];
    eg_trapped_knight = buf[P_EG_TRAPPED_KNIGHT];
    mg_trapped_bishop = buf[P_MG_TRAPPED_BISHOP];
    eg_trapped_bishop = buf[P_EG_TRAPPED_BISHOP];
    mg_trapped_rook = buf[P_MG_TRAPPED_ROOK];
    eg_trapped_rook = buf[P_EG_TRAPPED_ROOK];

    rook_on_7th_bonus = buf[P_ROOK_7TH_BONUS];
    rook_behind_passer_bonus = buf[P_ROOK_PASSER_BONUS];
    king_pawn_proximity = buf[P_KING_PAWN_PROXIMITY];
    king_far_pawn_penalty = buf[P_KING_FAR_PAWN];
    king_centralization_weight = buf[P_KING_CENTRALIZATION];
    mopup_edge_weight = buf[P_MOPUP_EDGE];
    mopup_proximity_weight = buf[P_MOPUP_PROXIMITY];
    rule_of_square_bonus = buf[P_RULE_OF_SQUARE];
    pawn_storm_weight = buf[P_PAWN_STORM];
    king_zone_attack_weight = buf[P_KING_ZONE_ATTACK];
    king_defender_bonus = buf[P_KING_DEFENDER];
    tempo_bonus = buf[P_TEMPO_BONUS];
    mg_pawn_advance_space = buf[P_MG_PAWN_ADVANCE_SPACE];
    eg_pawn_advance_space = buf[P_EG_PAWN_ADVANCE_SPACE];
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
        mg_c[P_MG_BISHOP_PAIR] += 1.0;
        eg_c[P_EG_BISHOP_PAIR] += 1.0;
    }
    if (bb_cnt >= 2) {
        mg_c[P_MG_BISHOP_PAIR] -= 1.0;
        eg_c[P_EG_BISHOP_PAIR] -= 1.0;
    }

    // Endgame features — always computed, phase interpolation handles weighting
    coeffsEndgame(board, &eg_c);

    coeffsThreats(board, .White, cache, &mg_c, &eg_c, 1.0);
    coeffsThreats(board, .Black, cache, &mg_c, &eg_c, -1.0);

    coeffsSpace(board, .White, cache, &mg_c, &eg_c, 1.0);
    coeffsSpace(board, .Black, cache, &mg_c, &eg_c, -1.0);

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

    // Rule of square coefficients (eg only, self-gates to pawn-only endgames)
    coeffsRuleOfSquare(board, .White, &eg_c, 1.0);
    coeffsRuleOfSquare(board, .Black, &eg_c, -1.0);

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

    var attacker_count: f64 = 0;

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

    // Knights
    var bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);

        const rank = @divTrunc(sq, 8);
        const relative_rank = if (color == .White) rank else 7 - rank;
        const is_supported = (our_pawn_attacks & (@as(u64, 1) << @intCast(sq))) != 0;
        if (is_supported and relative_rank >= 3 and relative_rank <= 5) {
            mg_c[P_MG_KNIGHT_OUTPOST] += sign;
            eg_c[P_EG_KNIGHT_OUTPOST] += sign;
        }

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_c[P_MG_MINOR_THREAT] -= sign;
            eg_c[P_EG_MINOR_THREAT] -= sign;
        }

        coeffsMobility(sq, .Knight, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        const attack_mask = move_gen.knights[@as(usize, @intCast(sq))];
        if (attack_mask & opp_king_zone != 0) {
            mg_c[P_MG_KNIGHT_KING_ATK] += sign;
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
            mg_c[P_MG_MINOR_THREAT] -= sign;
            eg_c[P_EG_MINOR_THREAT] -= sign;
        }

        const bishop_mask: u64 = move_gen.getBishopAttacks(sq, occupancy);
        const blocking_pawns: i32 = @as(i32, @intCast(@popCount(our_pawns & bishop_mask)));
        if (blocking_pawns > 1) {
            const count_f: f64 = @floatFromInt(blocking_pawns - 1);
            mg_c[P_MG_BAD_BISHOP] -= sign * count_f;
            eg_c[P_EG_BAD_BISHOP] -= sign * count_f;
        }

        if (bishop_mask & opp_queen_bb != 0) {
            mg_c[P_MG_BISHOP_ON_QUEEN] += sign;
            eg_c[P_EG_BISHOP_ON_QUEEN] += sign;
        }
        if (bishop_mask & opp_king_bb != 0) {
            mg_c[P_MG_BISHOP_ON_KING] += sign;
            eg_c[P_EG_BISHOP_ON_KING] += sign;
        }

        coeffsMobility(sq, .Bishop, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        const attack_mask = move_gen.getBishopAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            mg_c[P_MG_BISHOP_KING_ATK] += sign;
            attacker_count += 1;
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
                mg_c[P_MG_ROOK_OPEN_FILE] += sign;
                eg_c[P_EG_ROOK_OPEN_FILE] += sign;
            } else {
                mg_c[P_MG_ROOK_SEMI_OPEN] += sign;
                eg_c[P_EG_ROOK_SEMI_OPEN] += sign;
            }
        }

        const sq_bb: u64 = @as(u64, 1) << @intCast(sq);
        if ((sq_bb & opp_pawn_attacks) != 0) {
            mg_c[P_MG_ROOK_THREAT] -= sign;
            eg_c[P_EG_ROOK_THREAT] -= sign;
        }

        if (file_mask & opp_queen_bb != 0) {
            mg_c[P_MG_ROOK_ON_QUEEN] += sign;
            eg_c[P_EG_ROOK_ON_QUEEN] += sign;
        }
        if (file_mask & opp_king_bb != 0) {
            mg_c[P_MG_ROOK_ON_KING] += sign;
            eg_c[P_EG_ROOK_ON_KING] += sign;
        }

        coeffsMobility(sq, .Rook, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        const rook_attack_mask = move_gen.getRookAttacks(sq, occupancy);
        if (rook_attack_mask & opp_king_zone != 0) {
            mg_c[P_MG_ROOK_KING_ATK] += sign;
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
            mg_c[P_MG_QUEEN_THREAT] -= sign;
            eg_c[P_EG_QUEEN_THREAT] -= sign;
        }

        const file = @mod(sq, 8);
        const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
        if (file_mask & opp_king_bb != 0) {
            mg_c[P_MG_QUEEN_ON_KING] += sign;
            eg_c[P_EG_QUEEN_ON_KING] += sign;
        }

        coeffsMobility(sq, .Queen, board, move_gen, opp_pawn_attacks, color, mg_c, eg_c, sign);

        const attack_mask = move_gen.getQueenAttacks(sq, occupancy);
        if (attack_mask & opp_king_zone != 0) {
            mg_c[P_MG_QUEEN_KING_ATK] += sign;
            attacker_count += 1;
        }

        brd.popBit(&bb, sq);
    }

    // Quadratic king safety coefficients
    if (attacker_count >= 1) {
        mg_c[P_SAFETY_QUAD_A] += sign * attacker_count * attacker_count;
        mg_c[P_SAFETY_QUAD_B] += sign * attacker_count;
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
            const idx = if (count < mg_knight_mobility.len) count else mg_knight_mobility.len - 1;
            mg_c[P_MG_KNIGHT_MOB + idx] += sign;
            eg_c[P_EG_KNIGHT_MOB + idx] += sign;
        },
        .Bishop => {
            const idx = if (count < mg_bishop_mobility.len) count else mg_bishop_mobility.len - 1;
            mg_c[P_MG_BISHOP_MOB + idx] += sign;
            eg_c[P_EG_BISHOP_MOB + idx] += sign;
        },
        .Rook => {
            const idx = if (count < mg_rook_mobility.len) count else mg_rook_mobility.len - 1;
            mg_c[P_MG_ROOK_MOB + idx] += sign;
            eg_c[P_EG_ROOK_MOB + idx] += sign;
        },
        .Queen => {
            const idx = if (count < mg_queen_mobility.len) count else mg_queen_mobility.len - 1;
            mg_c[P_MG_QUEEN_MOB + idx] += sign;
            eg_c[P_EG_QUEEN_MOB + idx] += sign;
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
    var coeff_penalized_files: u8 = 0;
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
            mg_c[P_MG_PROTECTED_PAWN] += sign;
            eg_c[P_EG_PROTECTED_PAWN] += sign;
        }

        if ((our_pawns & adjacent_files) == 0) {
            mg_c[P_MG_ISOLATED_PAWN] += sign;
            eg_c[P_EG_ISOLATED_PAWN] += sign;
        }

        // Doubled pawn: penalize per-file (extra pawns), not per-pawn
        const file_bit = @as(u8, 1) << @intCast(file);
        if (file_counts[file] > 1 and (coeff_penalized_files & file_bit) == 0) {
            const extra: f64 = @floatFromInt(@as(i32, file_counts[file]) - 1);
            mg_c[P_MG_DOUBLED_PAWN] += sign * extra;
            eg_c[P_EG_DOUBLED_PAWN] += sign * extra;
            coeff_penalized_files |= file_bit;
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
    if (@abs(material_diff) > 400) {
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
                    mg_c[P_MG_HANGING_PIECE] -= sign;
                    eg_c[P_EG_HANGING_PIECE] -= sign;
                    mg_c[P_MG_ATK_BY_PAWN] -= sign;
                    eg_c[P_EG_ATK_BY_PAWN] -= sign;
                } else {
                    mg_c[P_MG_DEFENDED_BY_PAWN] -= sign;
                    eg_c[P_EG_DEFENDED_BY_PAWN] -= sign;
                }
            }

            // Attacked by minor (only rooks/queens)
            if (((opp_knight_attacks | opp_bishop_attacks) & sq_mask) != 0) {
                if (!is_defended and (piece == .Rook or piece == .Queen)) {
                    mg_c[P_MG_ATK_BY_MINOR] -= sign;
                    eg_c[P_EG_ATK_BY_MINOR] -= sign;
                }
            }

            // Attacked by rook (only queens)
            if ((opp_rook_attacks & sq_mask) != 0 and piece == .Queen) {
                if (!is_defended) {
                    mg_c[P_MG_ATK_BY_ROOK] -= sign;
                    eg_c[P_EG_ATK_BY_ROOK] -= sign;
                }
            }

            brd.popBit(&piece_bb, sq);
        }
    }
}

fn coeffsSpace(
    board: *brd.Board,
    color: brd.Color,
    cache: AttackCache,
    mg_c: []f64,
    eg_c: []f64,
    sign: f64,
) void {
    const c_idx = @intFromEnum(color);
    const our_half: u64 = if (color == .White) 0x00000000FFFFFFFF else 0xFFFFFFFF00000000;
    const center: u64 = 0x0000001818000000;
    const extended_center: u64 = 0x00003C3C3C3C0000;

    // Pawn advance space coefficient (now tunable)
    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    var pawn_bb = our_pawns;
    while (pawn_bb != 0) {
        const sq = brd.getLSB(pawn_bb);
        const rank = @divTrunc(sq, 8);
        const advance_bonus: i32 = if (color == .White)
            @as(i32, @intCast(rank)) - 1
        else
            @as(i32, @intCast(6 - rank));
        if (advance_bonus > 0) {
            const ab: f64 = @floatFromInt(advance_bonus);
            mg_c[P_MG_PAWN_ADVANCE_SPACE] += sign * ab;
            eg_c[P_EG_PAWN_ADVANCE_SPACE] += sign * ab;
        }
        brd.popBit(&pawn_bb, sq);
    }

    var our_attacks: u64 = undefined;
    if (color == .White) {
        our_attacks = cache.our_knight_attacks | cache.our_bishop_attacks | cache.our_rook_attacks | cache.our_queen_attacks | cache.our_defenses;
    } else {
        our_attacks = cache.opp_knight_attacks | cache.opp_bishop_attacks | cache.opp_rook_attacks | cache.opp_queen_attacks | cache.opp_defenses;
    }

    const controlled: f64 = @floatFromInt(@popCount(our_attacks & our_half));
    mg_c[P_MG_SPACE_PER_SQ] += sign * controlled;
    eg_c[P_EG_SPACE_PER_SQ] += sign * controlled;

    const center_ctrl: f64 = @floatFromInt(@popCount(our_attacks & center));
    mg_c[P_MG_CENTER_CTRL] += sign * center_ctrl;
    eg_c[P_EG_CENTER_CTRL] += sign * center_ctrl;

    const ext_ctrl: f64 = @floatFromInt(@popCount(our_attacks & extended_center));
    mg_c[P_MG_EXTENDED_CENTER] += sign * ext_ctrl;
    eg_c[P_EG_EXTENDED_CENTER] += sign * ext_ctrl;
}

fn coeffsExchangeAvoidance(board: *brd.Board, mg_c: []f64, eg_c: []f64) void {
    const white_mat = countMaterial(board, brd.Color.White);
    const black_mat = countMaterial(board, brd.Color.Black);
    const diff = white_mat - black_mat;
    const abs_diff = @abs(diff);
    if (abs_diff < 50) return;

    // Smooth ramp matching eval: scales from 0 at 50cp to full at 250cp
    const ramp: f64 = @floatFromInt(@min(abs_diff - 50, @as(i32, 200)));
    const scale: f64 = ramp / 200.0;

    const white_pieces = @popCount(board.color_bb[@intFromEnum(brd.Color.White)]);
    const black_pieces = @popCount(board.color_bb[@intFromEnum(brd.Color.Black)]);
    const total_pieces: f64 = @floatFromInt(white_pieces + black_pieces);

    const sign: f64 = if (diff > 0) 1.0 else -1.0;
    mg_c[P_MG_EXCHANGE_AVOIDANCE] += sign * total_pieces * scale;
    eg_c[P_EG_EXCHANGE_AVOIDANCE] += sign * total_pieces * scale;
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
            mg_c[P_MG_TRAPPED_KNIGHT] -= sign;
            eg_c[P_EG_TRAPPED_KNIGHT] -= sign;
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
            mg_c[P_MG_TRAPPED_BISHOP] -= sign;
            eg_c[P_EG_TRAPPED_BISHOP] -= sign;
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
            mg_c[P_MG_TRAPPED_ROOK] -= sign;
            eg_c[P_EG_TRAPPED_ROOK] -= sign;
        }
        brd.popBit(&bb, sq);
    }
}
