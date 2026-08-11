const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const see = @import("see");
const srch = @import("search");
const tp = @import("tunable_parameters");

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
    move: mvs.EncodedMove,
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
    move: mvs.EncodedMove,
    see_val: i32,
    stage: Stage,
};

const no_see: i32 = std.math.minInt(i32);
const max_bad_noisy = 64;

pub const MovePicker = struct {
    stage: Stage,
    tt_move: mvs.EncodedMove,
    killer1: mvs.EncodedMove,
    killer2: mvs.EncodedMove,
    counter_move: mvs.EncodedMove,

    list: mvs.MoveList,
    scores: [218]i32,
    sees: [218]i32,
    index: usize,

    bad_noisy: [max_bad_noisy]MoveWithSee,
    bad_count: usize,
    bad_index: usize,

    see_threshold: i32,
    skip_quiets: bool,
    noisy_only: bool,
    allow_quiet_tt: bool,
    is_null: bool,

    info: mvs.MoveGen.MoveGenInfo,
    info_ready: bool,

    fn base(hash_move: mvs.EncodedMove) MovePicker {
        return MovePicker{
            .stage = .tt_move,
            .tt_move = hash_move,
            .killer1 = mvs.EncodedMove.fromU32(0),
            .killer2 = mvs.EncodedMove.fromU32(0),
            .counter_move = mvs.EncodedMove.fromU32(0),
            .list = mvs.MoveList.init(),
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
        };
    }

    pub fn init(hash_move: mvs.EncodedMove, is_null: bool) MovePicker {
        var p = base(hash_move);
        p.is_null = is_null;
        return p;
    }

    pub fn initNoisy(hash_move: mvs.EncodedMove) MovePicker {
        var p = base(hash_move);
        p.noisy_only = true;
        p.allow_quiet_tt = false;
        return p;
    }

    pub fn initProbcut(hash_move: mvs.EncodedMove, see_threshold: i32) MovePicker {
        var p = base(hash_move);
        p.noisy_only = true;
        p.allow_quiet_tt = true;
        p.see_threshold = see_threshold;
        return p;
    }

    fn ensureInfo(self: *MovePicker, s: *srch.Searcher, board: *brd.Board) void {
        if (!self.info_ready) {
            self.info = s.move_gen.computeMoveGenInfo(board);
            self.info_ready = true;
        }
    }

    fn pickBest(self: *MovePicker, comptime with_see: bool) mvs.EncodedMove {
        var best_idx = self.index;
        var j = self.index + 1;
        while (j < self.list.len) : (j += 1) {
            if (self.scores[j] > self.scores[best_idx]) {
                best_idx = j;
            }
        }
        if (best_idx != self.index) {
            std.mem.swap(mvs.EncodedMove, &self.list.items[self.index], &self.list.items[best_idx]);
            std.mem.swap(i32, &self.scores[self.index], &self.scores[best_idx]);
            if (with_see) {
                std.mem.swap(i32, &self.sees[self.index], &self.sees[best_idx]);
            }
        }
        return self.list.items[self.index];
    }

    fn isTTDup(self: *MovePicker, move: mvs.EncodedMove) bool {
        return self.tt_move.toU32() != 0 and move.matchesTTKey(self.tt_move);
    }

    fn scoreNoisy(self: *MovePicker, s: *srch.Searcher, board: *brd.Board) void {
        const side = @intFromEnum(board.toMove());
        for (self.list.items[0..self.list.len], 0..) |move, i| {
            if (move.capture == 1) {
                const sv = see.seeCapture(board, s.move_gen, move);
                self.sees[i] = sv;

                const capture_piece_idx = @as(usize, @intCast(move.captured_piece));
                const attacking_piece_idx = @as(usize, @intCast(move.piece));
                const capthist = s.capture_history[side][attacking_piece_idx][move.end_square][capture_piece_idx];

                const ordering = tp.see_weight.value * sv +
                    @divTrunc(capthist * 10, tp.capthist_div.value);

                var score: i32 = if (sv >= 0) score_winning_capture + ordering else sv + ordering;

                if (move.promoted_piece == @intFromEnum(brd.Pieces.Queen)) {
                    score += score_promotion;
                }
                self.scores[i] = score;
            } else {
                // Quiet queen promotion: after winning captures, before losers.
                self.sees[i] = 0;
                self.scores[i] = score_promotion;
            }
        }
    }

    fn scoreQuiets(self: *MovePicker, s: *srch.Searcher, board: *brd.Board) void {
        const side = @intFromEnum(board.toMove());
        for (self.list.items[0..self.list.len], 0..) |move, i| {
            if (move.promoted_piece != 0) {
                self.scores[i] = -5_000;
                continue;
            }

            var score: i32 = s.history[side][move.start_square][move.end_square];
            if (!self.is_null and s.ply >= 1) {
                const plies: [3]usize = .{ 0, 1, 3 };
                for (plies) |p| {
                    if (s.ply >= p + 1) {
                        const prev = s.move_history[s.ply - p - 1];
                        if (prev.toU32() == 0) continue;
                        const prev_piece_color = s.moved_piece_history[s.ply - p - 1];
                        const prev_pc_index = @as(usize, @intCast(@intFromEnum(prev_piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(prev_piece_color.piece)));

                        const cur_pc_index = @as(usize, @intCast(side)) * 6 + @as(usize, @intCast(move.piece));

                        score += s.continuation[prev_pc_index][prev.end_square][cur_pc_index][move.end_square];
                    }
                }
            }
            self.scores[i] = score;
        }
    }

    fn trySpecialQuiet(self: *MovePicker, s: *srch.Searcher, board: *brd.Board, candidate: mvs.EncodedMove) ?mvs.EncodedMove {
        if (candidate.toU32() == 0) return null;
        if (candidate.promoted_piece != 0) return null;

        const m = mvs.materializeMove(board, candidate) orelse return null;
        if (m.capture == 1) return null;
        if (self.isTTDup(m)) return null;
        if (m.toU32() == self.killer1.toU32()) return null;
        if (m.toU32() == self.killer2.toU32()) return null;

        self.ensureInfo(s, board);
        if (!s.move_gen.isLegalMoveWithInfo(board, m, &self.info)) return null;
        return m;
    }

    pub fn next(self: *MovePicker, s: *srch.Searcher, board: *brd.Board) ?PickedMove {
        while (true) {
            switch (self.stage) {
                .tt_move => {
                    self.stage = .gen_noisy;
                    if (self.tt_move.toU32() != 0) {
                        if (mvs.materializeMove(board, self.tt_move)) |m| {
                            const is_noisy = m.capture == 1 or
                                m.promoted_piece == @intFromEnum(brd.Pieces.Queen);
                            if (self.allow_quiet_tt or is_noisy) {
                                self.ensureInfo(s, board);
                                if (s.move_gen.isLegalMoveWithInfo(board, m, &self.info)) {
                                    self.tt_move = m;
                                    const sv: i32 = if (m.capture == 1)
                                        see.seeCapture(board, s.move_gen, m)
                                    else if (m.promoted_piece == @intFromEnum(brd.Pieces.Queen))
                                        0
                                    else
                                        no_see;
                                    return PickedMove{ .move = m, .see_val = sv, .stage = .tt_move };
                                }
                            }
                        }
                        self.tt_move = mvs.EncodedMove.fromU32(0);
                    }
                },

                .gen_noisy => {
                    self.ensureInfo(s, board);
                    self.list = s.move_gen.generateMovesWithInfo(board, .captures, &self.info);
                    self.scoreNoisy(s, board);
                    self.index = 0;
                    self.stage = .good_noisy;
                },

                .good_noisy => {
                    while (self.index < self.list.len) {
                        const m = self.pickBest(true);
                        const sv = self.sees[self.index];
                        self.index += 1;

                        if (self.isTTDup(m)) continue;

                        if (m.capture == 1) {
                            if (sv < self.see_threshold and self.bad_count < max_bad_noisy) {
                                self.bad_noisy[self.bad_count] = MoveWithSee{ .move = m, .see_val = sv };
                                self.bad_count += 1;
                                continue;
                            }
                            return PickedMove{ .move = m, .see_val = sv, .stage = .good_noisy };
                        }

                        return PickedMove{ .move = m, .see_val = 0, .stage = .good_noisy };
                    }
                    self.stage = if (self.noisy_only) .bad_noisy else .killer_1;
                },

                .killer_1 => {
                    self.stage = .killer_2;
                    if (self.trySpecialQuiet(s, board, s.killer[s.ply][0])) |m| {
                        self.killer1 = m;
                        return PickedMove{ .move = m, .see_val = no_see, .stage = .killer_1 };
                    }
                },

                .killer_2 => {
                    self.stage = .counter;
                    if (self.trySpecialQuiet(s, board, s.killer[s.ply][1])) |m| {
                        self.killer2 = m;
                        return PickedMove{ .move = m, .see_val = no_see, .stage = .killer_2 };
                    }
                },

                .counter => {
                    self.stage = .gen_quiet;
                    if (s.ply > 0) {
                        const last = s.move_history[s.ply - 1];
                        if (last.toU32() != 0) {
                            const side = @intFromEnum(board.toMove());
                            const cm = s.counter_moves[side][last.start_square][last.end_square];
                            if (self.trySpecialQuiet(s, board, cm)) |m| {
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
                    self.ensureInfo(s, board);
                    self.list = s.move_gen.generateMovesWithInfo(board, .quiets, &self.info);
                    self.scoreQuiets(s, board);
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
                        const mu = m.toU32();
                        if (mu == self.killer1.toU32() or
                            mu == self.killer2.toU32() or
                            mu == self.counter_move.toU32()) continue;

                        return PickedMove{ .move = m, .see_val = no_see, .stage = .quiet };
                    }
                    self.stage = .bad_noisy;
                },

                .bad_noisy => {
                    if (self.bad_index < self.bad_count) {
                        const bm = self.bad_noisy[self.bad_index];
                        self.bad_index += 1;
                        return PickedMove{ .move = bm.move, .see_val = bm.see_val, .stage = .bad_noisy };
                    }
                    self.stage = .done;
                },

                .done => return null,
            }
        }
    }
};

pub fn verifyPicker(s: *srch.Searcher, board: *brd.Board, hash_move: mvs.EncodedMove) bool {
    var reference = s.move_gen.generateMoves(board, false);
    var matched: [218]bool = .{false} ** 218;

    var picker = MovePicker.init(hash_move, false);
    var ok = true;

    while (picker.next(s, board)) |picked| {
        const mu = picked.move.toU32();
        var found = false;
        for (reference.items[0..reference.len], 0..) |ref, i| {
            if (ref.toU32() == mu) {
                if (matched[i]) {
                    std.debug.print("picker yielded duplicate move (stage {s}): ", .{@tagName(picked.stage)});
                    picked.move.print();
                    ok = false;
                }
                matched[i] = true;
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("picker yielded illegal/unknown move (stage {s}): ", .{@tagName(picked.stage)});
            picked.move.print();
            ok = false;
        }
    }

    for (reference.items[0..reference.len], 0..) |ref, i| {
        if (!matched[i]) {
            std.debug.print("picker missed legal move: ", .{});
            ref.print();
            ok = false;
        }
    }

    return ok;
}

