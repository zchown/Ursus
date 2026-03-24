const std = @import("std");
const mvs = @import("moves");
const brd = @import("board");
const eval = @import("eval");
const search = @import("search");

const Searcher = search.Searcher;
const max_ply = search.max_ply;
const PieceColor = Searcher.PieceColor;

pub fn resetHeuristics(self: *Searcher, total: bool) void {
    self.nmp_min_ply = 0;

    for (0..max_ply) |i| {
        self.killer[i][0] = mvs.EncodedMove.fromU32(0);
        self.killer[i][1] = mvs.EncodedMove.fromU32(0);
        self.excluded_moves[i] = mvs.EncodedMove.fromU32(0);

        for (0..max_ply) |j| {
            self.pv[i][j] = mvs.EncodedMove.fromU32(0);
        }
        self.pv_length[i] = 0;
        self.eval_history[i] = 0;
        self.move_history[i] = mvs.EncodedMove.fromU32(0);
        self.moved_piece_history[i] = PieceColor{ .piece = .None, .color = .White };
    }

    for (0..2) |c| {
        if (total) {
            @memset(&self.correction[c], 0);
            @memset(&self.np_white_correction[c], 0);
            @memset(&self.np_black_correction[c], 0);
        } else {
            for (0..16384) |i| {
                self.correction[c][i] = @divTrunc(self.correction[c][i], 8);
                self.np_white_correction[c][i] = @divTrunc(self.np_white_correction[c][i], 8);
                self.np_black_correction[c][i] = @divTrunc(self.np_black_correction[c][i], 8);
            }
        }
    }

    for (0..64) |j| {
        for (0..7) |a| {
            for (0..7) |t| {
                for (0..2) |c| {
                    if (total) {
                        self.capture_history[c][a][j][t] = 0;
                    } else {
                        self.capture_history[c][a][j][t] = @divTrunc(self.capture_history[c][a][j][t], 8);
                    }
                }
            }
        }

        for (0..64) |k| {
            for (0..2) |c| {
                if (total) {
                    self.history[c][j][k] = 0;
                } else {
                    self.history[c][j][k] = @divTrunc(self.history[c][j][k] * 3, 4);
                }
                self.counter_moves[c][j][k] = mvs.EncodedMove.fromU32(0);
            }
        }
    }

    if (total) {
        @memset(std.mem.asBytes(self.continuation), 0);
    } else {
        for (0..12) |l| {
            for (0..64) |j| {
                for (0..64) |k| {
                    for (0..64) |m| {
                        self.continuation[l][j][k][m] = @divTrunc(self.continuation[l][j][k][m] * 3, 4);
                    }
                }
            }
        }
    }
}

pub fn updateCorrection(
    self: *Searcher,
    color: brd.Color,
    board: *brd.Board,
    best_score: i32,
    static_eval: i32,
    depth: usize,
) void {
    const corr_idx = board.game_state.pawn_hash & 16383;
    const np_white_corr_idx = board.game_state.white_np_hash & 16383;
    const np_black_corr_idx = board.game_state.black_np_hash & 16383;

    const err = best_score - static_eval;
    const current_entry = &self.correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(corr_idx))];

    const weight: i32 = @min(256, @as(i32, @intCast(depth)) * 32); // scale with depth
    const scaled_err = err * weight;
    current_entry.* = std.math.clamp(current_entry.* + @divTrunc(scaled_err - current_entry.* * @as(i32, @intCast(@abs(weight))), 256), -16000, 16000);

    const np_current_entry = &self.np_white_correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(np_white_corr_idx))];
    const np_weight: i32 = @min(128, @as(i32, @intCast(depth)) * 16);
    const np_scaled_err = err * np_weight;
    np_current_entry.* = std.math.clamp(np_current_entry.* + @divTrunc(np_scaled_err - np_current_entry.* * @as(i32, @intCast(@abs(np_weight))), 256), -16000, 16000);

    const npb_current_entry = &self.np_black_correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(np_black_corr_idx))];
    const npb_weight: i32 = @min(128, @as(i32, @intCast(depth)) * 16);
    const npb_scaled_err = err * npb_weight;
    npb_current_entry.* = std.math.clamp(npb_current_entry.* + @divTrunc(npb_scaled_err - npb_current_entry.* * @as(i32, @intCast(@abs(npb_weight))), 256), -16000, 16000);
}

pub fn updateQuietHistory(
    self: *Searcher,
    color: brd.Color,
    best_move: mvs.EncodedMove,
    quiet_moves: *const mvs.MoveList,
    is_null: bool,
    depth: usize,
) void {
    self.killer[self.ply][1] = self.killer[self.ply][0];
    self.killer[self.ply][0] = best_move;

    const depth_i32 = @as(i32, @intCast(depth));
    const bonus = @min(16384, 32 * depth_i32 * depth_i32);
    const max_history: i32 = 16384;

    if (!is_null and self.ply >= 1) {
        const last = self.move_history[self.ply - 1];
        self.counter_moves[@intFromEnum(color)][last.start_square][last.end_square] = best_move;
    }

    const b = best_move.toU32();

    for (quiet_moves.items) |m| {
        const h = &self.history[@intFromEnum(color)][m.start_square][m.end_square];

        const is_best = m.toU32() == b;

        const clamped_bonus = if (is_best)
            bonus
        else
            -bonus;

        // Gravity update:
        h.* += clamped_bonus - @divTrunc(h.* * @as(i32, @intCast(@abs(clamped_bonus))), max_history);

        if (!is_null and self.ply >= 1) {
            const plies: [3]usize = .{ 0, 1, 3 };
            for (plies) |p| {
                if (self.ply >= p + 1) {
                    const prev = self.move_history[self.ply - p - 1];
                    if (prev.toU32() == 0) continue;

                    const piece_color = self.moved_piece_history[self.ply - p - 1];
                    const pc_index = @as(usize, @intCast(@intFromEnum(piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(piece_color.piece)));
                    const cont_hist = self.continuation[pc_index][prev.start_square][prev.end_square][m.end_square] * bonus;
                    if (is_best) {
                        self.continuation[pc_index][prev.start_square][prev.end_square][m.end_square] += bonus - @divTrunc(cont_hist, max_history);
                    } else {
                        self.continuation[pc_index][prev.start_square][prev.end_square][m.end_square] += -bonus - @divTrunc(cont_hist, max_history);
                    }
                }
            }
        }
    }
}

pub fn updateCaptureHistory(
    self: *Searcher,
    board: *brd.Board,
    color: brd.Color,
    best_move: mvs.EncodedMove,
    other_moves: *const mvs.MoveList,
    depth: usize,
) void {
    const captured_piece_idx = @as(usize, @intCast(best_move.captured_piece));

    if (captured_piece_idx < 6) {
        const bonus = @as(i32, @intCast(@min(1024, depth * depth * 16)));
        const max_cap_hist: i32 = 16384;

        var attacking_piece = board.getPieceFromSquare(best_move.start_square).?;
        var attacking_piece_idx = @as(usize, @intCast(@intFromEnum(attacking_piece)));

        const old_value = self.capture_history[@intFromEnum(color)][attacking_piece_idx][best_move.end_square][captured_piece_idx];
        const hist = old_value * bonus;
        self.capture_history[@intFromEnum(color)][attacking_piece_idx][best_move.end_square][captured_piece_idx] +=
            bonus - @divTrunc(hist, max_cap_hist);

        // Penalize other captures that were tried but didn't cause cutoff
        for (other_moves.items) |m| {
            if (m.capture == 1 and m.toU32() != best_move.toU32()) {
                const cap_p_idx = @as(usize, @intCast(m.captured_piece));

                attacking_piece = board.getPieceFromSquare(m.start_square).?;
                attacking_piece_idx = @as(usize, @intCast(@intFromEnum(attacking_piece)));

                if (cap_p_idx < 6) {
                    const old_val = self.capture_history[@intFromEnum(color)][attacking_piece_idx][m.end_square][cap_p_idx];
                    const h = old_val * bonus;
                    self.capture_history[@intFromEnum(color)][attacking_piece_idx][m.end_square][cap_p_idx] +=
                        -bonus - @divTrunc(h, max_cap_hist);
                }
            }
        }
    }
}
