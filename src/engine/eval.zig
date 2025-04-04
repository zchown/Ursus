const brd = @import("../chess/board.zig");
pub const PieceValues = enum(usize) {
    Pawn = 100,
    Knight = 320,
    Bishop = 330,
    Rook = 500,
    Queen = 900,
    King = 0,
};

// Pawn position values (encourages center control and promotion)
const pawn_pst = [64]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5, 0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0 };

// Knight position values (encourages knights to stay near center)
const knight_pst = [64]i32{ -50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30, -30, 5, 15, 20, 20, 15, 5, -30, -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50 };

// Bishop position values (encourages bishops to control diagonals)
const bishop_pst = [64]i32{ -20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 10, 10, 10, 10, 0, -10, -10, 5, 5, 10, 10, 5, 5, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 5, 5, 5, 5, 5, 5, -10, -10, 0, 5, 0, 0, 5, 0, -10, -20, -10, -10, -10, -10, -10, -10, -20 };

// Rook position values (encourages rooks to control open files)
const rook_pst = [64]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0 };

// Queen position values (discourages early queen development)
const queen_pst = [64]i32{ -20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0, -5, 0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20 };

// King position values for middlegame (encourages king safety)
const king_pst_mg = [64]i32{ -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10, 20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20 };

// King position values for endgame (encourages king activity)
const king_pst_eg = [64]i32{ -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50 };

const BISHOP_PAIR_BONUS = 30;
const ENDGAME_MATERIAL_THRESHOLD = 1500;
var total_material: u32 = 0;

inline fn squareIndex(file: u3, rank: u3) u6 {
    return @as(u6, rank) * 8 + @as(u6, file);
}

inline fn mirrorSquare(square: u6) u6 {
    return @intCast(@as(u8, 64) -| square - 1);
}

pub fn evaluate(board: *brd.Board) f64 {
    var score: f64 = evaluateMaterial(board);
    score += (evaluatePosition(board) / 10);

    return score;
}

pub fn evaluateMaterial(board: *brd.Board) f64 {
    var score: f64 = 0;
    // pawns
    const wp = @as(f64, @floatFromInt(@popCount(board.piece_bb[0][0]) * @intFromEnum(PieceValues.Pawn)));
    const bp = @as(f64, @floatFromInt(@popCount(board.piece_bb[1][0]) * @intFromEnum(PieceValues.Pawn)));
    // knights
    const wn = @as(f64, @floatFromInt(@popCount(board.piece_bb[0][1]) * @intFromEnum(PieceValues.Knight)));
    const bn = @as(f64, @floatFromInt(@popCount(board.piece_bb[1][1]) * @intFromEnum(PieceValues.Knight)));
    // bishops
    const wb = @as(f64, @floatFromInt(@popCount(board.piece_bb[0][2]) * @intFromEnum(PieceValues.Bishop)));
    const bb = @as(f64, @floatFromInt(@popCount(board.piece_bb[1][2]) * @intFromEnum(PieceValues.Bishop)));
    // rooks
    const wr = @as(f64, @floatFromInt(@popCount(board.piece_bb[0][3]) * @intFromEnum(PieceValues.Rook)));
    const br = @as(f64, @floatFromInt(@popCount(board.piece_bb[1][3]) * @intFromEnum(PieceValues.Rook)));
    // queens
    const wq = @as(f64, @floatFromInt(@popCount(board.piece_bb[0][4]) * @intFromEnum(PieceValues.Queen)));
    const bq = @as(f64, @floatFromInt(@popCount(board.piece_bb[1][4]) * @intFromEnum(PieceValues.Queen)));

    score = wp - bp + wn - bn + wb - bb + wr - br + wq - bq;
    total_material = @as(u32, @intFromFloat(wp + bp + wn + bn + wb + bb + wr + br + wq + bq));

    // Bishop pair bonus
    if (@popCount(board.piece_bb[0][2]) >= 2) score += BISHOP_PAIR_BONUS;
    if (@popCount(board.piece_bb[1][2]) >= 2) score -= BISHOP_PAIR_BONUS;

    return score;
}

inline fn calculateEndgamePhase() f64 {
    if (total_material <= ENDGAME_MATERIAL_THRESHOLD) {
        return 1.0; // Endgame phase
    } else {
        return @as(f64, @floatFromInt(total_material - ENDGAME_MATERIAL_THRESHOLD)) / @as(f64, @floatFromInt(total_material));
    }
}

fn evaluatePosition(board: *brd.Board) f64 {
    var score: f64 = 0;
    const endgame_phase = calculateEndgamePhase();

    var bb: u64 = undefined;
    var sq: u6 = undefined;

    // Pawns
    bb = board.piece_bb[0][0]; // White pawns
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score += @as(f64, @floatFromInt(pawn_pst[sq]));
        bb &= bb - 1; // Clear least significant bit
    }

    bb = board.piece_bb[1][0]; // Black pawns
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score -= @as(f64, @floatFromInt(pawn_pst[mirrorSquare(sq)]));
        bb &= bb - 1;
    }

    // Knights
    bb = board.piece_bb[0][1]; // White knights
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score += @as(f64, @floatFromInt(knight_pst[sq]));
        bb &= bb - 1;
    }

    bb = board.piece_bb[1][1]; // Black knights
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score -= @as(f64, @floatFromInt(knight_pst[mirrorSquare(sq)]));
        bb &= bb - 1;
    }

    // Bishops
    bb = board.piece_bb[0][2]; // White bishops
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score += @as(f64, @floatFromInt(bishop_pst[sq]));
        bb &= bb - 1;
    }

    bb = board.piece_bb[1][2]; // Black bishops
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score -= @as(f64, @floatFromInt(bishop_pst[mirrorSquare(sq)]));
        bb &= bb - 1;
    }

    // Rooks
    bb = board.piece_bb[0][3]; // White rooks
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score += @as(f64, @floatFromInt(rook_pst[sq]));
        bb &= bb - 1;
    }

    bb = board.piece_bb[1][3]; // Black rooks
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score -= @as(f64, @floatFromInt(rook_pst[mirrorSquare(sq)]));
        bb &= bb - 1;
    }

    // Queens
    bb = board.piece_bb[0][4]; // White queens
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score += @as(f64, @floatFromInt(queen_pst[sq]));
        bb &= bb - 1;
    }

    bb = board.piece_bb[1][4]; // Black queens
    while (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        score -= @as(f64, @floatFromInt(queen_pst[mirrorSquare(sq)]));
        bb &= bb - 1;
    }

    // Kings (interpolate between middlegame and endgame values)
    bb = board.piece_bb[0][5]; // White king
    if (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        const mg_value = @as(f64, @floatFromInt(king_pst_mg[sq]));
        const eg_value = @as(f64, @floatFromInt(king_pst_eg[sq]));
        score += mg_value * (1.0 - endgame_phase) + eg_value * endgame_phase;
    }

    bb = board.piece_bb[1][5]; // Black king
    if (bb != 0) {
        sq = @as(u6, @truncate(@ctz(bb)));
        const mg_value = @as(f64, @floatFromInt(king_pst_mg[mirrorSquare(sq)]));
        const eg_value = @as(f64, @floatFromInt(king_pst_eg[mirrorSquare(sq)]));
        score -= mg_value * (1.0 - endgame_phase) + eg_value * endgame_phase;
    }

    return score;
}
