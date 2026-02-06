const brd = @import("board");
const std = @import("std");
const mvs = @import("moves");

pub const mate_score: i32 = 888888;

const total_phase: i32 = 24;
const pawn_phase: i32 = 0;
const knight_phase: i32 = 1;
const bishop_phase: i32 = 1;
const rook_phase: i32 = 2;
const queen_phase: i32 = 4;

const mg_pawn: i32 = 82;   const eg_pawn: i32 = 94;
const mg_knight: i32 = 337; const eg_knight: i32 = 281;
const mg_bishop: i32 = 365; const eg_bishop: i32 = 297;
const mg_rook: i32 = 477;   const eg_rook: i32 = 512;
const mg_queen: i32 = 1025; const eg_queen: i32 = 936;
const mg_king: i32 = 0;    const eg_king: i32 = 0;

// King Safety Bonuses
const castled_bonus: i32 = 50;           // Bonus for having castled
const pawn_shield_bonus: i32 = 15;       // Per pawn in front of king
const open_file_penalty: i32 = -30;      // Penalty for open file near king
const semi_open_penalty: i32 = -15;      // Penalty for semi-open file near king

// Endgame Bonuses
const rook_on_7th_bonus: i32 = 20;       // Rook on 7th rank in endgame
const rook_behind_passer_bonus: i32 = 25; // Rook behind passed pawn
const king_pawn_proximity: i32 = 4;      // King close to passed pawns in endgame

// Pawn Structure Bonuses
const passed_pawn_bonus = [8]i32{ 0, 10, 20, 35, 60, 100, 150, 0 }; // By rank (endgame)
const mg_passed_bonus = [8]i32{ 0, 5, 10, 15, 25, 40, 60, 0 };      // Middlegame passed pawn
const protected_pawn_bonus: i32 = 8;     // Pawn protected by another pawn
const doubled_pawn_penalty: i32 = -10;   // Pawns on same file
const isolated_pawn_penalty: i32 = -12;  // No friendly pawns on adjacent files

// Pawn Table (incentivize pushing)
const mg_pawn_table = [64]i32{
    0,   0,   0,   0,   0,   0,   0,   0,
    98, 134,  61,  95,  68, 126,  34, -11,
    -6,   7,  26,  31,  65,  56,  25, -20,
    -14,  13,   6,  21,  23,  12,  17, -23,
    -27,  -2,  -5,  12,  17,   6,  10, -25,
    -26,  -4,  -4, -10,   3,   3,  33, -12,
    -35,  -1, -20, -23, -15,  24,  38, -22,
    0,   0,   0,   0,   0,   0,   0,   0,
};
const eg_pawn_table = [64]i32{
    0,   0,   0,   0,   0,   0,   0,   0,
    178, 173, 158, 134, 147, 132, 165, 187,
    94, 100,  85,  67,  56,  53,  82,  84,
    32,  24,  13,   5,  -2,   4,  17,  17,
    13,   9,  -3,  -7,  -7,  -8,   3,  -1,
    4,   7,  -6,   1,   0,  -5,  -1,  -8,
    13,   8,   8,  10,  13,   0,   2,  -7,
    0,   0,   0,   0,   0,   0,   0,   0,
};

// Knight Table (incentivize center)
const mg_knight_table = [64]i32{
    -167, -89, -34, -49,  61, -97, -15, -107,
    -73, -41,  72,  36,  23,  62,   7, -17,
    -47,  60,  37,  65,  84, 129,  73,  44,
    -9,  17,  19,  53,  37,  69,  18,  22,
    -13,   4,  16,  13,  28,  19,  21,  -8,
    -23,  -9,  12,  10,  19,  17,  25, -16,
    -29, -53, -12,  -3,  -1,  18, -14, -19,
    -105, -21, -58, -33, -17, -28, -19, -23,
};
const eg_knight_table = [64]i32{
    -58, -38, -13, -28, -31, -27, -63, -99,
    -25,  -8, -25,  -2,  -9, -25, -24, -52,
    -24, -20,  10,   9,  -1,  -9, -19, -41,
    -17,   3,  22,  22,  22,  11,   8, -18,
    -18,  -6,  16,  25,  16,  17,   4, -18,
    -23,  -3,  -1,  15,  10,  -3, -20, -22,
    -42, -20, -10,  -5,  -2, -11, -28, -43,
    -61, -42, -31, -24, -19, -26, -38, -68,
};

// Bishop Table (avoid corners, control diagonals)
const mg_bishop_table = [64]i32{
    -29,   4, -82, -37, -25, -42,   7,  -8,
    -26,  16, -18, -13,  30,  59,  18, -47,
    -16,  37,  43,  40,  35,  50,  37,  -2,
    -4,   5,  19,  50,  37,  37,   7,  -2,
    -6,  13,  13,  26,  34,  12,  10,   4,
    0,  15,  15,  15,  14,  27,  18,  10,
    4,  15,  16,   0,   7,  21,  33,   1,
    -33,  -3, -14, -21, -13, -12, -39, -21,
};
const eg_bishop_table = [64]i32{
    -14, -21, -11,  -8, -7,  -9, -17, -24,
    -8,  -4,   7, -12, -3, -13,  -4, -14,
    -4,   0,  11,  14, 12,   5,   6,  -6,
    -3,   3,  24,  15,  8,  -4,  20,   6,
    4,   5,  16,   4,  3,  -6,  10,   4,
    4,   0,   4,  -6, -4,  -7,   4,   9,
    -7,  -5, -12,  -1, -6,  -2,  -6,   1,
    -17, -20, -12,  -5, -7, -12, -18, -20,
};

// Rook Table
const mg_rook_table = [64]i32{
    32,  42,  32,  51, 63,  9,  31,  43,
    27,  32,  58,  62, 80, 67,  26,  44,
    -5,  19,  26,  36, 17, 45,  61,  16,
    -24, -11,   7,  26, 24, 35,  -8, -20,
    -36, -26, -12,  -1,  9, -7,   6, -23,
    -45, -25, -16, -17,  3,  0,  -5, -33,
    -44, -16, -20,  -9, -1, 11,  -6, -71,
    -19, -13,   1,  17, 16,  7, -37, -26,
};
const eg_rook_table = [64]i32{
    13,  10,  18,  15, 12,  12,   8,   5,
    11,  13,  13,  11, -3,   3,   8,   3,
    7,   7,   7,   5,  4,  -3,  -5,  -3,
    4,   3,  13,   1,  2,   1,  -1,   2,
    3,   5,   8,   4, -5,  -6,  -8, -11,
    -4,   0,  -5,  -1, -7, -12,  -8, -16,
    -6,  -6,   0,   2, -9,  -9, -11,  -3,
    -9,   2,   3,  -1, -5, -13,   4, -20,
};

// Queen Table
const mg_queen_table = [64]i32{
    -28,   0,  29,  12,  59,  44,  43,  45,
    -24, -39,  -5,   1, -16,  57,  28,  54,
    -13, -17,   7,   8,  29,  56,  47,  57,
    -27, -27, -16, -16,  -1,  17,  -2,   1,
    -9, -26, -9, -10,  -2,  -4,   3,  -3,
    -14,   2, -11,  -2,  -5,   2,  14,   5,
    -35,  -8,  11,   2,   8,  15,  -3,   1,
    -1, -18,  -9,  10, -15, -25, -31, -50,
};
const eg_queen_table = [64]i32{
    -9,  22,  22,  27,  27,  19,  10,  20,
    -17,  20,  32,  41,  58,  25,  30,   0,
    -20,   6,   9,  49,  47,  35,  19,   9,
    3,  22,  24,  45,  57,  40,  57,  36,
    -18,  28,  19,  47,  31,  34,  39,  23,
    -16, -27,  15,   6,   9,  17,  10,   5,
    -22, -23, -30, -16, -16, -23, -36, -32,
    -33, -28, -22, -43,  -5, -32, -20, -41,
};

// King Table (Hide in safety in MG, Active in EG)
const mg_king_table = [64]i32{
    -65,  23,  16, -15, -56, -34,   2,  13,
    29,  -1, -20,  -7,  -8,  -4, -38, -29,
    -9,  24,   2, -16, -20,   6,  22, -22,
    -17, -20, -12, -27, -30, -25, -14, -36,
    -49,  -1, -27, -39, -46, -44, -33, -51,
    -14, -14, -22, -46, -44, -30, -15, -27,
    1,   7,  -8, -64, -43, -16,   9,   8,
    -15,  36,  12, -54,   8, -28,  24,  14,
};
const eg_king_table = [64]i32{
    -74, -35, -18, -18, -11,  15,   4, -17,
    -12,  17,  14,  17,  17,  38,  23,  11,
    10,  17,  23,  15,  20,  45,  44,  13,
    -8,  22,  24,  27,  26,  33,  26,   3,
    -18,  -4,  21,  24,  27,  23,   9, -11,
    -19,  -3,  11,  21,  23,  16,   7,  -9,
    -27, -11,   4,  13,  14,   4,  -5, -17,
    -53, -34, -21, -11, -28, -14, -24, -43,
};

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

pub fn evaluate(board: *brd.Board) i32 {
    var current_phase: i32 = 0;

    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][1]) + @popCount(board.piece_bb[1][1]))) * knight_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][2]) + @popCount(board.piece_bb[1][2]))) * bishop_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][3]) + @popCount(board.piece_bb[1][3]))) * rook_phase;
    current_phase += @as(i32, @intCast(@popCount(board.piece_bb[0][4]) + @popCount(board.piece_bb[1][4]))) * queen_phase;

    current_phase = std.math.clamp(current_phase, 0, total_phase);

    var mg_score: i32 = 0;
    var eg_score: i32 = 0;

    mg_score += evalColor(board, brd.Color.White, true);
    eg_score += evalColor(board, brd.Color.White, false);

    mg_score -= evalColor(board, brd.Color.Black, true);
    eg_score -= evalColor(board, brd.Color.Black, false);

    // King Safety (middlegame focused)
    mg_score += evalKingSafety(board, brd.Color.White);
    mg_score -= evalKingSafety(board, brd.Color.Black);

    // Pawn Structure evaluation
    const pawn_eval = evalPawnStructure(board, current_phase);
    mg_score += pawn_eval.mg;
    eg_score += pawn_eval.eg;

    // Endgame-specific evaluation (more important as phase approaches 0)
    if (current_phase < total_phase / 2) {
        const eg_eval = evalEndgame(board, current_phase);
        eg_score += eg_eval;
    }

    var final_score = (mg_score * current_phase + eg_score * (total_phase - current_phase));
    final_score = @divTrunc(final_score, total_phase);

    if (board.toMove() == brd.Color.White) {
        return final_score;
    } else {
        return -final_score;
    }
}

fn evalColor(board: *brd.Board, color: brd.Color, is_mg: bool) i32 {
    const c_idx = @intFromEnum(color);
    var score: i32 = 0;

    // Piece Values selection
    const p_val = if (is_mg) mg_pawn else eg_pawn;
    const n_val = if (is_mg) mg_knight else eg_knight;
    const b_val = if (is_mg) mg_bishop else eg_bishop;
    const r_val = if (is_mg) mg_rook else eg_rook;
    const q_val = if (is_mg) mg_queen else eg_queen;
    const k_val = 0; 

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
        score += p_val;
        score += getPst(sq, if (is_mg) mg_pawn_table else eg_pawn_table, color);
        brd.popBit(&bb, sq);
    }

    // Knights
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Knight)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        score += n_val;
        score += getPst(sq, if (is_mg) mg_knight_table else eg_knight_table, color);
        brd.popBit(&bb, sq);
    }

    // Bishops
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Bishop)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        score += b_val;
        score += getPst(sq, if (is_mg) mg_bishop_table else eg_bishop_table, color);
        brd.popBit(&bb, sq);
    }

    // Rooks
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Rook)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        score += r_val;
        score += getPst(sq, if (is_mg) mg_rook_table else eg_rook_table, color);
        brd.popBit(&bb, sq);
    }

    // Queens
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Queen)];
    while (bb != 0) {
        const sq = brd.getLSB(bb);
        score += q_val;
        score += getPst(sq, if (is_mg) mg_queen_table else eg_queen_table, color);
        brd.popBit(&bb, sq);
    }

    // King
    bb = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.King)];
    if (bb != 0) {
        const sq = brd.getLSB(bb);
        score += k_val;
        score += getPst(sq, if (is_mg) mg_king_table else eg_king_table, color);
    }

    return score;
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
            // Has pawn on this file
            var temp_bb = pawns_on_file;
            while (temp_bb != 0) {
                const pawn_sq = brd.getLSB(temp_bb);
                const pawn_rank = @divTrunc(pawn_sq, 8);
                
                // Check if pawn is in front of king (rank-wise)
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
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    var result = PawnEval{ .mg = 0, .eg = 0 };
    
    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];
    
    // Count pawns per file for doubled pawn detection
    var file_counts = [_]u8{0} ** 8;
    var temp_bb = our_pawns;
    while (temp_bb != 0) {
        const sq = brd.getLSB(temp_bb);
        const file = @mod(sq, 8);
        file_counts[file] += 1;
        brd.popBit(&temp_bb, sq);
    }
    
    // Evaluate each pawn
    temp_bb = our_pawns;
    while (temp_bb != 0) {
        const sq = brd.getLSB(temp_bb);
        const file = @mod(sq, 8);
        const rank = @divTrunc(sq, 8);
        
        // Adjust rank for color
        const relative_rank: usize = if (color == brd.Color.White) rank else 7 - rank;
        
        // Check for passed pawn
        const is_passed = blk: {
            const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
            const left_mask: u64 = if (file > 0) @as(u64, 0x0101010101010101) << @intCast(file - 1) else 0;
            const right_mask: u64 = if (file < 7) @as(u64, 0x0101010101010101) << @intCast(file + 1) else 0;
            const forward_mask = file_mask | left_mask | right_mask;
            
            // Check if any opposing pawns block this pawn's path
            const blocking_pawns = if (color == brd.Color.White) blk2: {
                // For white, check ranks above
                const rank_mask: u64 = (@as(u64, 0xFFFFFFFFFFFFFFFF) << @intCast((rank + 1) * 8));
                break :blk2 opp_pawns & forward_mask & rank_mask;
            } else blk2: {
                // For black, check ranks below
                const rank_mask: u64 = if (rank > 0) (@as(u64, 0xFFFFFFFFFFFFFFFF) >> @intCast((8 - rank) * 8)) else 0;
                break :blk2 opp_pawns & forward_mask & rank_mask;
            };
            
            break :blk blocking_pawns == 0;
        };
        
        if (is_passed) {
            // Scale passed pawn bonus more heavily towards endgame
            // In endgame (phase near 0), passed pawns are very valuable
            // In middlegame (phase near 24), they're less critical
            const mg_bonus = mg_passed_bonus[relative_rank];
            const eg_bonus = passed_pawn_bonus[relative_rank];
            
            // Add extra endgame weight for advanced passed pawns
            const advancement_bonus = if (relative_rank >= 5) 
                @divTrunc((total_phase - phase) * @as(i32, @intCast(relative_rank)) * 3, total_phase)
            else 
                0;
            
            result.mg += mg_bonus;
            result.eg += eg_bonus + advancement_bonus;
        }
        
        // Check for pawn protection (pawn chain)
        const is_protected = blk: {
            const protection_sqs = if (color == brd.Color.White) blk2: {
                // White pawns protected from behind-left and behind-right
                var sqs: [2]?usize = .{ null, null };
                if (sq >= 9 and file > 0) sqs[0] = sq - 9;  // Behind-left
                if (sq >= 7 and file < 7) sqs[1] = sq - 7;  // Behind-right
                break :blk2 sqs;
            } else blk2: {
                // Black pawns protected from behind-left and behind-right (from black's perspective)
                var sqs: [2]?usize = .{ null, null };
                if (sq <= 54 and file > 0) sqs[0] = sq + 7;  // Behind-left
                if (sq <= 56 and file < 7) sqs[1] = sq + 9;  // Behind-right
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
        
        // Check for isolated pawn
        const is_isolated = blk: {
            const left_mask: u64 = if (file > 0) @as(u64, 0x0101010101010101) << @intCast(file - 1) else 0;
            const right_mask: u64 = if (file < 7) @as(u64, 0x0101010101010101) << @intCast(file + 1) else 0;
            const adjacent_files = left_mask | right_mask;
            break :blk (our_pawns & adjacent_files) == 0;
        };
        
        if (is_isolated) {
            result.mg += isolated_pawn_penalty;
            result.eg += isolated_pawn_penalty;
        }
        
        // Doubled pawns penalty
        if (file_counts[file] > 1) {
            result.mg += doubled_pawn_penalty;
            result.eg += doubled_pawn_penalty;
        }
        
        brd.popBit(&temp_bb, sq);
    }
    
    return result;
}

// Endgame-specific evaluation
fn evalEndgame(board: *brd.Board, phase: i32) i32 {
    var score: i32 = 0;
    
    // Determine material imbalance
    const white_material = countMaterial(board, brd.Color.White);
    const black_material = countMaterial(board, brd.Color.Black);
    const material_diff = white_material - black_material;
    
    // Mop-up evaluation: when winning, drive enemy king to edge and our king closer
    if (@abs(material_diff) > 200) { // Significant material advantage
        const winning_side = if (material_diff > 0) brd.Color.White else brd.Color.Black;
        const losing_side = if (material_diff > 0) brd.Color.Black else brd.Color.White;
        
        const winner_idx = @intFromEnum(winning_side);
        const loser_idx = @intFromEnum(losing_side);
        
        const winner_king_bb = board.piece_bb[winner_idx][@intFromEnum(brd.Pieces.King)];
        const loser_king_bb = board.piece_bb[loser_idx][@intFromEnum(brd.Pieces.King)];
        
        if (winner_king_bb != 0 and loser_king_bb != 0) {
            const winner_king_sq = brd.getLSB(winner_king_bb);
            const loser_king_sq = brd.getLSB(loser_king_bb);
            
            // Drive losing king to the edge (important for checkmating)
            const edge_score = centerDistance(loser_king_sq) * 10;
            
            // Bring winning king closer to losing king (important for checkmate)
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

// Count total material for a side
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
    score += centralization * 3;
    
    // Bonus for king being close to passed pawns (to support or stop them)
    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[1 - c_idx][@intFromEnum(brd.Pieces.Pawn)];
    
    // Check proximity to our passed pawns
    var pawn_bb = our_pawns;
    while (pawn_bb != 0) {
        const pawn_sq = brd.getLSB(pawn_bb);
        const is_passed = checkPassedPawn(board, pawn_sq, color);
        
        if (is_passed) {
            const dist = manhattanDistance(king_sq, pawn_sq);
            if (dist <= 3) {
                score += king_pawn_proximity * (4 - dist);
            }
        }
        
        brd.popBit(&pawn_bb, pawn_sq);
    }
    
    // Penalty for being far from opponent's passed pawns (need to stop them)
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

// Helper to check if a pawn is passed
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
        
        // Rook on 7th rank bonus (attacking pawns)
        const seventh_rank: i32 = if (color == brd.Color.White) 6 else 1;
        if (rook_rank == seventh_rank) {
            score += rook_on_7th_bonus;
        }
        
        // Rook behind passed pawn (very strong)
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

pub fn almostMate(score: i32) bool {
    return @abs(score) > mate_score - 256;
}
