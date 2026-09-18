const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;
const mvs = root.moves;
const see = root.see;
const srch = root.search;
const tp = root.tp;

const Move = mvs.Move;
const GameState = brd.GameState;

const score_hash: i32 = 2_000_000_000;
const score_winning_capture: i32 = 1_000_000;
const score_promotion: i32 = 950_000;
const score_equal_capture: i32 = 900_000;
const score_killer_1: i32 = 700_000;
const score_killer_2: i32 = 690_000;
const score_counter: i32 = 600_000;

pub const ScoredMove = struct {
    score: i32,
    see_val: i32,
};

pub const MoveWithSee = struct {
    move: Move,
    see_val: i32,
};

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
    see_val: i32,
    stage: Stage,
};

const no_see: i32 = std.math.minInt(i32);
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
    sees: [mvs.max_moves]i32,
    index: usize,

    bad_noisy: [max_bad_noisy]MoveWithSee,
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

    fn base(hash_move: Move) MovePicker {
        return MovePicker{
            .stage = .tt_move,
            .tt_move = hash_move,
            .killer1 = Move.none,
            .killer2 = Move.none,
            .counter_move = Move.none,
            .list = .{},
            .scores = undefined,
            .sees = undefined,
            .index = 0,
            .bad_noisy = undefined,
            .bad_count = 0,
            .bad_index = 0,
            .see_threshold = 0,
            .skip_quiets = false,
            .noisy_only = false,
            .allow_quiet_tt = true,
            .is_null = false,
            .info = undefined,
            .info_ready = false,
            .threats = 0,
            .threats_ready = false,
        };
    }

    pub fn init(hash_move: Move, is_null: bool) MovePicker {
        var p = base(hash_move);
        p.is_null = is_null;
        return p;
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

    pub fn initNoisy(hash_move: Move) MovePicker {
        var p = base(hash_move);
        p.noisy_only = true;
        p.allow_quiet_tt = false;
        return p;
    }

    pub fn initProbcut(hash_move: Move, see_threshold: i32) MovePicker {
        var p = base(hash_move);
        p.noisy_only = true;
        p.allow_quiet_tt = true;
        p.see_threshold = see_threshold;
        return p;
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

    fn pickBest(self: *MovePicker, comptime with_see: bool) Move {
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
            if (with_see) {
                std.mem.swap(i32, &self.sees[self.index], &self.sees[best_idx]);
            }
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
                const sv = see.seeCapture(gs, s.move_gen, move);
                self.sees[i] = sv;

                const capture_piece_idx = pos.capturedPiece(move).piece.idx();
                const attacking_piece_idx = pos.movedPiece(move).piece.idx();
                const capthist: i32 = s.capture_history[side][attacking_piece_idx][move.to][capture_piece_idx];

                const ordering = tp.see_weight.value * sv +
                    @divTrunc(capthist * 10, tp.capthist_div.value);

                var score: i32 = if (sv >= 0) score_winning_capture + ordering else sv + ordering;

                if (isQueenPromo(move)) {
                    score += score_promotion;
                }
                self.scores[i] = score;
            } else {
                // Quiet queen promotion
                self.sees[i] = 0;
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
                            const sv: i32 = if (m.isCapture())
                                see.seeCapture(gs, s.move_gen, m)
                            else if (isQueenPromo(m))
                                0
                            else
                                no_see;
                            return PickedMove{ .move = m, .see_val = sv, .stage = .tt_move };
                        }
                        self.tt_move = Move.none;
                    }
                },

                .gen_noisy => {
                    self.list = s.move_gen.generateMoves(gs, .captures);
                    self.scoreNoisy(s, gs);
                    self.index = 0;
                    self.stage = .good_noisy;
                },

                .good_noisy => {
                    while (self.index < self.list.len) {
                        const m = self.pickBest(true);
                        const sv = self.sees[self.index];
                        self.index += 1;

                        if (self.isTTDup(m)) continue;

                        if (m.isCapture()) {
                            if (sv < self.see_threshold and self.bad_count < max_bad_noisy) {
                                self.bad_noisy[self.bad_count] = MoveWithSee{ .move = m, .see_val = sv };
                                self.bad_count += 1;
                                continue;
                            }
                            if (!self.legal(s, gs, m)) continue;
                            return PickedMove{ .move = m, .see_val = sv, .stage = .good_noisy };
                        }

                        if (!self.legal(s, gs, m)) continue;
                        return PickedMove{ .move = m, .see_val = 0, .stage = .good_noisy };
                    }
                    self.stage = if (self.noisy_only) .bad_noisy else .killer_1;
                },

                .killer_1 => {
                    self.stage = .killer_2;
                    if (self.trySpecialQuiet(s, gs, s.killer[s.ply][0])) |m| {
                        self.killer1 = m;
                        return PickedMove{ .move = m, .see_val = no_see, .stage = .killer_1 };
                    }
                },

                .killer_2 => {
                    self.stage = .counter;
                    if (self.trySpecialQuiet(s, gs, s.killer[s.ply][1])) |m| {
                        self.killer2 = m;
                        return PickedMove{ .move = m, .see_val = no_see, .stage = .killer_2 };
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
                                return PickedMove{ .move = m, .see_val = no_see, .stage = .counter };
                            }
                        }
                    }
                },

                .gen_quiet => {
                    if (self.skip_quiets) {
                        self.stage = .bad_noisy;
                        continue;
                    }
                    self.list = s.move_gen.generateMoves(gs, .quiets);
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
                        const m = self.pickBest(false);
                        self.index += 1;

                        if (self.isTTDup(m)) continue;
                        if (m.eql(self.killer1) or
                            m.eql(self.killer2) or
                            m.eql(self.counter_move)) continue;
                        if (!self.legal(s, gs, m)) continue;

                        return PickedMove{ .move = m, .see_val = no_see, .stage = .quiet };
                    }
                    self.stage = .bad_noisy;
                },

                .bad_noisy => {
                    while (self.bad_index < self.bad_count) {
                        const bm = self.bad_noisy[self.bad_index];
                        self.bad_index += 1;
                        if (!self.legal(s, gs, bm.move)) continue;
                        return PickedMove{ .move = bm.move, .see_val = bm.see_val, .stage = .bad_noisy };
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

    var picker = MovePicker.init(hash_move, false);
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
