const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;
const mvs = root.moves;
const zob = root.zob;
const tp = root.tp;

pub const mate_score: i32 = 32000;
pub const tb_win_score: i32 = mate_score;

pub fn almostMate(score: i32) bool {
    return @abs(score) > mate_score - 256;
}

pub inline fn scalingMaterial(gs: *const brd.GameState) i32 {
    const pos = &gs.cur_position;

    const pawns:   i32 = @intCast(@popCount(pos.getPieceBoard(.Pawn)));
    const knights: i32 = @intCast(@popCount(pos.getPieceBoard(.Knight)));
    const bishops: i32 = @intCast(@popCount(pos.getPieceBoard(.Bishop)));
    const rooks:   i32 = @intCast(@popCount(pos.getPieceBoard(.Rook)));
    const queens:  i32 = @intCast(@popCount(pos.getPieceBoard(.Queen)));

    return tp.scale_pawn.value   * pawns
         + tp.scale_knight.value * knights
         + tp.scale_bishop.value * bishops
         + tp.scale_rook.value   * rooks
         + tp.scale_queen.value  * queens;
}

pub fn adjustEval(gs: *const brd.GameState, optimism: i32, raw: i32, correction: i32) i32 {
    const mat: i64 = scalingMaterial(gs);
    const opt_mul: i64 = @as(i64, tp.optimism_base.value)
        + @divTrunc(mat * @as(i64, tp.optimism_mat_scale.value), 1024);

    var v: i64 = @as(i64, raw)
        + @divTrunc(@as(i64, optimism) * opt_mul, @as(i64, tp.material_scale_div.value));

    const hm: i64 = gs.cur_position.halfmove;
    const fifty: i64 = tp.fifty_scale_base.value;
    v = @divTrunc(v * (fifty - hm), fifty);

    v += correction;
    return @intCast(std.math.clamp(v, -mate_score + 257, mate_score - 257));
}
