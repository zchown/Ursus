const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;
const mvs = root.moves;
const see = root.see;
const srch = root.search;
const tp = root.tp;

const Move = mvs.Move;
const GameState = brd.GameState;

const score_promotion: i32 = 950_000;

pub const Stage = enum(u8) {
    tt_move,
    gen_noisy,
    good_noisy,
    killer_1,
    killer_2,
    counter,
    gen_quiet,
    quiet,
    bad_noisy,
    done,
};

pub const PickedMove = struct {
    move: Move,
    stage: Stage,
    see_passed: ?bool = null,
    see_bound: i32 = 0,

    pub fn seeAtLeast(self: PickedMove, s: *srch.Searcher, gs: *const GameState, threshold: i32) bool {
        if (self.see_passed) |passed| {
            if (passed and threshold <= self.see_bound) return true;
            if (!passed and threshold >= self.see_bound) return false;
        }
        return see.seeAtLeast(gs, s.move_gen, self.move, threshold);
    }
};

const max_bad_noisy = 64;

inline fn isQueenPromo(m: Move) bool {
    return m.isPromo() and m.promoPiece() == .Queen;
}

pub const MovePicker = struct {
    stage: Stage,
    tt_move: Move,
    killer1: Move,
    killer2: Move,
    counter_move: Move,

    list: mvs.MoveList,
    scores: [mvs.max_moves]i32,
    index: usize,

    bad_noisy: [max_bad_noisy]Move,
    bad_count: usize,
    bad_index: usize,

    see_threshold: i32,
    skip_quiets: bool,
    noisy_only: bool,
    allow_quiet_tt: bool,
    is_null: bool,

    info: mvs.MoveGen.LegalInfo,
    info_ready: bool,

    threats: u64,
    threats_ready: bool,

    fn reset(self: *MovePicker, hash_move: Move) void {
        self.stage = .tt_move;
        self.tt_move = hash_move;
        self.killer1 = Move.none;
        self.killer2 = Move.none;
        self.counter_move = Move.none;
        self.list.len = 0;
        self.index = 0;
        self.bad_count = 0;
        self.bad_index = 0;
        self.see_threshold = 0;
        self.skip_quiets = false;
        self.noisy_only = false;
        self.allow_quiet_tt = true;
        self.is_null = false;
        self.info_ready = false;
        self.threats = 0;
        self.threats_ready = false;
    }

    pub fn init(self: *MovePicker, hash_move: Move, is_null: bool) void {
        self.reset(hash_move);
        self.is_null = is_null;
    }

    pub fn setThreats(self: *MovePicker, t: u64) void {
        self.threats = t;
        self.threats_ready = true;
    }

    fn ensureThreats(self: *MovePicker, s: *srch.Searcher, gs: *const GameState) u64 {
        if (!self.threats_ready) {
            self.threats = srch.computeThreats(s.move_gen, gs, gs.to_move.opposite());
            self.threats_ready = true;
        }
        return self.threats;
    }

    pub fn initNoisy(self: *MovePicker, hash_move: Move) void {
        self.reset(hash_move);
        self.noisy_only = true;
        self.allow_quiet_tt = false;
    }

    pub fn initProbcut(self: *MovePicker, hash_move: Move, see_threshold: i32) void {
        self.reset(hash_move);
        self.noisy_only = true;
        self.allow_quiet_tt = true;
        self.see_threshold = see_threshold;
    }

    fn ensureInfo(self: *MovePicker, s: *srch.Searcher, gs: *const GameState) void {
        if (!self.info_ready) {
            self.info = s.move_gen.legalInfo(gs);
            self.info_ready = true;
        }
    }

    inline fn legal(self: *MovePicker, s: *srch.Searcher, gs: *const GameState, m: Move) bool {
        self.ensureInfo(s, gs);
        return s.move_gen.isLegal(gs, m, &self.info);
    }

    fn pickBest(self: *MovePicker) Move {
        var best_idx = self.index;
        var j = self.index + 1;
        while (j < self.list.len) : (j += 1) {
            if (self.scores[j] > self.scores[best_idx]) {
                best_idx = j;
            }
        }
        if (best_idx != self.index) {
            std.mem.swap(Move, &self.list.moves[self.index], &self.list.moves[best_idx]);
            std.mem.swap(i32, &self.scores[self.index], &self.scores[best_idx]);
        }
        return self.list.moves[self.index];
    }

    fn isTTDup(self: *MovePicker, move: Move) bool {
        return !self.tt_move.isNull() and move.eql(self.tt_move);
    }

    fn scoreNoisy(self: *MovePicker, s: *srch.Searcher, gs: *const GameState) void {
        const pos = &gs.cur_position;
        const side = @intFromEnum(gs.to_move);
        for (self.list.slice(), 0..) |move, i| {
            if (move.isCapture()) {
                const victim = @intFromEnum(pos.capturedPiece(move).piece);
                const attacker = @intFromEnum(pos.movedPiece(move).piece);
                const capthist: i32 = s.capture_history[side][attacker][move.to][victim];

                var score: i32 = tp.see_weight.value * see.see_values[victim] +
                    @divTrunc(capthist * 10, tp.capthist_div.value);
                if (isQueenPromo(move)) {
                    score += score_promotion;
                }
                self.scores[i] = score;
            } else {
                // Quiet queen promotion
                self.scores[i] = score_promotion;
            }
        }
    }

    fn scoreQuiets(self: *MovePicker, s: *srch.Searcher, gs: *const GameState) void {
        const pos = &gs.cur_position;
        const side = @intFromEnum(gs.to_move);
        const threats = self.ensureThreats(s, gs);
        for (self.list.slice(), 0..) |move, i| {
            if (move.isPromo()) {
                self.scores[i] = -5_000;
                continue;
            }

            var score: i32 = s.quietHistScore(side, threats, move.from, move.to);
            if (!self.is_null and s.ply >= 1) {
                const cur_pc_index = @as(usize, side) * 6 + pos.movedPiece(move).piece.idx();
                const plies: [3]usize = .{ 0, 1, 3 };
                for (plies) |p| {
                    if (s.ply >= p + 1) {
                        const prev = s.move_history[s.ply - p - 1];
                        if (prev.isNull()) continue;
                        const prev_piece_color = s.moved_piece_history[s.ply - p - 1];
                        const prev_pc_index = @as(usize, @intCast(@intFromEnum(prev_piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(prev_piece_color.piece)));

                        score += s.continuation[prev_pc_index][prev.to][cur_pc_index][move.to];
                        if (s.ply < tp.low_ply_size) {
                            const lph: i32 = s.low_ply_history[s.ply][move.from][move.to];
                            score += @divTrunc(@divTrunc(lph * tp.lph_order_mul.value, 10), @as(i32, @intCast(s.ply + 1)));
                        }
                    }
                }
            }
            self.scores[i] = score;
        }
    }

    fn trySpecialQuiet(self: *MovePicker, s: *srch.Searcher, gs: *const GameState, candidate: Move) ?Move {
        if (candidate.isNull() or !candidate.isQuiet()) return null;
        if (self.isTTDup(candidate)) return null;
        if (candidate.eql(self.killer1) or candidate.eql(self.killer2)) return null;

        if (!s.move_gen.isPseudoLegal(gs, candidate)) return null;
        if (!self.legal(s, gs, candidate)) return null;
        return candidate;
    }

    pub fn next(self: *MovePicker, s: *srch.Searcher, gs: *const GameState) ?PickedMove {
        while (true) {
            switch (self.stage) {
                .tt_move => {
                    self.stage = .gen_noisy;
                    const m = self.tt_move;
                    if (!m.isNull()) {
                        if ((self.allow_quiet_tt or m.isNoisy()) and
                            s.move_gen.isPseudoLegal(gs, m) and self.legal(s, gs, m))
                        {
                            return PickedMove{ .move = m, .stage = .tt_move };
                        }
                        self.tt_move = Move.none;
                    }
                },

                .gen_noisy => {
                    self.list.clear();
                    s.move_gen.appendMoves(gs, .captures, &self.list);
                    self.scoreNoisy(s, gs);
                    self.index = 0;
                    self.stage = .good_noisy;
                },

                .good_noisy => {
                    while (self.index < self.list.len) {
                        const m = self.pickBest();
                        self.index += 1;

                        if (self.isTTDup(m)) continue;
                        if (!self.legal(s, gs, m)) continue;

                        if (m.isCapture()) {
                            const good = see.seeAtLeast(gs, s.move_gen, m, self.see_threshold);
                            if (!good and self.bad_count < max_bad_noisy) {
                                self.bad_noisy[self.bad_count] = m;
                                self.bad_count += 1;
                                continue;
                            }
                            return PickedMove{ .move = m, .stage = .good_noisy, .see_passed = good, .see_bound = self.see_threshold };
                        }

                        return PickedMove{ .move = m, .stage = .good_noisy };
                    }
                    self.stage = if (self.noisy_only) .bad_noisy else .killer_1;
                },

                .killer_1 => {
                    self.stage = .killer_2;
                    if (self.trySpecialQuiet(s, gs, s.killer[s.ply][0])) |m| {
                        self.killer1 = m;
                        return PickedMove{ .move = m, .stage = .killer_1 };
                    }
                },

                .killer_2 => {
                    self.stage = .counter;
                    if (self.trySpecialQuiet(s, gs, s.killer[s.ply][1])) |m| {
                        self.killer2 = m;
                        return PickedMove{ .move = m, .stage = .killer_2 };
                    }
                },

                .counter => {
                    self.stage = .gen_quiet;
                    if (s.ply > 0) {
                        const last = s.move_history[s.ply - 1];
                        if (!last.isNull()) {
                            const side = @intFromEnum(gs.to_move);
                            const cm = s.counter_moves[side][last.from][last.to];
                            if (self.trySpecialQuiet(s, gs, cm)) |m| {
                                self.counter_move = m;
                                return PickedMove{ .move = m, .stage = .counter };
                            }
                        }
                    }
                },

                .gen_quiet => {
                    if (self.skip_quiets) {
                        self.stage = .bad_noisy;
                        continue;
                    }
                    self.list.clear();
                    s.move_gen.appendMoves(gs, .quiets, &self.list);
                    self.scoreQuiets(s, gs);
                    self.index = 0;
                    self.stage = .quiet;
                },

                .quiet => {
                    if (self.skip_quiets) {
                        self.stage = .bad_noisy;
                        continue;
                    }
                    while (self.index < self.list.len) {
                        const m = self.pickBest();
                        self.index += 1;

                        if (self.isTTDup(m)) continue;
                        if (m.eql(self.killer1) or
                            m.eql(self.killer2) or
                            m.eql(self.counter_move)) continue;
                        if (!self.legal(s, gs, m)) continue;

                        return PickedMove{ .move = m, .stage = .quiet };
                    }
                    self.stage = .bad_noisy;
                },

                .bad_noisy => {
                    if (self.bad_index < self.bad_count) {
                        const bm = self.bad_noisy[self.bad_index];
                        self.bad_index += 1;
                        return PickedMove{ .move = bm, .stage = .bad_noisy, .see_passed = false, .see_bound = self.see_threshold };
                    }
                    self.stage = .done;
                },

                .done => return null,
            }
        }
    }
};

pub fn verifyPicker(s: *srch.Searcher, gs: *const GameState, hash_move: Move) bool {
    const reference = s.move_gen.generateLegal(gs, .all);
    var matched: [mvs.max_moves]bool = .{false} ** mvs.max_moves;

    var picker: MovePicker = undefined;
    picker.init(hash_move, false);
    var ok = true;
    var buf: [5]u8 = undefined;

    while (picker.next(s, gs)) |picked| {
        var found = false;
        for (reference.slice(), 0..) |ref, i| {
            if (ref.eql(picked.move)) {
                if (matched[i]) {
                    std.debug.print("picker yielded duplicate move (stage {s}): {s}\n", .{ @tagName(picked.stage), picked.move.toUci(&buf) });
                    ok = false;
                }
                matched[i] = true;
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("picker yielded illegal/unknown move (stage {s}): {s}\n", .{ @tagName(picked.stage), picked.move.toUci(&buf) });
            ok = false;
        }
    }

    for (reference.slice(), 0..) |ref, i| {
        if (!matched[i]) {
            std.debug.print("picker missed legal move: {s}\n", .{ref.toUci(&buf)});
            ok = false;
        }
    }

    return ok;
}
