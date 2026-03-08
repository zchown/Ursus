const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const see = @import("see");
const srch = @import("search");

// mvv_lva[victim][attacker]
pub const mvv_lva = [6][6]i32{
    // Pawn  Knight Bishop Rook  Queen  King   <- attacker
    .{ 105, 104, 103, 102, 101, 100 }, // Pawn   victim
    .{ 305, 304, 303, 302, 301, 300 }, // Knight victim
    .{ 305, 304, 303, 302, 301, 300 }, // Bishop victim
    .{ 505, 504, 503, 502, 501, 500 }, // Rook   victim
    .{ 905, 904, 903, 902, 901, 900 }, // Queen  victim
    .{ 0, 0, 0, 0, 0, 0 }, // King   victim (unused)
};

const hash_move_score = 1_000_000;
const killer_1_score = 900_000;
const killer_2_score = 800_000;

pub fn scoreMoves(searcher: *srch.Searcher, board: *brd.Board, move_list: *const mvs.MoveList, hash_move: mvs.EncodedMove, is_null: bool) [218]i32 {
    _ = is_null;

    var scores: [218]i32 = @splat(0);
    const hm = hash_move.toU32();
    const side = @intFromEnum(board.toMove());

    for (0..move_list.len) |i| {
        const mv = move_list.items[i];
        if (mv.toU32() == hm) {
            scores[i] = hash_move_score;
        } else if (mv.captured_piece != 0) {
            const victim = @as(usize, @intCast(mv.captured_piece));

            const attacking_piece = board.getPieceFromSquare(mv.start_square).?;
            const attacker = @as(usize, @intCast(@intFromEnum(attacking_piece)));

            scores[i] = mvv_lva[victim][attacker] + hash_move_score / 2;
        } else if (mv.toU32() == searcher.killer[searcher.ply][0].toU32()) {
            scores[i] = killer_1_score;
        } else if (mv.toU32() == searcher.killer[searcher.ply][1].toU32()) {
            scores[i] = killer_2_score;
        } else {
            scores[i] = searcher.history[side][mv.start_square][mv.end_square];
        }
    }
    return scores;
}

pub fn getNextBest(move_list: *mvs.MoveList, scores: *[218]i32, start_index: usize) mvs.EncodedMove {
    var j = start_index + 1;
    while (j < move_list.len) : (j += 1) {
        if (scores[start_index] < scores[j]) {
            std.mem.swap(mvs.EncodedMove, &move_list.items[start_index], &move_list.items[j]);
            std.mem.swap(i32, &scores[start_index], &scores[j]);
        }
    }
    return move_list.items[start_index];
}
