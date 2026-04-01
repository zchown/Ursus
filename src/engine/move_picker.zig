const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const see = @import("see");
const srch = @import("search");

const score_hash: i32 = 2_000_000_000;
const score_winning_capture: i32 = 1_000_000;
const score_promotion: i32 = 950_000;
const score_equal_capture: i32 = 900_000;
const score_killer_1: i32 = 700_000;
const score_killer_2: i32 = 690_000;
const score_counter: i32 = 600_000;

pub fn scoreMoves(s: *srch.Searcher, board: *brd.Board, move_list: *mvs.MoveList, hash_move: mvs.EncodedMove, is_null: bool) [218]i32 {
        var scores: [218]i32 = @splat(0);

        // Pre-fetch history pointers to avoid lookups in the loop
        const side = @intFromEnum(board.toMove());

        // Counter move lookup prep
        var counter_move_u32: u32 = 0;
        if (s.ply > 0) {
            const last = s.move_history[s.ply - 1];
            counter_move_u32 = s.counter_moves[side][last.start_square][last.end_square].toU32();
        }

        for (move_list.items[0..move_list.len], 0..) |move, i| {
            var score: i32 = 0;
            const move_u32 = move.toU32();

            if (move.matchesTTKey(hash_move)) {
                score = score_hash;
            } else if (move.capture == 1) {
                const see_val = see.seeCapture(board, s.move_gen, move);

                if (see_val > 0) {
                    score = score_winning_capture + (see_val * 100);
                } else if (see_val == 0) {
                    score = score_equal_capture + @as(i32, move.captured_piece);
                } else {
                    score = see_val;
                }

                if (move.promoted_piece == @intFromEnum(brd.Pieces.Queen)) {
                    score += score_promotion;
                }

                const capture_piece_idx = @as(usize, @intCast(move.captured_piece));
                const color_idx = @as(usize, @intCast(@intFromEnum(board.toMove())));

                const attacking_piece = board.getPieceFromSquare(move.start_square).?;
                const attacking_piece_idx = @as(usize, @intCast(@intFromEnum(attacking_piece)));

                score += s.capture_history[color_idx][attacking_piece_idx][move.end_square][capture_piece_idx];
            } else {
                if (move.promoted_piece != 0) {
                    if (move.promoted_piece == @intFromEnum(brd.Pieces.Queen)) {
                        score = score_promotion;
                    } else {
                        score = -5_000;
                    }
                } else if (move_u32 == s.killer[s.ply][0].toU32()) {
                    score = score_killer_1;
                } else if (move_u32 == s.killer[s.ply][1].toU32()) {
                    score = score_killer_2;
                } else if (move_u32 == counter_move_u32) {
                    score = score_counter;
                } else {
                    score = s.history[side][move.start_square][move.end_square];
                    if (!is_null and s.ply >= 1) {
                        const plies: [3]usize = .{ 0, 1, 3 };
                        for (plies) |p| {
                            if (s.ply >= p + 1) {
                                const prev = s.move_history[s.ply - p - 1];
                                if (prev.toU32() == 0) continue;
                                const piece_color = s.moved_piece_history[s.ply - p - 1];
                                const pc_index = @as(usize, @intCast(@intFromEnum(piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(piece_color.piece)));
                                score += s.continuation[pc_index][prev.start_square][prev.end_square][move.end_square];
                            }
                        }
                    }
                }
            }
            scores[i] = score;
        }
        return scores;
    }

    pub fn getNextBest(move_list: *mvs.MoveList, scores: *[218]i32, start_index: usize) mvs.EncodedMove {
        var j = start_index + 1;
        if (start_index == 0) {
            while (j < move_list.len) : (j += 1) {
                if (scores[start_index] < scores[j]) {
                    std.mem.swap(mvs.EncodedMove, &move_list.items[start_index], &move_list.items[j]);
                    std.mem.swap(i32, &scores[start_index], &scores[j]);
                    if (scores[start_index] == score_hash) {
                        break; // Don't move hash move from the front
                    }
                }
            }
        } else {
            while (j < move_list.len) : (j += 1) {
                if (scores[start_index] < scores[j]) {
                    std.mem.swap(mvs.EncodedMove, &move_list.items[start_index], &move_list.items[j]);
                    std.mem.swap(i32, &scores[start_index], &scores[j]);
                }
            }
        }
        return move_list.items[start_index];
    }

