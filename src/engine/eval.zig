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

pub fn adjustEval(board: *const brd.Board, raw: i32, correction: i32) i32 {
    var v: i64 = raw;

    const hm: i64 = board.game_state.halfmove_clock;
    const fifty: i64 = tp.fifty_scale_base.value;
    v = @divTrunc(v * (fifty - hm), fifty);

    v += correction;
    return @intCast(std.math.clamp(v, -mate_score + 257, mate_score - 257));
}
