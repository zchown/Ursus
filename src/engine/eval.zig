const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const zob = @import("zobrist");
const pawn_tt = @import("pawn_tt");
const tp = @import("tunable_parameters");

pub const mate_score: i32 = 32000;
pub const tb_win_score: i32 = mate_score;

pub fn almostMate(score: i32) bool {
    return @abs(score) > mate_score - 256;
}

pub inline fn scalingMaterial(board: *const brd.Board) i32 {
    const w  = @intFromEnum(brd.Color.White);
    const b  = @intFromEnum(brd.Color.Black);
    const P  = @intFromEnum(brd.Pieces.Pawn);
    const N  = @intFromEnum(brd.Pieces.Knight);
    const B  = @intFromEnum(brd.Pieces.Bishop);
    const R  = @intFromEnum(brd.Pieces.Rook);
    const Q  = @intFromEnum(brd.Pieces.Queen);

    const pawns:   i32 = @intCast(@popCount(board.piece_bb[w][P] | board.piece_bb[b][P]));
    const knights: i32 = @intCast(@popCount(board.piece_bb[w][N] | board.piece_bb[b][N]));
    const bishops: i32 = @intCast(@popCount(board.piece_bb[w][B] | board.piece_bb[b][B]));
    const rooks:   i32 = @intCast(@popCount(board.piece_bb[w][R] | board.piece_bb[b][R]));
    const queens:  i32 = @intCast(@popCount(board.piece_bb[w][Q] | board.piece_bb[b][Q]));

    return tp.scale_pawn.value   * pawns
         + tp.scale_knight.value * knights
         + tp.scale_bishop.value * bishops
         + tp.scale_rook.value   * rooks
         + tp.scale_queen.value  * queens;
}

pub fn adjustEval(board: *const brd.Board, optimism: i32, raw: i32, correction: i32) i32 {
    const mat: i64 = scalingMaterial(board);
    const opt_mul: i64 = @as(i64, tp.optimism_base.value)
        + @divTrunc(mat * @as(i64, tp.optimism_mat_scale.value), 1024);

    var v: i64 = @as(i64, raw)
        + @divTrunc(@as(i64, optimism) * opt_mul, @as(i64, tp.material_scale_div.value));

    const hm: i64 = board.game_state.halfmove_clock;
    const fifty: i64 = tp.fifty_scale_base.value;
    v = @divTrunc(v * (fifty - hm), fifty);

    v += correction;
    return @intCast(std.math.clamp(v, -mate_score + 257, mate_score - 257));
}
