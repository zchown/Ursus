const std = @import("std");
const root = @import("root.zig");
const mvs = root.moves;
const brd = root.brd;
const eval = root.eval;
const tt = root.tt;
const see = root.see;
const mp = root.mp;
const tp = root.tp;
const hist = root.hist;
const tb = root.tb;

pub const max_ply = 128;
pub const max_game_ply = 1024;
pub const eval_none: i32 = std.math.minInt(i32);

pub const max_root_moves = 218;
pub const max_multipv = 16;

pub var quiet_lmr: [64][64]i32 = undefined;


pub fn initQuietLMR() [64][64]i32 {
    const lmr_base_f: f32 = @as(f32, @floatFromInt(tp.lmr_base.value)) / 100.0;
    const lmr_div_f: f32 = @as(f32, @floatFromInt(tp.lmr_div.value)) / 100.0;
    var table: [64][64]i32 = undefined;
    for (0..64) |d| {
        for (0..64) |m| {
            const df: f32 = @floatFromInt(@max(d, 1));
            const mf: f32 = @floatFromInt(@max(m, 1));
            table[d][m] = @intFromFloat(lmr_base_f + @log(df) * @log(mf) / lmr_div_f);
        }
    }
    return table;
}

inline fn scoreToTT(score: i32, ply: usize) i32 {
    if (score >= eval.win_bound) return score + @as(i32, @intCast(ply));
    if (score <= -eval.win_bound) return score - @as(i32, @intCast(ply));
    return score;
}

inline fn scoreFromTT(score: i32, ply: usize) i32 {
    if (score >= eval.win_bound) return score - @as(i32, @intCast(ply));
    if (score <= -eval.win_bound) return score + @as(i32, @intCast(ply));
    return score;
}

pub var noisy_lmr: [64][64]i32 = undefined;

pub fn initNoisyLMR() [64][64]i32 {
    const lmr_base_f: f32 = @as(f32, @floatFromInt(tp.lmr_noisy_base.value)) / 100.0;
    const lmr_div_f: f32 = @as(f32, @floatFromInt(tp.lmr_noisy_div.value)) / 100.0;
    var table: [64][64]i32 = undefined;
    for (0..64) |d| {
        for (0..64) |m| {
            const df: f32 = @floatFromInt(@max(d, 1));
            const mf: f32 = @floatFromInt(@max(m, 1));
            table[d][m] = @intFromFloat(lmr_base_f + @log(df) * @log(mf) / lmr_div_f);
        }
    }
    return table;
}

pub fn computeThreats(mg: *const mvs.MoveGen, gs: *const brd.GameState, by: brd.Color) u64 {
    const pos = &gs.cur_position;
    const occ = pos.getOccupancy();
    var t: u64 = 0;

    const by_i = @intFromEnum(by);
    var pawns = pos.getPieceColorBoard(.Pawn, by);
    while (pawns != 0) {
        const sq = brd.popLsb(&pawns);
        t |= mg.pawns[by_i][sq];
    }

    var knights = pos.getPieceColorBoard(.Knight, by);
    while (knights != 0) {
        const sq = brd.popLsb(&knights);
        t |= mg.knights[sq];
    }

    var diagonal = pos.diagonalSliders(by);
    while (diagonal != 0) t |= mg.getBishopAttacks(brd.popLsb(&diagonal), occ);

    var straight = pos.straightSliders(by);
    while (straight != 0) t |= mg.getRookAttacks(brd.popLsb(&straight), occ);

    const king = pos.getPieceColorBoard(.King, by);
    if (king != 0) {
        const ksq = brd.lsb(king);
        t |= mg.kings[ksq];
    }

    return t;
}

pub inline fn threatIndex(threats: u64, sq: anytype) usize {
    return @intFromBool(threats & (@as(u64, 1) << @intCast(sq)) != 0);
}


pub const NodeType = enum {
    Root,
    PV,
    NonPV,
};

pub const SearchResult = struct {
    move: mvs.Move,
    score: i32,
    depth: usize,
    nodes: u64,
    time_ms: u64,
    pv: [max_ply]mvs.Move,
    pv_length: usize,
};

pub const RootLine = struct {
    move: mvs.Move = undefined,
    score: i32 = 0,
    pv: [max_ply]mvs.Move = undefined,
    pv_length: usize = 0,
    seldepth: usize = 0,
    valid: bool = false,
};

pub var search_helpers: std.ArrayList(*Searcher) = undefined;

pub var threads: std.ArrayList(std.Thread) = undefined;

pub const Searcher = struct {
    min_depth: usize = 1,
    max_ms: u64 = 0,
    ideal_ms: u64 = 0,
    force_think: bool = false,
    search_depth: usize = 0,
    time_offset: u64 = 0,
    timer: std.time.Timer = undefined,
    prev_depth_ms: u64 = 0,
    chess960: bool = false,

    move_gen: *mvs.MoveGen = undefined,

    soft_max_nodes: ?u64 = null,
    max_nodes: ?u64 = null,

    time_stop: bool = false,

    nodes: u64 = 0,
    tb_hits: u64 = 0,
    ply: usize = 0,
    seldepth: usize = 0,
    stop: bool = false,
    is_searching: bool = false,

    best_move: mvs.Move = undefined,
    best_move_score: i32 = 0,
    pv: [max_ply][max_ply]mvs.Move = undefined,
    pv_length: [max_ply]usize = undefined,

    multi_pv: usize = 1,
    searchmoves: ?[]mvs.Move = null,
    excluded_root_moves: [max_multipv]mvs.Move = undefined,
    excluded_root_count: usize = 0,
    root_moves: [max_root_moves]mvs.Move = undefined,
    root_move_count: usize = 0,
    root_moves_searched: usize = 0,
    root_pv_index: usize = 0,
    root_lines: [max_multipv]RootLine = undefined,

    search_score: i32 = 0,
    perspective: brd.Color = .White,

    eval_history: [max_ply]i32 = undefined,
    move_history: [max_ply]mvs.Move = undefined,
    moved_piece_history: [max_ply]PieceColor = undefined,
    killer: [max_ply][2]mvs.Move = undefined,
    lmr_reduction: [max_ply]i32 = @splat(0),
    history: [2][64][64]i32 = undefined,
    threat_history: [2][2][2][64][64]i32 = undefined,
    low_ply_history: [tp.low_ply_size][64][64]i16 = undefined,
    counter_moves: [2][64][64]mvs.Move = undefined,
    excluded_moves: [max_ply]mvs.Move = undefined,
    continuation: *[12][64][12][64]i16= undefined,
    correction: [2][16384]i16 = undefined,
    np_white_correction: [2][16384]i16 = undefined,
    np_black_correction: [2][16384]i16 = undefined,
    major_correction: [2][16384]i16 = undefined,
    minor_correction: [2][16384]i16 = undefined,
    capture_history: [2][7][64][7]i16 = undefined,
    root_node_counts: [64][64]u64 = undefined,

    optimism: [2]i32 = .{0, 0},
    avg_root_score: i32 = 0,
    avg_root_valid: bool = false,

    thread_id: usize = 0,
    root_board: *brd.GameState = undefined,
    silent_output: bool = false,
    stdout_buffer: [2048]u8 = undefined,

    tt_table: *tt.TranspositionTable = undefined,

    pub const PieceColor = brd.Piece;

    pub fn initInPlace(self: *Searcher) void {
        self.timer = std.time.Timer.start() catch unreachable;
        self.move_gen = std.heap.smp_allocator.create(mvs.MoveGen) catch unreachable;
        self.move_gen.init();
        self.continuation = std.heap.smp_allocator.create([12][64][12][64]i16) catch unreachable;
        hist.resetHeuristics(self, true);
    }

    pub fn deinit(self: *Searcher) void {
        std.heap.smp_allocator.destroy(self.continuation);
        std.heap.smp_allocator.destroy(self.move_gen);
    }

    pub inline fn butterflyPtr(self: *Searcher, side: usize, from: usize, to: usize) *i32 {
        return &self.history[side][from][to];
    }

    pub fn quietStatScore(self: *Searcher, side: usize, threats: u64, pc: PieceColor, m: mvs.Move, use_cont: bool) i32 {
        var s: i32 = self.quietHistScore(side, threats, m.from, m.to) * tp.stat_main_weight.value;
        if (use_cont) {
            const cp = @as(usize, @intFromEnum(pc.color)) * 6 + @intFromEnum(pc.piece);
            s += self.contHistAt(self.ply, 1, cp, m.to) * tp.stat_cont1_weight.value;
            s += self.contHistAt(self.ply, 2, cp, m.to) * tp.stat_cont2_weight.value;
            s += self.contHistAt(self.ply, 4, cp, m.to) * tp.stat_cont4_weight.value;
        }
        return @divTrunc(s, 1024);
    }

    pub inline fn contHistAt(self: *Searcher, idx: usize, back: usize, cur_pc: usize, to: usize) i32 {
        if (idx < back) return 0;
        const prev = self.move_history[idx - back];
        if (prev.isNull()) return 0;
        const prev_pc = @as(usize, @intFromEnum(self.moved_piece_history[idx - back].color)) * 6 + @intFromEnum(self.moved_piece_history[idx - back].piece);
        return self.continuation[prev_pc][prev.to][cur_pc][to];
    }

    pub inline fn threatHistPtr(self: *Searcher, side: usize, threats: u64, from: usize, to: usize) *i32 {
        return &self.threat_history[side][threatIndex(threats, from)][threatIndex(threats, to)][from][to];
    }

    pub inline fn quietHistScore(self: *Searcher, side: usize, threats: u64, from: usize, to: usize) i32 {
        const bf: i32 = self.butterflyPtr(side, from, to).*;
        const th: i32 = self.threatHistPtr(side, threats, from, to).*;
        return @divTrunc(bf * tp.butterfly_weight.value + th * tp.threat_hist_weight.value, 1024);
    }


    pub inline fn capHistOf(self: *const Searcher, gs: *const brd.GameState, color: brd.Color, move: mvs.Move) i32 {
        const pos = &gs.cur_position;
        return self.capture_history[@intFromEnum(color)][pos.movedPiece(move).piece.idx()][move.to][pos.capturedPiece(move).piece.idx()];
    }

    pub inline fn predictedLmrDepth(depth: usize, move_number: usize, is_capture: bool, stat_score: i32) i32 {
        const d = @min(depth, 63);
        const m = @min(move_number, 63);
        const r: i32 = if (is_capture) noisy_lmr[d][m] else quiet_lmr[d][m];
        const hist_adj: i32 = if (is_capture) 0 else @divTrunc(stat_score, tp.history_div.value);
        return @max(0, @as(i32, @intCast(depth)) - 1 - r + hist_adj);
    }

    pub inline fn sameRootMove(a: mvs.Move, b: mvs.Move) bool {
        return a.from == b.from and a.to == b.to and a.promo == b.promo and
            (a.promo == 0 or a.flags == b.flags);
    }

    fn buildRootMoves(self: *Searcher, gs: *brd.GameState) void {
        self.root_move_count = 0;

        const list = self.move_gen.generateLegal(gs, .all);
        for (list.slice()) |move| {

            if (self.searchmoves) |sm| {
                var allowed = false;
                for (sm) |candidate| {
                    if (sameRootMove(move, candidate)) {
                        allowed = true;
                        break;
                    }
                }
                if (!allowed) continue;
            }

            if (self.root_move_count >= max_root_moves) break;
            self.root_moves[self.root_move_count] = move;
            self.root_move_count += 1;
        }
    }

    inline fn isRootMoveAllowed(self: *Searcher, move: mvs.Move) bool {
        for (self.excluded_root_moves[0..self.excluded_root_count]) |excluded| {
            if (sameRootMove(move, excluded)) return false;
        }

        if (self.searchmoves == null) return true;

        for (self.root_moves[0..self.root_move_count]) |allowed| {
            if (sameRootMove(move, allowed)) return true;
        }
        return false;
    }

    fn alreadyExcluded(self: *Searcher, move: mvs.Move) bool {
        for (self.excluded_root_moves[0..self.excluded_root_count]) |excluded| {
            if (sameRootMove(move, excluded)) return true;
        }
        return false;
    }

    pub inline fn should_stop(self: *Searcher) bool {
        if (self.stop) return true;
        if (self.search_depth <= self.min_depth) return false;
        if (self.soft_max_nodes) |soft_limit| {
            if (self.nodes >= soft_limit) return true;
        }
        const thinking = @atomicLoad(bool, &self.force_think, .acquire);
        return self.thread_id == 0 and
            ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
                (!thinking and self.timer.read() / std.time.ns_per_ms >= self.max_ms));
    }

    pub inline fn should_not_continue(self: *Searcher, factor: f32) bool {
        if (self.stop) return true;
        if (self.search_depth <= self.min_depth) return false;
        if (self.soft_max_nodes) |soft_limit| {
            if (self.nodes >= soft_limit) return true;
        }
        const thinking = @atomicLoad(bool, &self.force_think, .acquire);
        const soft_limit_ms = if (self.ideal_ms == std.math.maxInt(u64))
            std.math.maxInt(u64)
            else
            @min(
            @as(u64, @intFromFloat(@as(f32, @floatFromInt(self.ideal_ms)) * factor)),
            self.max_ms,
        );
        return self.thread_id == 0 and
    ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
    (!thinking and self.timer.read() / std.time.ns_per_ms >= soft_limit_ms));
    }

    const ThreadContext = struct {
        searcher: *Searcher,
        gs: *brd.GameState,
        max_depth: ?u8,
    };

    fn helperThreadWorker(ctx: ThreadContext) void {
        _ = ctx.searcher.iterativeDeepening(ctx.gs, ctx.max_depth) catch |err| {
            std.debug.print("Helper thread {} error: {}\n", .{ ctx.searcher.thread_id, err });
        };
    }

    pub fn initHelperThreads(num_threads: usize, shared_tt: *tt.TranspositionTable, chess960: bool) !void {
        if (num_threads <= 1) {
            return; // No helpers needed for single-threaded search
        }

        for (search_helpers.items) |helper| {
            helper.deinit();
            std.heap.smp_allocator.destroy(helper);
        }
        search_helpers.clearRetainingCapacity();
        threads.clearRetainingCapacity();

        try search_helpers.ensureTotalCapacity(std.heap.smp_allocator, num_threads - 1);
        try threads.ensureTotalCapacity(std.heap.smp_allocator, num_threads - 1);

        // Create helper searchers (thread 0 is the main searcher)
        var i: usize = 1;
        while (i < num_threads) : (i += 1) {
            const helper_ptr = try std.heap.smp_allocator.create(Searcher);
            helper_ptr.* = .{};
            helper_ptr.initInPlace();
            helper_ptr.chess960 = chess960;
            helper_ptr.thread_id = i;
            helper_ptr.silent_output = true;
            helper_ptr.tt_table = shared_tt;
            try search_helpers.append(std.heap.smp_allocator, helper_ptr);
        }
    }

    pub fn startParallelSearch(
        main_searcher: *Searcher,
        gs: *brd.GameState,
        max_depth: ?u8,
        num_threads: usize,
    ) !void {
        if (num_threads <= 1) {
            return;
        }

        if (search_helpers.items.len != num_threads - 1) {
            try initHelperThreads(num_threads, main_searcher.tt_table, main_searcher.chess960);
        }

        threads.clearRetainingCapacity();

        main_searcher.root_board = gs;

        for (search_helpers.items) |helper| {
            var board_copy: *brd.GameState = try std.heap.smp_allocator.create(brd.GameState);
            board_copy.copyFrom(gs);

            helper.root_board = board_copy;
            helper.stop = false;
            helper.time_stop = false;

            helper.max_ms = main_searcher.max_ms;
            helper.ideal_ms = main_searcher.ideal_ms;
            helper.min_depth = main_searcher.min_depth;
            helper.force_think = main_searcher.force_think;
            helper.max_nodes = main_searcher.max_nodes;
            helper.soft_max_nodes = main_searcher.soft_max_nodes;

            helper.searchmoves = main_searcher.searchmoves;
            helper.multi_pv = 1;

            const ctx = ThreadContext{
                .searcher = helper,
                .gs = board_copy,
                .max_depth = max_depth,
            };

            const thread = try std.Thread.spawn(.{}, helperThreadWorker, .{ctx});
            try threads.append(std.heap.smp_allocator, thread);
        }
    }

    pub fn waitForHelpers() void {
        for (threads.items) |thread| {
            thread.join();
        }
        threads.clearRetainingCapacity();

        for (search_helpers.items) |helper| {
            std.heap.smp_allocator.destroy(helper.root_board);
        }
    }

    pub fn stopAllThreads() void {
        tt.stop_signal.store(true, .release);

        for (search_helpers.items) |helper| {
            helper.stop = true;
            helper.time_stop = true;
        }
    }

    pub fn parallelIterativeDeepening(
        main_searcher: *Searcher,
        gs: *brd.GameState,
        max_depth: ?u8,
        num_threads: usize,
    ) !SearchResult {
        if (num_threads <= 1) {
            return try main_searcher.iterativeDeepening(gs, max_depth);
        }

        tt.stop_signal.store(false, .release);
        main_searcher.stop = false;
        main_searcher.time_stop = false;

        try startParallelSearch(main_searcher, gs, max_depth, num_threads);

        const result = try main_searcher.iterativeDeepening(gs, max_depth);

        stopAllThreads();

        waitForHelpers();

        var total_nodes = result.nodes;
        for (search_helpers.items) |helper| {
            total_nodes += helper.nodes;
        }

        var final_result = result;
        final_result.nodes = total_nodes;

        return final_result;
    }

    pub fn deinitThreading() void {

        for (search_helpers.items) |helper| {
            helper.deinit();
            std.heap.smp_allocator.destroy(helper);
        }

        search_helpers.deinit(std.heap.smp_allocator);
        threads.deinit(std.heap.smp_allocator);
    }

    pub fn iterativeDeepening(self: *Searcher, gs: *brd.GameState, max_depth: ?u8) !SearchResult {
        self.stop = false;
        self.is_searching = true;
        self.time_stop = false;
        self.time_offset = 0;
        self.prev_depth_ms = 0;
        tt.stop_signal.store(false, .release);
        hist.resetHeuristics(self, false);
        self.nodes = 0;
        self.tb_hits = 0;
        self.root_node_counts = std.mem.zeroes([64][64]u64);
        self.best_move = mvs.Move.none;
        self.best_move_score = -eval.mate_score;
        self.timer = std.time.Timer.start() catch unreachable;
        self.perspective = gs.to_move;
        self.search_score = 0;
        self.root_board = gs;

        self.optimism = .{0, 0};
        self.avg_root_score = 0;
        self.avg_root_valid = false;

        self.excluded_root_count = 0;
        self.root_pv_index = 0;
        self.root_moves_searched = 0;
        for (&self.root_lines) |*line| line.valid = false;

        self.buildRootMoves(gs);

        if (self.root_move_count == 0) {
            self.is_searching = false;
            self.best_move = mvs.Move.none;
            self.best_move_score = 0;
            self.search_depth = 0;
            return SearchResult{
                .move = self.best_move,
                .score = 0,
                .depth = 0,
                .nodes = 0,
                .time_ms = 0,
                .pv = undefined,
                .pv_length = 0,
            };
        }

        const multipv: usize = @max(1, @min(self.multi_pv, @min(self.root_move_count, max_multipv)));

        if (self.thread_id == 0 and tb.isLoaded() and multipv == 1) blk: {
            const piece_count = @popCount(gs.cur_position.getOccupancy());
            if (piece_count > @as(usize, @intCast(tb.largest()))) break :blk;

            const root_probe = tb.probeRootDtz(gs, self.move_gen) orelse break :blk;

            if (self.searchmoves != null) {
                var permitted = false;
                for (self.root_moves[0..self.root_move_count]) |m| {
                    if (sameRootMove(m, root_probe.move)) {
                        permitted = true;
                        break;
                    }
                }
                if (!permitted) break :blk;
            }

            self.tb_hits += 1;
            self.best_move = root_probe.move;
            self.best_move_score = switch (root_probe.wdl) {
                tb.TB_LOSS => -eval.tb_win_score,
                tb.TB_WIN => eval.tb_win_score,
                else => 0,
            };

            var pv_buf: [max_ply]mvs.Move = undefined;
            pv_buf[0] = root_probe.move;

            self.search_depth = 1;
            self.seldepth = 1;

            if (!self.silent_output) {
                self.printInfo(0, 1, self.best_move_score, pv_buf[0..1], 1, std.heap.smp_allocator);
            }

            self.is_searching = false;

            if (self.thread_id == 0) {
                self.tt_table.incrementAge();
            }

            return SearchResult{
                .move = root_probe.move,
                .score = self.best_move_score,
                .depth = 1,
                .nodes = 0,
                .time_ms = (self.timer.read() / std.time.ns_per_ms) -| self.time_offset,
                .pv = pv_buf,
                .pv_length = 1,
            };
        }

        var prev_score: i32 = -eval.mate_score;
        var score: i32 = -eval.mate_score;

        var bm = mvs.Move.none;
        var best_pv: [max_ply]mvs.Move = undefined;
        var best_pv_length: usize = 0;

        var stability: usize = 0;

        var outer_depth: usize = (self.thread_id % 2) + 1;

        const bound: usize = if (max_depth != null) @as(usize, max_depth.?) else max_ply;

        var prev_line_scores: [max_multipv]i32 = @splat(-eval.mate_score);

        outer: while (outer_depth <= bound) : (outer_depth += 1) {
            self.excluded_root_count = 0;

            var pv_idx: usize = 0;
            while (pv_idx < multipv) : (pv_idx += 1) {
                self.root_pv_index = pv_idx;
                self.ply = 0;
                self.seldepth = 0;
                self.search_depth = outer_depth;
                self.best_move = mvs.Move.none;

                const prev_line = prev_line_scores[pv_idx];
                const have_prev = outer_depth > 1 and prev_line != -eval.mate_score;

                var alpha = if (have_prev) prev_line - tp.aspiration_window.value else -eval.mate_score;
                var beta = if (have_prev) prev_line + tp.aspiration_window.value else eval.mate_score;
                var delta: i32 = tp.aspiration_window.value;

                const depth = outer_depth;

                var window_failed = false;

                if (pv_idx == 0 and self.avg_root_valid) {
                    const avg = self.avg_root_score;
                    const abs_avg: i32 = @intCast(@abs(avg));
                    const o = @divTrunc(tp.optimism_scale.value * avg, abs_avg + tp.optimism_stretch.value);
                    self.optimism[@intFromEnum(self.perspective)] = o;
                    self.optimism[@intFromEnum(self.perspective.opposite())] = -o;
                }

                var line_score: i32 = -eval.mate_score;

                while (true) {
                    self.root_moves_searched = 0;

                    line_score = self.negamax(gs, gs.to_move, depth, alpha, beta, false, NodeType.Root, false);

                    if (self.time_stop or self.should_stop()) {
                        self.time_stop = true;
                        tt.stop_signal.store(true, .release);
                        break :outer;
                    }

                    if (line_score <= alpha) {
                        alpha = @max(alpha - delta, -eval.mate_score);
                        delta = @min(delta * 2, eval.mate_score);
                        window_failed = true;
                    } else if (line_score >= beta) {
                        beta = @min(beta + delta, eval.mate_score);
                        delta = @min(delta * 2, eval.mate_score);
                        window_failed = false;
                    } else {
                        window_failed = false;
                        break;
                    }
                }

                if (pv_idx == 0) score = line_score;

                if (self.root_moves_searched == 0 or self.best_move.isNull()) break;

                prev_line_scores[pv_idx] = line_score;
                self.root_lines[pv_idx] = .{
                    .move = self.best_move,
                    .score = line_score,
                    .pv = self.pv[0],
                    .pv_length = self.pv_length[0],
                    .seldepth = self.seldepth,
                    .valid = true,
                };

                if (pv_idx == 0) {
                    if (!self.best_move.eql(bm)) {
                        stability = 0;
                    } else {
                        stability += 1;
                    }

                    if (!window_failed) {
                        bm = self.best_move;
                        best_pv = self.pv[0];
                        best_pv_length = self.pv_length[0];
                    }
                }

                if (!self.silent_output) {
                    var total_nodes = self.nodes;
                    var total_tb_hits = self.tb_hits;
                    for (search_helpers.items) |helper| {
                        total_nodes += helper.nodes;
                        total_tb_hits += helper.tb_hits;
                    }

                    const line = &self.root_lines[pv_idx];
                    self.printInfo(
                        total_nodes,
                        total_tb_hits,
                        line.score,
                        line.pv[0..line.pv_length],
                        pv_idx + 1,
                        std.heap.smp_allocator,
                    );
                }

                if (self.excluded_root_count >= max_multipv or self.alreadyExcluded(self.best_move)) break;
                self.excluded_root_moves[self.excluded_root_count] = self.best_move;
                self.excluded_root_count += 1;
            }

            self.root_pv_index = 0;
            self.excluded_root_count = 0;

            const stability_idx = @min(stability, tp.tm_stability_scale.values.len - 1);
            var factor: f32 = tp.tm_stability_scale.values[stability_idx];

            if (score - prev_score > tp.aspiration_window.value) {
                factor *= 1.3;
            } else if (prev_score - score > tp.aspiration_window.value) {
                factor *= 1.5;
            }

            if (outer_depth >= tp.tm_nodetm_min_depth.value and !bm.isNull() and self.nodes > 0) {
                const bm_nodes = self.root_node_counts[bm.from][bm.to];
                const bm_frac = @as(f32, @floatFromInt(bm_nodes)) / @as(f32, @floatFromInt(self.nodes));
                factor *= std.math.clamp((tp.tm_nodetm_base.value - bm_frac) * tp.tm_nodetm_mul.value, 0.55, 1.80);
            }

            factor = std.math.clamp(factor, 0.35, 2.75);

            if (!self.avg_root_valid) {
                self.avg_root_score = score;
                self.avg_root_valid = true;
            } else {
                self.avg_root_score = @divTrunc(self.avg_root_score + score, 2);
            }

            prev_score = score;
            self.search_score = score;

            const now_ms = self.timer.read() / std.time.ns_per_ms;
            const this_depth_ms = now_ms -| self.prev_depth_ms;
            self.prev_depth_ms = now_ms;

            const predicted_next_ms = this_depth_ms * 3;
            const thinking = @atomicLoad(bool, &self.force_think, .acquire);
            if (!thinking and now_ms +| predicted_next_ms > self.max_ms) {
                break;
            }

            if (self.soft_max_nodes) |soft_limit| {
                if (self.nodes >= soft_limit) break;
            }

            if (self.should_not_continue(factor)) {
                break;
            }
        }

        self.best_move = bm;

        self.is_searching = false;

        self.tt_table.incrementAge();

        // Guard against null moves
        if (self.best_move.isNull() and self.root_move_count > 0) {
            self.best_move = self.root_moves[0];

            if (self.tt_table.get(gs.cur_position.hash)) |e| {
                for (self.root_moves[0..self.root_move_count]) |move| {
                    if (move.eql(e.move)) {
                        self.best_move = move;
                        break;
                    }
                }
            }
        }

        return SearchResult{
            .move = self.best_move,
            .score = self.best_move_score,
            .depth = self.search_depth,
            .nodes = self.nodes,
            .time_ms = (self.timer.read() / std.time.ns_per_ms) -| self.time_offset,
            .pv = best_pv,
            .pv_length = best_pv_length,
        };
    }

    pub fn negamax(self: *Searcher, gs: *brd.GameState, color: brd.Color, depth_: usize, alpha_: i32, beta_: i32, is_null: bool, comptime node_type: NodeType, cutnode: bool) i32 {
        var alpha = alpha_;
        const beta = beta_;
        var depth = depth_;

        if (self.nodes & 2047 == 0 and self.should_stop()) {
            self.time_stop = true;
            tt.stop_signal.store(true, .release);
            return 0;
        }

        self.pv_length[self.ply] = 0;

        if (self.ply >= max_ply - 1) {
            return eval.adjustEval(gs, self.optimism[@intFromEnum(color)], gs.evaluateNNUE(), 0);
        }

        if (gs.isDraw(self.ply)) {
            return 0;
        }

        self.seldepth = @max(self.seldepth, self.ply);

        const is_root = comptime (node_type == NodeType.Root);
        const on_pv = comptime (node_type != NodeType.NonPV);

        if (depth == 0) {
            return self.qsearch(gs, color, alpha, beta, on_pv);
        }

        // mate distance pruning
        if (!is_root) {
            const r_alpha = @max(alpha, -eval.mate_score + @as(i32, @intCast(self.ply)));
            const r_beta = @min(beta, eval.mate_score - @as(i32, @intCast(self.ply + 1)));

            if (r_alpha >= r_beta) {
                return r_alpha;
            }
        }

        self.nodes += 1;

        // TT lookup happens before isInCheck so we can reuse the stored in_check flag
        // on hits, saving an expensive bitboard traversal on the common TT-hit path.
        var hash_move = mvs.Move.none;
        var tt_hit = false;
        var tt_eval: i32 = 0;
        var tt_static_eval: i32 = 0;
        var tt_e_flag: tt.EstimationType = .None;
        var tt_depth: usize = 0;
        var tt_in_check: bool = false;
        var tt_is_pv: bool = false;
        var tt_static_eval_valid: bool = false;
        const entry = self.tt_table.get(gs.cur_position.hash);

        if (entry) |e| {
            tt_hit = true;
            tt_eval = scoreFromTT(e.eval, self.ply);
            tt_depth = @as(usize, @intCast(e.depth));
            tt_e_flag = e.flag;
            tt_static_eval = e.static_eval;
            tt_in_check = e.in_check;
            tt_is_pv = e.is_pv;
            tt_static_eval_valid = e.static_eval_valid;

            hash_move = e.move;

            if (is_root and self.root_pv_index == 0) {
                self.best_move_score = tt_eval;
            }

            if (!on_pv and !is_root and self.excluded_moves[self.ply].isNull() and e.depth >= @as(u8, @intCast(depth))) {
                const cut = switch (e.flag) {
                    .Exact => true,
                    .Under => tt_eval >= beta,
                    .Over => tt_eval <= alpha,
                    .None => false,
                };
                if (cut) {
                    return tt_eval;
                }
            }
        }

        const in_check: bool = self.move_gen.isInCheck(&gs.cur_position, color);
        const tt_pv: bool = on_pv or (tt_hit and tt_is_pv);

        if (!is_root and self.excluded_moves[self.ply].isNull() and depth >= tp.tb_probe_depth) {
            const tb_max = tb.largest();
            if (tb_max > 0) {
                const piece_count = @popCount(gs.cur_position.getOccupancy());
                if (piece_count <= @as(usize, @intCast(tb_max))) {
                    if (tb.probeWdl(gs)) |wdl| {
                        self.tb_hits += 1;

                        const tb_score: i32 = switch (wdl) {
                            tb.TB_LOSS => -eval.tb_win_score,
                            tb.TB_WIN => eval.tb_win_score,
                            else => 0,
                        };
                        const tb_flag: tt.EstimationType = switch (wdl) {
                            tb.TB_LOSS => .Over,
                            tb.TB_WIN => .Under,
                            else => .Exact,
                        };

                        const cutoff = (tb_flag == .Exact) or
                            (tb_flag == .Under and tb_score >= beta) or
                            (tb_flag == .Over and tb_score <= alpha);

                        if (cutoff) {
                            const tdepth: u8 = @intCast(@min(depth + 6, 255));
                            self.tt_table.set(tt.Entry{
                                .hash = gs.cur_position.hash,
                                .eval = tb_score,
                                .move = mvs.Move.none,
                                .static_eval = 0,
                                .flag = tb_flag,
                                .depth = tdepth,
                                .age = self.tt_table.getAge(),
                                .in_check = in_check,
                                .is_pv = tt_pv,
                                .static_eval_valid = !in_check,
                            });
                            return tb_score;
                        }
                    }
                }
            }
        }

        var static_eval: i32 = undefined;
        var raw_static_eval: i32 = 0;

        if (in_check) {
            static_eval = -eval.mate_score + @as(i32, @intCast(self.ply));
            self.eval_history[self.ply] = eval_none;
        } else if (!self.excluded_moves[self.ply].isNull()) {
            static_eval = self.eval_history[self.ply];
        } else if (tt_hit and tt_static_eval_valid) {
            raw_static_eval = tt_static_eval;
            const corrected = hist.getCorrection(self, color, gs);
            static_eval = eval.adjustEval(gs, self.optimism[@intFromEnum(color)], raw_static_eval, corrected);

            self.eval_history[self.ply] = static_eval;
        } else {
            raw_static_eval = gs.evaluateNNUE();
            const correction = hist.getCorrection(self, color, gs);
            static_eval = eval.adjustEval(gs, self.optimism[@intFromEnum(color)], raw_static_eval, correction);
            self.eval_history[self.ply] = static_eval;
        }

        var best_score: i32 = if (is_root) -eval.mate_score else static_eval;

        var improving = false;
        if (!in_check) {
            if (self.ply >= 2 and self.eval_history[self.ply - 2] != eval_none) {
                improving = static_eval > self.eval_history[self.ply - 2];
            } else if (self.ply >= 4 and self.eval_history[self.ply - 4] != eval_none) {
                improving = static_eval > self.eval_history[self.ply - 4];
            } else {
                improving = false;
            }
        }


        if (self.ply > 0) {
            const prior_reduction = self.lmr_reduction[self.ply - 1];
            self.lmr_reduction[self.ply - 1] = 0;

            const parent_eval = self.eval_history[self.ply - 1];
            if (prior_reduction > 0 and !in_check and parent_eval != eval_none and
                self.excluded_moves[self.ply].isNull())
            {
                const eval_sum = static_eval + parent_eval;
                if (prior_reduction >= tp.hindsight_ext_min_red and eval_sum <= 0) {
                    depth += 1;
                } else if (prior_reduction >= tp.hindsight_red_min_red and depth >= 2 and eval_sum > tp.hindsight_red_margin.value) {
                    depth -= 1;
                }
            }
        }

        const has_non_pawns = gs.cur_position.hasNonPawnMaterial(color);

        var last_move: mvs.Move = mvs.Move.none;
        if (self.ply > 0) {
            last_move = self.move_history[self.ply - 1];
        }
        var last_last_last_move = mvs.Move.none;
        if (self.ply > 2) {
            last_last_last_move = self.move_history[self.ply - 3];
        }

        if (depth >= 3 and !in_check and hash_move.isNull() and self.excluded_moves[self.ply].isNull() and (on_pv or cutnode)) {
            depth -= 1;
        }

        if (!in_check and !on_pv and self.excluded_moves[self.ply].isNull()) {
            var pruning_eval = static_eval;
            if (tt_hit and !in_check and tt_eval < eval.win_bound and tt_eval > -eval.win_bound) {
                const use_tt = switch (tt_e_flag) {
                    .Exact => true,
                    .Under => tt_eval > static_eval,
                    .Over => tt_eval < static_eval,
                    .None => false,
                };
                if (use_tt) pruning_eval = tt_eval;
            }

            // reverse futility pruning
            if (@abs(beta) < eval.win_bound and
                depth <= @as(usize, @intCast(tp.rfp_depth)))
            {
                var n: i32 = @as(i32, @intCast(depth)) * tp.rfp_mul.value;

                if (improving) {
                    n -= tp.rfp_improve.value;
                }

                if (pruning_eval - n >= beta) {
                    return pruning_eval - n;
                }
            }

            // razoring
            if (depth <= 4) {
                const threshold = tp.razoring_base.value + (tp.razoring_mul.value * @as(i32, @intCast(depth)));
                if (pruning_eval + threshold < alpha) {
                    return self.qsearch(gs, color, alpha, beta, false);
                }
            }

            // null move pruning
            var nmp_static_eval: i32 = pruning_eval;
            if (improving) {
                nmp_static_eval += tp.nmp_improve.value;
            }

            if (!is_null and depth >= 3 and nmp_static_eval >= beta and has_non_pawns) {
                var r = tp.nmp_base.value + depth / tp.nmp_depth_div.value;
                const diff = pruning_eval - beta;
                const div = @divTrunc(diff, @as(i32, @intCast(tp.nmp_beta_div.value)));
                r += @as(usize, @intCast(@max(0, @min(4, div))));

                if (cutnode) {
                    r += 1;
                }

                r = @min(r, depth);

                self.move_history[self.ply] = mvs.Move.none;
                self.moved_piece_history[self.ply] = PieceColor{
                    .piece = .None,
                    .color = .White
                };
                self.ply += 1;
                gs.makeNullMove();
                var null_score = -self.negamax(gs, color.opposite(), depth - r, -beta, -beta + 1, true, NodeType.NonPV, false);
                self.ply -= 1;
                gs.unmakeNullMove();

                if (self.time_stop) {
                    return 0;
                }

                if (null_score >= beta) {
                    if (null_score >= eval.win_bound) {
                        null_score = beta;
                    }
                    return null_score;
                }
            }
        }

        var quiet_moves: mvs.MoveList = .{};
        var other_moves: mvs.MoveList = .{};

        self.killer[self.ply + 1][0] = mvs.Move.none;
        self.killer[self.ply + 1][1] = mvs.Move.none;

        var best_move = mvs.Move.none;
        var alpha_move = mvs.Move.none;
        best_score = -eval.mate_score + @as(i32, @intCast(self.ply));


        // Probcut
        var probcut_beta = beta + tp.probcut_margin.value;

        if (improving) {
            probcut_beta += (tp.probcut_improve.value - 1000);
        }


        if (cutnode and depth >= 6 and !in_check and beta < eval.win_bound and beta > -eval.win_bound and self.excluded_moves[self.ply].isNull()) {
            const probcut_depth = depth - 3;
            var pc_picker: mp.MovePicker = undefined;
            pc_picker.initProbcut(hash_move, tp.probcut_min_see.value);
            while (pc_picker.next(self, gs)) |pc_picked| {
                const move = pc_picked.move;

                if (pc_picked.stage == .bad_noisy) {
                    break;
                }
                if (!move.isCapture()) {
                    if (!move.eql(hash_move)) {
                        continue;
                    }
                }
                else if (!pc_picked.seeAtLeast(self, gs, tp.probcut_min_see.value)) {
                    break;
                }

                self.move_history[self.ply] = move;
                self.moved_piece_history[self.ply] = gs.cur_position.movedPiece(move);

                gs.makeMove(move);
                self.ply += 1;

                var score = -self.qsearch(gs, color.opposite(), -probcut_beta, -probcut_beta+1, false);

                if (self.time_stop) {
                    gs.unmakeMove(move);
                    self.ply -= 1;
                    return 0;
                }

                if (score >= probcut_beta) {
                    score = -self.negamax(gs, color.opposite(), probcut_depth, -probcut_beta, -probcut_beta+1, false, NodeType.NonPV, true);
                }

                if (self.time_stop) {
                    gs.unmakeMove(move);
                    self.ply -= 1;
                    return 0;
                }

                if (score >= probcut_beta) {
                    // store in TT
                    gs.unmakeMove(move);
                    self.ply -= 1;

                    self.tt_table.set(tt.Entry{
                        .hash = gs.cur_position.hash,
                        .eval = scoreToTT(score, self.ply),
                        .move = move,
                        .static_eval = raw_static_eval,
                        .flag = tt.EstimationType.Under,
                        .depth = @intCast(probcut_depth),
                        .age = self.tt_table.getAge(),
                        .in_check = in_check,
                        .is_pv = tt_pv,
                        .static_eval_valid = !in_check and self.excluded_moves[self.ply].isNull(),
                    });


                    return score;
                } 
                else {
                    gs.unmakeMove(move);
                    self.ply -= 1;
                }
            }
        }

        var skip_quiet: bool = false;
        var quiet_count: usize = 0;
        var other_count: usize = 0;
        var searched_moves: usize = 0;
        var moves_seen: usize = 0;

        const node_threats = computeThreats(self.move_gen, gs, color.opposite());

        var picker: mp.MovePicker = undefined;
        picker.init(hash_move, is_null);

        picker.setThreats(node_threats);

        while (picker.next(self, gs)) |picked| {
            const move = picked.move;

            if (is_root) {
                if (!self.isRootMoveAllowed(move)) continue;
                self.root_moves_searched += 1;
            }

            moves_seen += 1;

            if (move.eql(self.excluded_moves[self.ply])) {
                continue;
            }

            const is_capture = move.isCapture();
            const is_killer = move.eql(self.killer[self.ply][0]) or move.eql(self.killer[self.ply][1]);

            const moved_pc = gs.cur_position.movedPiece(move);
            const stat_score: i32 = if (!is_capture)
                self.quietStatScore(@intFromEnum(color), node_threats, moved_pc, move, !is_null)
                else
                0;

            if (!is_root and moves_seen > 2 and !in_check and !on_pv) {
                var lmp_threshold: usize = tp.lmp_base.value + depth * tp.lmp_mul.value;

                lmp_threshold = @divTrunc(lmp_threshold, 100);

                lmp_threshold += self.thread_id;

                if (improving) {
                    lmp_threshold += @divTrunc(tp.lmp_improve.value, 100);
                }

                if (quiet_count > lmp_threshold) {
                    skip_quiet = true;
                    picker.skip_quiets = true;
                }
            }

            if (!is_capture) {
                quiet_count += 1;
            } else {
                other_count += 1;
            }

            const is_important = is_killer or (move.isPromo() and move.promoPiece() == .Queen);

            if (skip_quiet and !is_capture and !is_important) {
                continue;
            }

            if (!is_capture and !is_important and !in_check and !on_pv and
                depth <= 4 and searched_moves >= 2)
            {
                const hist_threshold: i32 = -@as(i32, @intCast(depth)) * tp.history_prune_mult.value;
                if (stat_score < hist_threshold) {
                    continue;
                }
            }

            // futility pruning
            if (searched_moves >= 1 and !move.isCapture() and depth <= 8 and !in_check and !on_pv and !is_important and static_eval + ((@as(i32, @intCast(depth)) + 1) * tp.futility_mul.value) <= alpha) {
                continue;
            }

            // SEE pruning
            if (!is_capture and !in_check and !on_pv and !is_important and depth <= 6 and searched_moves >= 2) {
                if (!see.seeAtLeast(gs, self.move_gen, move, -@as(i32, @intCast(depth)) * 25)) {
                    continue;
                }
            }

            if (is_capture and !in_check and !on_pv and depth <= 6 and searched_moves >= 2 and !is_important) {
                const d: i32 = @intCast(depth);
                const ch: i32 = self.capHistOf(gs, color, move);
                const margin = -tp.see_capture_mul.value * d * d -
                @divTrunc(ch, tp.see_capthist_div.value);
                if (!picked.seeAtLeast(self, gs, margin)) {
                    continue;
                }
            }

            if (!is_capture) {
                quiet_moves.add(move);
            } else {
                other_moves.add(move);
            }

            var extension: i32 = 0;

            // Singular Extensions, also double and triple
            if (!is_root and
            self.excluded_moves[self.ply].isNull() and
            depth >= tp.se_min_depth and
            tt_hit and
            !hash_move.isNull() and
            move.eql(hash_move) and
            tt_depth + 3 >= depth and
        (tt_e_flag == .Under or tt_e_flag == .Exact) and
            tt_eval < eval.win_bound and
            tt_eval > -eval.win_bound)
        {
                const s_beta: i32 = tt_eval - @divTrunc(@as(i32, @intCast(depth)) * tp.se_margin.value, 100);
                const s_depth: usize = (depth - 1) / 2;

                self.excluded_moves[self.ply] = move;
                const s_score = self.negamax(gs, color, s_depth, s_beta - 1, s_beta, false, NodeType.NonPV, cutnode);
                self.excluded_moves[self.ply] = mvs.Move.none;

                if (self.time_stop) return 0;

                if (s_score < s_beta) {
                    extension = 1;
                } else if (!on_pv and s_score >= beta and !eval.almostMate(s_score)) {
                    return s_score;
                } else if (tt_eval >= beta) {
                    extension = -2;
                }
            }

            if (!is_root and self.ply <= depth and !hash_move.isCapture()) {
                if (is_capture and last_move.isCapture() and move.to == last_move.to) {
                    extension += 1;
                } else if (is_capture and self.ply >= 3 and last_last_last_move.isCapture() and
                    move.to == last_last_last_move.to)
                {
                    extension += 1;
                }
            }

            self.move_history[self.ply] = move;
            self.moved_piece_history[self.ply] = gs.cur_position.movedPiece(move);

            const nodes_before_move: u64 = if (is_root) self.nodes else 0;

            self.ply += 1;

            gs.makeMove(move);
            searched_moves += 1;

            var nd: i32 = @as(i32, @intCast(depth)) + extension - 1;
            if (nd < 0) {
                nd = 0;
            }

            const new_depth: usize = @as(usize, @intCast(nd));

            self.tt_table.prefetch(gs.cur_position.hash);

            var score: i32 = 0;

            const min_lmr_move: usize = if (on_pv) tp.lmr_pv_min else tp.lmr_non_pv_min;
            var do_full_search = false;



            if (on_pv and searched_moves == 1) {
                score = -self.negamax(gs, color.opposite(), new_depth, -beta, -alpha, false, NodeType.PV, false);
            } else {
                if (!in_check and depth >= 3 and searched_moves > min_lmr_move) {
                    var reduction: i32 = if (is_capture)
                        noisy_lmr[@min(depth, 63)][@min(searched_moves, 63)]
                    else
                        quiet_lmr[@min(depth, 63)][@min(searched_moves, 63)];

                    if (improving) {
                        reduction -= 1;
                    }

                    if (!last_move.isNull() and
                    self.counter_moves[@intFromEnum(color)][last_move.from][last_move.to].eql(move))
                {
                        reduction -= 1;
                    }

                    if (!on_pv) {
                        reduction += 1;
                    }

                    if (cutnode) {
                        reduction += 1;
                    }

                    if (tt_pv) {
                        reduction -= 1;
                    }

                    if (!is_capture) {
                        reduction -= @divTrunc(stat_score, tp.history_div.value);
                    }

                    const reduced_depth: usize = @intCast(std.math.clamp(@as(i32, @intCast(new_depth)) - reduction, 1, @as(i32, @intCast(new_depth))));

                    self.lmr_reduction[self.ply - 1] = @as(i32, @intCast(new_depth)) - @as(i32, @intCast(reduced_depth));
                    score = -self.negamax(gs, color.opposite(), reduced_depth, -alpha - 1, -alpha, false, NodeType.NonPV, true);
                    self.lmr_reduction[self.ply - 1] = 0;

                    do_full_search = score > alpha and reduced_depth < new_depth;
                } else {
                    do_full_search = !on_pv or searched_moves > 1;
                }

                if (do_full_search) {
                    score = -self.negamax(gs, color.opposite(), new_depth, -alpha - 1, -alpha, false, NodeType.NonPV, !cutnode);
                }

                if (on_pv and ((score > alpha and score < beta) or searched_moves == 1)) {
                    score = -self.negamax(gs, color.opposite(), new_depth, -beta, -alpha, false, NodeType.PV, false);
                }
            }

            self.ply -= 1;
            gs.unmakeMove(move);

            if (is_root and self.root_pv_index == 0) {
                self.root_node_counts[move.from][move.to] += self.nodes - nodes_before_move;
            }

            if (self.time_stop) {
                return 0;
            }

            if (score > best_score) {
                best_score = score;
                best_move = move;

                if (is_root) {
                    self.best_move = move;
                    self.best_move_score = score;
                }

                if (!is_null) {
                    self.pv[self.ply][0] = move;
                    std.mem.copyForwards(mvs.Move, self.pv[self.ply][1..(self.pv_length[self.ply + 1] + 1)], self.pv[self.ply + 1][0..(self.pv_length[self.ply + 1])]);

                    self.pv_length[self.ply] = self.pv_length[self.ply + 1] + 1;
                }

                if (score > alpha) {
                    alpha = score;
                    alpha_move = move;

                    if (alpha >= beta) {
                        break;
                    }
                }
            }
        }

        if (moves_seen == 0) {
            if (is_root) return alpha;

            if (in_check) {
                // checkmate
                return -eval.mate_score + @as(i32, @intCast(self.ply));
            }
            // stalemate
            return 0;
        }

        if (searched_moves == 0) {
            return alpha;
        }

        const fail_high = best_score >= beta;
        const fail_low = alpha_move.isNull();

        if (!in_check and !is_null and
            self.excluded_moves[self.ply].isNull() and
            !(!alpha_move.isNull() and alpha_move.isCapture()) and
            !eval.almostMate(best_score) and
            !(fail_high and best_score <= static_eval) and
            !(fail_low and best_score >= static_eval)) {
            hist.updateCorrection(self, color, gs, best_score, static_eval, depth);
        }


        if (alpha >= beta and !best_move.isCapture() and !best_move.isPromo()) {
            hist.updateQuietHistory(self, gs, color, best_move, &quiet_moves, is_null, depth, node_threats);
        }

        if (alpha >= beta) {
            hist.updateCaptureHistory(self, gs, color, best_move, &other_moves, depth);
        }

        const skip_root_store = is_root and (self.root_pv_index > 0 or self.excluded_root_count > 0);

        if (self.excluded_moves[self.ply].isNull() and !skip_root_store) {
            const tt_flag: tt.EstimationType = if (best_score >= beta)
                .Under
                else if (!alpha_move.isNull())
                    .Exact
                    else
                    .Over;

            self.tt_table.set(tt.Entry{
                .hash = gs.cur_position.hash,
                .eval = scoreToTT(best_score, self.ply),
                .move = alpha_move,
                .static_eval = raw_static_eval,
                .flag = tt_flag,
                .depth = @as(u8, @intCast(depth)),
                .age = self.tt_table.getAge(),
                .in_check = in_check,
                .is_pv = tt_pv,
                .static_eval_valid = !in_check and self.excluded_moves[self.ply].isNull(),
            });
        }

        return best_score;
    }

    pub fn qsearch(
    self: *Searcher,
    gs: *brd.GameState,
    color: brd.Color,
    alpha_: i32,
    beta_: i32,
    comptime is_pv: bool,
) i32 {
        var alpha = alpha_;
        const beta = beta_;

        if (self.nodes & 2047 == 0 and self.should_stop()) {
            self.time_stop = true;
            return 0;
        }

        if (gs.isDraw(self.ply)) {
            return 0;
        }

        if (self.ply >= max_ply - 1) {
            return eval.adjustEval(gs, self.optimism[@intFromEnum(color)], gs.evaluateNNUE(), 0);
        }

        if (self.ply > self.seldepth) {
            self.seldepth = self.ply;
        }

        self.pv_length[self.ply] = 0;

        self.nodes += 1;

        var hash_move = mvs.Move.none;
        var qs_tt_static_eval: i32 = 0;
        var qs_tt_static_eval_valid: bool = false;
        var qs_tt_in_check: bool = false;
        var qs_tt_hit: bool = false;
        var qs_tt_is_pv: bool = false;
        const entry = self.tt_table.get(gs.cur_position.hash);

        if (entry) |e| {
            qs_tt_hit = true;
            hash_move = e.move;
            qs_tt_in_check = e.in_check;
            qs_tt_static_eval = e.static_eval;
            qs_tt_static_eval_valid = e.static_eval_valid;
            qs_tt_is_pv = e.is_pv;

            if (!is_pv) {
                const tt_score = scoreFromTT(e.eval, self.ply);
                if (e.flag == .Exact) {
                    return tt_score;
                } else if (e.flag == .Under and tt_score >= beta) {
                    return tt_score;
                } else if (e.flag == .Over and tt_score <= alpha) {
                    return tt_score;
                }
            }
        }


        const q_tt_pv: bool = is_pv or (qs_tt_hit and qs_tt_is_pv);
        const in_check: bool = if (qs_tt_hit) qs_tt_in_check else self.move_gen.isInCheck(&gs.cur_position, color);

        var best_score = -eval.mate_score + @as(i32, @intCast(self.ply));
        var best_move = mvs.Move.none;
        var static_eval: i32 = best_score;

        var raw_static: i32 = 0;
        if (!in_check) {
            if (qs_tt_hit and qs_tt_static_eval_valid) {
                raw_static = qs_tt_static_eval;
            } else {
                raw_static = gs.evaluateNNUE();
            }
            const correction = hist.getCorrection(self, color, gs);
            static_eval = eval.adjustEval(gs, self.optimism[@intFromEnum(color)], raw_static, correction);


            best_score = static_eval;

            if (best_score >= beta) {
                self.tt_table.set(tt.Entry{
                    .hash = gs.cur_position.hash,
                    .eval = scoreToTT(best_score, self.ply),
                    .move = mvs.Move.none,
                    .static_eval = raw_static,
                    .flag = .Under,
                    .depth = 0,
                    .age = self.tt_table.getAge(),
                    .in_check = in_check,
                    .is_pv = q_tt_pv,
                    .static_eval_valid = true,
                });
                return best_score;
            }
            if (best_score > alpha) alpha = best_score;
        }


        const queen_val = see.see_values[@intFromEnum(brd.Pieces.Queen)];

        if (!in_check) {
            if (static_eval + queen_val + tp.q_delta_margin.value < alpha) {
                return static_eval + queen_val + tp.q_delta_margin.value;
            }
        }

        var picker: mp.MovePicker = undefined;
        if (in_check) picker.init(hash_move, false) else picker.initNoisy(hash_move);

        var moves_seen: usize = 0;

        while (picker.next(self, gs)) |picked| {
            const move = picked.move;
            moves_seen += 1;

            if (move.isCapture() and !in_check) {
                const futile_below = alpha - static_eval - tp.q_delta_margin.value;
                const threshold = @max(tp.q_see_min.value, @min(tp.q_see_margin.value, futile_below));
                if (!picked.seeAtLeast(self, gs, threshold)) {
                    continue;
                }
            }

            self.move_history[self.ply] = move;
            self.moved_piece_history[self.ply] = gs.cur_position.movedPiece(move);
            self.ply += 1;
            gs.makeMove(move);

            self.tt_table.prefetch(gs.cur_position.hash);
            const score = -self.qsearch(gs, color.opposite(), -beta, -alpha, is_pv);
            self.ply -= 1;
            gs.unmakeMove(move);

            if (score > best_score) {
                best_score = score;
                best_move = move;
                if (score > alpha) {
                    alpha = best_score;

                    if (score >= beta) {
                        self.tt_table.set(tt.Entry{
                            .hash = gs.cur_position.hash,
                            .eval = scoreToTT(best_score, self.ply),
                            .move = best_move,
                            .static_eval = raw_static,
                            .flag = tt.EstimationType.Under,
                            .depth = 0,
                            .age = self.tt_table.getAge(),
                            .in_check = in_check,
                            .is_pv = q_tt_pv,
                            .static_eval_valid = !in_check,
                        });
                        return best_score;
                    }
                }
            }
        }

        if (in_check and moves_seen == 0) {
            // checkmate
            return -eval.mate_score + @as(i32, @intCast(self.ply));
        }

        if (!in_check and moves_seen == 0 and self.ply > 0) {
            // The piece the previous move captured (Piece.none after a null move).
            const last_captured = gs.history[gs.ply - 1].captured.piece;
            const has_non_pawns_us = gs.cur_position.hasNonPawnMaterial(color);

            // Only relevant if we just lost a rook/queen and have no pieces left
            if (!has_non_pawns_us and (last_captured == .Rook or last_captured == .Queen)) {

                // Check if any pawn can push forward (if so, can't be stalemate)
                const pawn_bb = gs.cur_position.getPieceColorBoard(.Pawn, color);
                const occupied = gs.cur_position.getOccupancy();

                const pawn_pushes_exist = if (color == .White)
                    ((pawn_bb << 8) & ~occupied) != 0
                else
                    ((pawn_bb >> 8) & ~occupied) != 0;

                if (!pawn_pushes_exist) {
                    const all_moves = self.move_gen.generateLegal(gs, .all);
                    if (all_moves.len == 0) {
                        return 0; // stalemate — don't return a negative stand-pat
                    }
                }
            }
        }

        if (self.time_stop) return 0;

        self.tt_table.set(tt.Entry{
            .hash = gs.cur_position.hash,
            .eval = scoreToTT(best_score, self.ply),
            .move = if (best_score > alpha_) best_move else mvs.Move.none,
            .static_eval = raw_static,
            .flag = if (best_score >= beta) tt.EstimationType.Under else tt.EstimationType.Over,
            .depth = 0,
            .age = self.tt_table.getAge(),
            .in_check = in_check,
            .is_pv = q_tt_pv,
            .static_eval_valid = !in_check,
        });

        return best_score;
    }

    fn formatScore(score: i32, buf: []u8) []const u8 {
        const mate_threshold = eval.mate_score - max_ply;
        if (score + 20 >= mate_threshold) {
            const plies = eval.mate_score - score;
            const moves = @divTrunc(plies + 1, 2);
            return std.fmt.bufPrint(buf, "score mate {d}", .{moves}) catch "score cp 0";
        } else if (score - 20 <= -mate_threshold) {
            const plies = eval.mate_score + score;
            const moves = @divTrunc(plies + 1, 2);
            return std.fmt.bufPrint(buf, "score mate -{d}", .{moves}) catch "score cp 0";
        } else {
            return std.fmt.bufPrint(buf, "score cp {d}", .{score}) catch "score cp 0";
        }
    }

    pub fn printInfo(self: *Searcher, nodes: u64, tb_hits: u64, score: i32, pv: []const mvs.Move, multipv_idx: usize, allocator: std.mem.Allocator) void {
        const elapsed_ms = self.timer.read() / std.time.ns_per_ms;
        const nps: u64 = if (elapsed_ms > 0) (nodes * 1000) / elapsed_ms else 0;

        var stdout_writer = std.fs.File.stdout().writer(&self.stdout_buffer);
        const stdout = &stdout_writer.interface;

        _ = allocator;
        var pv_string_buffer: [512]u8 = @splat(0);
        var pv_string_len: usize = 0;

        for (pv) |move| {
            var move_buf: [5]u8 = undefined;
            const cur_move_str = mvs.moveToUci(self.root_board, move, self.chess960, &move_buf);

            const needed_len = pv_string_len + cur_move_str.len + 1;
            if (needed_len > pv_string_buffer.len) break;
            std.mem.copyForwards(u8, pv_string_buffer[pv_string_len..], cur_move_str);
            pv_string_len += cur_move_str.len;
            pv_string_buffer[pv_string_len] = ' ';
            pv_string_len += 1;
        }
        const pv_string = pv_string_buffer[0..pv_string_len];

        var score_buf: [64]u8 = undefined;
        const score_string = formatScore(score, &score_buf);

        var multipv_buf: [32]u8 = undefined;
        const multipv_string: []const u8 = if (self.multi_pv > 1)
            (std.fmt.bufPrint(&multipv_buf, "multipv {d} ", .{multipv_idx}) catch "")
        else
            "";

        stdout.print("info depth {d} seldepth {d} {s}{s} time {d} nodes {d} nps {d} tbhits {d} pv {s}\n", .{
            self.search_depth,
            self.seldepth,
            multipv_string,
            score_string,
            elapsed_ms,
            nodes,
            nps,
            tb_hits,
            pv_string,
        }) catch return;
        stdout.flush() catch {};
    }
};
