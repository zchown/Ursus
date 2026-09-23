const std = @import("std");
const root = @import("root.zig");
const mvs = root.moves;
const brd = root.brd;
const eval = root.eval;
const search = root.search;
const tp = root.tp;

const Searcher = search.Searcher;
const max_ply = search.max_ply;
const PieceColor = Searcher.PieceColor;

const max_history: i32 = 16384;
const max_cap_history: i32 = 16384;

pub inline fn quietHist(s: *Searcher, side: usize, threats: u64, from: usize, to: usize) i32 {
    return s.quietHistScore(side, threats, from, to);
}

pub inline fn capHist(s: *Searcher, side: usize, attacker: usize, to: usize, captured: usize) i32 {
    return s.capture_history[side][attacker][to][captured];
}

pub inline fn contHist(s: *Searcher, prev_pc: usize, prev_to: usize, cur_pc: usize, cur_to: usize) i32 {
    return s.continuation[prev_pc][prev_to][cur_pc][cur_to];
}

pub const QuietUpdate = struct {
    threats: ?u64 = null,
    cont_idx: ?usize = null,
};


pub fn resetHeuristics(self: *Searcher, total: bool) void {
    @memset(std.mem.asBytes(&self.killer), 0);
    @memset(std.mem.asBytes(&self.pv_length), 0);
    @memset(std.mem.asBytes(&self.eval_history), 0);
    @memset(std.mem.asBytes(&self.move_history), 0);
    @memset(std.mem.asBytes(&self.moved_piece_history), 0);
    @memset(std.mem.asBytes(&self.excluded_moves), 0);
    @memset(std.mem.asBytes(&self.lmr_reduction), 0);
    @memset(std.mem.asBytes(&self.low_ply_history), 0);

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
        @memset(std.mem.asBytes(&self.threat_history), 0);
        @memset(std.mem.asBytes(self.continuation), 0);
    }
    else {
        const hist_flat = std.mem.bytesAsSlice(i32, std.mem.asBytes(&self.history));
        for (hist_flat) |*entry| {
            entry.* = entry.* - (entry.* >> 2) + 64;
        }

        const threat_flat = std.mem.bytesAsSlice(i32, std.mem.asBytes(&self.threat_history));
        for (threat_flat) |*entry| {
            entry.* = entry.* - (entry.* >> 2) + 64;
        }

        const cap_flat = std.mem.bytesAsSlice(i16, std.mem.asBytes(&self.capture_history));
        for (cap_flat) |*entry| {
            entry.* -= (entry.* >> 2);
        }

        const cont_flat = std.mem.bytesAsSlice(i16, std.mem.asBytes(self.continuation));
        for (cont_flat) |*entry| {
            entry.* -= (entry.* >> 2);
        }
    }
}

pub inline fn historyBonus(depth: i32) i32 {
    return @max(1, @min(tp.hist_bonus_max.value, tp.hist_bonus_mul.value * depth - tp.hist_bonus_offset.value));
}

inline fn historyMalus(depth: i32) i32 {
    return @max(0, @min(tp.hist_malus_max.value, tp.hist_malus_mul.value * depth - tp.hist_malus_offset.value));
}

inline fn applyBonus(comptime T: type, entry: *T, delta: i32, max: i32) void {
    const v: i32 = entry.*;
    const updated = v + delta - @divTrunc(v * @as(i32, @intCast(@abs(delta))), max);
    entry.* = @intCast(std.math.clamp(updated, -max, max));
}

pub fn updateCorrection(
    self: *Searcher,
    color: brd.Color,
    gs: *const brd.GameState,
    best_move: mvs.Move,
    best_score: i32,
    static_eval: i32,
    depth: usize,
) void {
    _ = best_move;
    const pos = &gs.cur_position;
    const corr_idx = pos.pawn_hash & 16383;
    const np_white_corr_idx = pos.non_pawn_hash[@intFromEnum(brd.Color.White)] & 16383;
    const np_black_corr_idx = pos.non_pawn_hash[@intFromEnum(brd.Color.Black)] & 16383;
    const minor_corr_idx = pos.minor_hash & 16383;
    const major_corr_idx = pos.major_hash & 16383;

    const err = best_score - static_eval;
    const depth_i32 = @as(i32, @intCast(depth));
    const c = @as(usize, @intFromEnum(color));

    const corr_limit: i32 = 16000;

    // Pawn correction
    const pawn_weight: i32 = @min(128, depth_i32 * 16);
    const pawn_entry = &self.correction[c][@as(usize, @intCast(corr_idx))];
    const pawn_old: i32 = pawn_entry.*;
    pawn_entry.* = @intCast(std.math.clamp(
        pawn_old + @divTrunc(err * pawn_weight - pawn_old * pawn_weight, 256),
        -corr_limit, corr_limit,
    ));

    const np_weight: i32 = @min(128, depth_i32 * 16);

    const npw_entry = &self.np_white_correction[c][@as(usize, @intCast(np_white_corr_idx))];
    const npw_old: i32 = npw_entry.*;
    npw_entry.* = @intCast(std.math.clamp(
        npw_old + @divTrunc(err * np_weight - npw_old * np_weight, 256),
        -corr_limit, corr_limit,
    ));

    const npb_entry = &self.np_black_correction[c][@as(usize, @intCast(np_black_corr_idx))];
    const npb_old: i32 = npb_entry.*;
    npb_entry.* = @intCast(std.math.clamp(
        npb_old + @divTrunc(err * np_weight - npb_old * np_weight, 256),
        -corr_limit, corr_limit,
    ));

    const major_weight: i32 = @min(128, depth_i32 * 16);
    const major_entry = &self.major_correction[c][@as(usize, @intCast(major_corr_idx))];
    const major_old: i32 = major_entry.*;
    major_entry.* = @intCast(std.math.clamp(
        major_old + @divTrunc(err * major_weight - major_old * major_weight, 256),
        -corr_limit, corr_limit,
    ));

    const minor_weight: i32 = @min(128, depth_i32 * 16);
    const minor_entry = &self.minor_correction[c][@as(usize, @intCast(minor_corr_idx))];
    const minor_old: i32 = minor_entry.*;
    minor_entry.* = @intCast(std.math.clamp(
        minor_old + @divTrunc(err * minor_weight - minor_old * minor_weight, 256),
        -corr_limit, corr_limit,
    ));
}

pub fn getCorrection(self: *Searcher, color: brd.Color, gs: *const brd.GameState) i32 {
    const pos = &gs.cur_position;
    const corr_idx = pos.pawn_hash & 16383;
    const np_white_corr_idx = pos.non_pawn_hash[@intFromEnum(brd.Color.White)] & 16383;
    const np_black_corr_idx = pos.non_pawn_hash[@intFromEnum(brd.Color.Black)] & 16383;
    const major_corr_idx = pos.major_hash & 16383;
    const minor_corr_idx = pos.minor_hash & 16383;

    const c = @as(usize, @intFromEnum(color));

    const pawn_val: i32 = self.correction[c][@as(usize, @intCast(corr_idx))];
    const npw_val: i32 = self.np_white_correction[c][@as(usize, @intCast(np_white_corr_idx))];
    const npb_val: i32 = self.np_black_correction[c][@as(usize, @intCast(np_black_corr_idx))];
    const major_val: i32 = self.major_correction[c][@as(usize, @intCast(major_corr_idx))];
    const minor_val: i32 = self.minor_correction[c][@as(usize, @intCast(minor_corr_idx))];

    const combined: i32 = pawn_val * tp.corr_pawn_read_weight.value +
        npw_val * tp.corr_np_read_weight.value +
        npb_val * tp.corr_np_read_weight.value +
        major_val * tp.corr_major_read_weight.value +
        minor_val * tp.corr_minor_read_weight.value;

    return @divTrunc(combined, tp.corr_read_divisor.value);
}

pub fn updateContinuation(self: *Searcher, idx: usize, cur_pc: usize, to: usize, delta: i32) void {
    const backs = [_]usize{ 1, 2, 4 };
    for (backs) |b| {
        if (idx < b) continue;
        const prev = self.move_history[idx - b];
        if (prev.isNull()) continue;
        const prev_pc = @as(usize, @intCast(@intFromEnum(self.moved_piece_history[idx - b].color))) * 6 + @as(usize, @intCast(@intFromEnum(self.moved_piece_history[idx - b].piece)));
        applyBonus(i16, &self.continuation[prev_pc][prev.to][cur_pc][to], delta, max_history);
    }
}

pub fn updateQuietMove(self: *Searcher, side: usize, pc: PieceColor, m: mvs.Move, delta: i32, opts: QuietUpdate) void {
    applyBonus(i32, self.butterflyPtr(side, m.from, m.to), delta, max_history);
    if (opts.threats) |t| {
        applyBonus(i32, self.threatHistPtr(side, t, m.from, m.to), delta, max_history);
    }
    if (opts.cont_idx) |idx| {
        const pc_index = @as(usize, @intCast(@intFromEnum(pc.color))) * 6 + @as(usize, @intCast(@intFromEnum(pc.piece)));
        updateContinuation(self, idx, pc_index, m.to, delta);
    }
}

pub fn updateQuietHistory(
    self: *Searcher,
    gs: *const brd.GameState,
    color: brd.Color,
    best_move: mvs.Move,
    quiet_moves: *const mvs.MoveList,
    is_null: bool,
    depth: usize,
    threats: u64,
    cutoff: bool,
) void {
    const pos = &gs.cur_position;
    if (cutoff) {
        if (!self.killer[self.ply][0].eql(best_move)) {
            self.killer[self.ply][1] = self.killer[self.ply][0];
            self.killer[self.ply][0] = best_move;
        }
        if (!is_null and self.ply >= 1) {
            const last = self.move_history[self.ply - 1];
            self.counter_moves[@intFromEnum(color)][last.from][last.to] = best_move;
        }
    }

    const depth_i32 = @as(i32, @intCast(depth));
    const bonus = historyBonus(depth_i32);
    const malus = historyMalus(depth_i32);

    for (quiet_moves.slice()) |m| {
        const is_best = m.eql(best_move);

        const delta = if (is_best) bonus else -malus;

        const h = self.butterflyPtr(@intFromEnum(color), m.from, m.to);
        applyBonus(i32, h, delta, max_history);

        const th = self.threatHistPtr(@intFromEnum(color), threats, m.from, m.to);
        applyBonus(i32, th, delta, max_history);

        if (!is_null and self.ply >= 1) {
            const plies: [3]usize = .{ 0, 1, 3 };
            for (plies) |p| {
                if (self.ply >= p + 1) {
                    const prev = self.move_history[self.ply - p - 1];
                    if (prev.isNull()) continue;

                    const prev_piece_color = self.moved_piece_history[self.ply - p - 1];
                    const prev_pc_index = @as(usize, @intCast(@intFromEnum(prev_piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(prev_piece_color.piece)));

                    const cur_pc_index = @as(usize, @intFromEnum(color)) * 6 + pos.movedPiece(m).piece.idx();

                    const cont = &self.continuation[prev_pc_index][prev.to][cur_pc_index][m.to];
                    applyBonus(i16, cont, delta, max_history);
                    if (self.ply < tp.low_ply_size) {
                        const lp = &self.low_ply_history[self.ply][m.from][m.to];
                        applyBonus(i16, lp, @divTrunc(delta * tp.lph_update_scale.value, 1024), max_history);
                    }
                }
            }
        }
    }
}

pub fn updateCaptureHistory(
    self: *Searcher,
    gs: *const brd.GameState,
    color: brd.Color,
    best_move: mvs.Move,
    other_moves: *const mvs.MoveList,
    depth: usize,
) void {
    const pos = &gs.cur_position;
    const depth_i32 = @as(i32, @intCast(depth));
    const bonus = historyBonus(depth_i32);
    const malus = historyMalus(depth_i32);
    const side = @intFromEnum(color);

    if (best_move.isCapture()) {
        const attacker = pos.movedPiece(best_move).piece.idx();
        const captured = pos.capturedPiece(best_move).piece.idx();
        const best_entry = &self.capture_history[side][attacker][best_move.to][captured];
        applyBonus(i16, best_entry, bonus, max_cap_history);
    }

    // Penalize other captures that were tried but didn't cause the cutoff.
    for (other_moves.slice()) |m| {
        if (!m.isCapture() or m.eql(best_move)) continue;
        const attacker = pos.movedPiece(m).piece.idx();
        const captured = pos.capturedPiece(m).piece.idx();
        const entry = &self.capture_history[side][attacker][m.to][captured];
        applyBonus(i16, entry, -malus, max_cap_history);
    }
}
