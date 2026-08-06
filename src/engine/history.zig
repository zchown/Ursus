const std = @import("std");
const mvs = @import("moves");
const brd = @import("board");
const eval = @import("eval");
const search = @import("search");
const tp = @import("tunable_parameters");

const Searcher = search.Searcher;
const max_ply = search.max_ply;
const PieceColor = Searcher.PieceColor;

const max_history: i32 = 16384;
const max_cap_history: i32 = 16384;

pub fn resetHeuristics(self: *Searcher, total: bool) void {
    @memset(std.mem.asBytes(&self.killer), 0);
    @memset(std.mem.asBytes(&self.pv_length), 0);
    @memset(std.mem.asBytes(&self.eval_history), 0);
    @memset(std.mem.asBytes(&self.move_history), 0);
    @memset(std.mem.asBytes(&self.moved_piece_history), 0);
    @memset(std.mem.asBytes(&self.excluded_moves), 0);

    if (total) {
        @memset(std.mem.asBytes(&self.correction), 0);
        @memset(std.mem.asBytes(&self.np_white_correction), 0);
        @memset(std.mem.asBytes(&self.np_black_correction), 0);
        @memset(std.mem.asBytes(&self.major_correction), 0);
        @memset(std.mem.asBytes(&self.minor_correction), 0);
    }

    if (total) {
        @memset(std.mem.asBytes(&self.capture_history), 0);
        @memset(std.mem.asBytes(&self.history), 0);
        @memset(std.mem.asBytes(self.continuation), 0);
    }
    else {
        const hist_flat = std.mem.bytesAsSlice(i32, std.mem.asBytes(&self.history));
        for (hist_flat) |*entry| {
            entry.* = entry.* - (entry.* >> 2) + 64;
        }

        const cap_flat = std.mem.bytesAsSlice(i32, std.mem.asBytes(&self.capture_history));
        for (cap_flat) |*entry| {
            entry.* -= (entry.* >> 2);
        }

        const cont_flat = std.mem.bytesAsSlice(i16, std.mem.asBytes(self.continuation));
        for (cont_flat) |*entry| {
            entry.* -= (entry.* >> 2);
        }
    }
}

inline fn historyBonus(depth: i32) i32 {
    return @max(1, @min(tp.hist_bonus_max, tp.hist_bonus_mul * depth - tp.hist_bonus_offset));
}

inline fn historyMalus(depth: i32) i32 {
    return @max(0, @min(tp.hist_malus_max, tp.hist_malus_mul * depth - tp.hist_malus_offset));
}

inline fn applyBonus(entry: *i32, delta: i32, max: i32) void {
    entry.* += delta - @divTrunc(entry.* * @as(i32, @intCast(@abs(delta))), max);
}

inline fn applyContBonus(entry: *i16, delta: i16, max: i16) void {
    entry.* += delta - @divTrunc(entry.* * @as(i16, @intCast(@abs(delta))), max);
}

inline fn applyCorrBonus(entry: *i32, bonus: i32, comptime limit: i32) void {
    entry.* += bonus - @divTrunc(entry.* * @as(i32, @intCast(@abs(bonus))), limit);
    entry.* = std.math.clamp(entry.*, -limit, limit);
}

pub fn updateCorrection(
    self: *Searcher,
    color: brd.Color,
    board: *brd.Board,
    best_move: mvs.EncodedMove,
    best_score: i32,
    static_eval: i32,
    depth: usize,
) void {
    _ = best_move;
    const corr_idx = board.game_state.pawn_hash & 16383;
    const np_white_corr_idx = board.game_state.white_np_hash & 16383;
    const np_black_corr_idx = board.game_state.black_np_hash & 16383;
    const minor_corr_idx = board.game_state.minor_hash & 16383;
    const major_corr_idx = board.game_state.major_hash & 16383;

    const err = best_score - static_eval;
    const depth_i32 = @as(i32, @intCast(depth));

    // Pawn correction
    const pawn_weight: i32 = @min(128, depth_i32 * 16);
    const pawn_entry = &self.correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(corr_idx))];
    pawn_entry.* = std.math.clamp(
        pawn_entry.* + @divTrunc(err * pawn_weight - pawn_entry.* * pawn_weight, 256),
        -16000, 16000,
    );

    const np_weight: i32 = @min(128, depth_i32 * 16);

    const npw_entry = &self.np_white_correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(np_white_corr_idx))];
    npw_entry.* = std.math.clamp(
        npw_entry.* + @divTrunc(err * np_weight - npw_entry.* * np_weight, 256),
        -16000, 16000,
    );

    const npb_entry = &self.np_black_correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(np_black_corr_idx))];
    npb_entry.* = std.math.clamp(
        npb_entry.* + @divTrunc(err * np_weight - npb_entry.* * np_weight, 256),
        -16000, 16000,
);

    const major_weight: i32 = @min(128, depth_i32 * 16);
    const major_entry = &self.major_correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(major_corr_idx))];
    major_entry.* = std.math.clamp(
    major_entry.* + @divTrunc(err * major_weight - major_entry.* * major_weight, 256),
    -16000, 16000,
);

    const minor_weight: i32 = @min(128, depth_i32 * 16);
    const minor_entry= &self.minor_correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(minor_corr_idx))];
    minor_entry.* = std.math.clamp(
    minor_entry.* + @divTrunc(err * minor_weight - minor_entry.* * minor_weight, 256),
    -16000, 16000,
);

}

pub fn getCorrection(self: *Searcher, color: brd.Color, board: *brd.Board) i32 {
    const corr_idx = board.game_state.pawn_hash & 16383;
    const np_white_corr_idx = board.game_state.white_np_hash & 16383;
    const np_black_corr_idx = board.game_state.black_np_hash & 16383;
    const major_corr_idx =board.game_state.major_hash & 16383; 
    const minor_corr_idx =board.game_state.minor_hash & 16383; 

    const c = @as(usize, @intFromEnum(color));

    const pawn_val = self.correction[c][@as(usize, @intCast(corr_idx))];
    const npw_val = self.np_white_correction[c][@as(usize, @intCast(np_white_corr_idx))];
    const npb_val = self.np_black_correction[c][@as(usize, @intCast(np_black_corr_idx))];
    const major_val= self.major_correction[c][@as(usize, @intCast(major_corr_idx))];
    const minor_val = self.minor_correction[c][@as(usize, @intCast(minor_corr_idx))];

    const combined = pawn_val * tp.corr_pawn_read_weight +
        npw_val * tp.corr_np_read_weight +
        npb_val * tp.corr_np_read_weight +
        major_val * tp.corr_major_read_weight +
        minor_val * tp.corr_minor_read_weight;


    return @divTrunc(combined, tp.corr_read_divisor);
}

pub fn updateQuietHistory(
    self: *Searcher,
    color: brd.Color,
    best_move: mvs.EncodedMove,
    quiet_moves: *const mvs.MoveList,
    is_null: bool,
    depth: usize,
) void {
    if(self.killer[self.ply][0].toU32() != best_move.toU32()) {
        self.killer[self.ply][1] = self.killer[self.ply][0];
        self.killer[self.ply][0] = best_move;
    }

    const depth_i32 = @as(i32, @intCast(depth));
    const bonus = historyBonus(depth_i32);
    const malus = historyMalus(depth_i32);

    if (!is_null and self.ply >= 1) {
        const last = self.move_history[self.ply - 1];
        self.counter_moves[@intFromEnum(color)][last.start_square][last.end_square] = best_move;
    }

    const b = best_move.toU32();

    for (quiet_moves.items) |m| {
        const is_best = m.toU32() == b;

        const delta = if (is_best) bonus else -malus;

        const h = &self.history[@intFromEnum(color)][m.start_square][m.end_square];
        applyBonus(h, delta, max_history);

        if (!is_null and self.ply >= 1) {
            const plies: [3]usize = .{ 0, 1, 3 };
            for (plies) |p| {
                if (self.ply >= p + 1) {
                    const prev = self.move_history[self.ply - p - 1];
                    if (prev.toU32() == 0) continue;

                    const prev_piece_color = self.moved_piece_history[self.ply - p - 1];
                    const prev_pc_index = @as(usize, @intCast(@intFromEnum(prev_piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(prev_piece_color.piece)));

                    const cur_pc_index = @as(usize, @intCast(@intFromEnum(brd.flipColor(prev_piece_color.color)))) * 6 + @as(usize, @intCast(m.piece));

                    const cont = &self.continuation[prev_pc_index][prev.end_square][cur_pc_index][m.end_square];
                    applyContBonus(cont, @as(i16, @intCast(delta)), @as(i16, @intCast(max_history)));
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
    _ = board;
    const captured_piece_idx = @as(usize, @intCast(best_move.captured_piece));

    if (captured_piece_idx < 6) {
        const depth_i32 = @as(i32, @intCast(depth));
        const bonus = historyBonus(depth_i32);
        const malus = historyMalus(depth_i32);

        const best_attacker: brd.Pieces = @enumFromInt(best_move.piece);
        const best_attacker_idx = @as(usize, @intCast(@intFromEnum(best_attacker)));

        const best_entry = &self.capture_history[@intFromEnum(color)][best_attacker_idx][best_move.end_square][captured_piece_idx];
        applyBonus(best_entry, bonus, max_cap_history);

        // Penalize other captures that were tried but didn't cause cutoff
        for (other_moves.items) |m| {
            if (m.capture == 1 and m.toU32() != best_move.toU32()) {
                const cap_p_idx = @as(usize, @intCast(m.captured_piece));

                if (cap_p_idx < 6) {
                    const attacker: brd.Pieces = @enumFromInt(m.piece);
                    const attacker_idx = @as(usize, @intCast(@intFromEnum(attacker)));

                    const entry = &self.capture_history[@intFromEnum(color)][attacker_idx][m.end_square][cap_p_idx];
                    applyBonus(entry, -malus, max_cap_history);
                }
            }
        }
    }
}

