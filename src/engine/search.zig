const std = @import("std");
const mvs = @import("moves");
const brd = @import("board");
const eval = @import("eval");
const tt = @import("transposition");
const see = @import("see");
const mp = @import("move_picker");
const tp = @import("tunable_parameters");
const hist = @import("history");

pub const max_ply = 128;
pub const max_game_ply = 1024;

pub var quiet_lmr: [64][64]i32 = undefined;

pub fn initQuietLMR() [64][64]i32 {
    const lmr_base_f: f32 = @as(f32, @floatFromInt(tp.lmr_base)) / 100.0;
    const lmr_div_f: f32 = @as(f32, @floatFromInt(tp.lmr_div)) / 100.0;
    var table: [64][64]i32 = undefined;
    for (1..64) |d| {
        for (1..64) |m| {
            const df: f32 = @floatFromInt(d);
            const mf: f32 = @floatFromInt(m);
            table[d][m] = @intFromFloat(lmr_base_f + @log(df) * @log(mf) / lmr_div_f);
        }
    }
    return table;
}

pub const NodeType = enum {
    Root,
    PV,
    NonPV,
};

pub const SearchResult = struct {
    move: mvs.EncodedMove,
    score: i32,
    depth: usize,
    nodes: u64,
    time_ms: u64,
    pv: [max_ply]mvs.EncodedMove,
    pv_length: usize,
};

pub var search_helpers: std.ArrayList(Searcher) = undefined;

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

    move_gen: *mvs.MoveGen = undefined,

    soft_max_nodes: ?u64 = null,
    max_nodes: ?u64 = null,

    time_stop: bool = false,

    nodes: u64 = 0,
    ply: usize = 0,
    seldepth: usize = 0,
    stop: bool = false,
    is_searching: bool = false,

    best_move: mvs.EncodedMove = undefined,
    best_move_score: i32 = 0,
    pv: [max_ply][max_ply]mvs.EncodedMove = undefined,
    pv_length: [max_ply]usize = undefined,

    search_score: i32 = 0,
    perspective: brd.Color = .White,

    eval_history: [max_ply]i32 = undefined,
    move_history: [max_ply]mvs.EncodedMove = undefined,
    moved_piece_history: [max_ply]PieceColor = undefined,
    killer: [max_ply][2]mvs.EncodedMove = undefined,
    history: [2][64][64]i32 = undefined,
    counter_moves: [2][64][64]mvs.EncodedMove = undefined,
    excluded_moves: [max_ply]mvs.EncodedMove = undefined,
    continuation: *[12][64][64][64]i32 = undefined,
    correction: [2][16384]i32 = undefined,
    np_white_correction: [2][16384]i32 = undefined,
    np_black_correction: [2][16384]i32 = undefined,
    capture_history: [2][7][64][7]i32 = undefined,

    nmp_min_ply: usize = 0,

    thread_id: usize = 0,
    root_board: *brd.Board = undefined,
    silent_output: bool = false,
    stdout_buffer: [2048]u8 = undefined,

    /// Owned by the main searcher; helpers point to the same table.
    tt_table: *tt.TranspositionTable = undefined,

    pub const PieceColor = struct {
        piece: brd.Pieces,
        color: brd.Color,
    };

    pub fn init() Searcher {
        var s = Searcher{
            .timer = std.time.Timer.start() catch {
                std.debug.panic("Failed to start timer", .{});
            },
            .move_gen = std.heap.c_allocator.create(mvs.MoveGen) catch {
                std.debug.panic("Failed to allocate move generator", .{});
            },
            .continuation = std.heap.c_allocator.create([12][64][64][64]i32) catch {
                std.debug.panic("Failed to allocate continuation table", .{});
            },
        };

        s.move_gen.init();

        hist.resetHeuristics(&s, true);

        search_helpers = std.ArrayList(Searcher).initCapacity(std.heap.c_allocator, 4) catch {
            std.debug.panic("Failed to initialize search helpers", .{});
        };

        threads = std.ArrayList(std.Thread).initCapacity(std.heap.c_allocator, 4) catch {
            std.debug.panic("Failed to initialize threads array", .{});
        };

        return s;
    }

    pub fn initInPlace(self: *Searcher) void {
        self.timer = std.time.Timer.start() catch unreachable;
        self.move_gen = std.heap.c_allocator.create(mvs.MoveGen) catch unreachable;
        self.move_gen.init();
        self.continuation = std.heap.c_allocator.create([12][64][64][64]i32) catch unreachable;
        hist.resetHeuristics(self, true);
    }

    pub fn deinit(self: *Searcher) void {
        std.heap.c_allocator.destroy(self.continuation);
    }

    pub inline fn should_stop(self: *Searcher) bool {
        const thinking = @atomicLoad(bool, &self.force_think, .acquire);
        return self.stop or
            (self.thread_id == 0 and self.search_depth > self.min_depth and
                ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
                    (!thinking and self.timer.read() / std.time.ns_per_ms >= self.max_ms)));
    }

    pub inline fn should_not_continue(self: *Searcher, factor: f32) bool {
        const thinking = @atomicLoad(bool, &self.force_think, .acquire);
        return self.stop or
            (self.thread_id == 0 and self.search_depth > self.min_depth and
                ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
                    (!thinking and self.timer.read() / std.time.ns_per_ms >= @min(self.ideal_ms, @as(u64, @intFromFloat(@as(f32, @floatFromInt(self.ideal_ms)) * factor))))));
    }

    const ThreadContext = struct {
        searcher: *Searcher,
        board: *brd.Board,
        max_depth: ?u8,
    };

    fn helperThreadWorker(ctx: ThreadContext) void {
        _ = ctx.searcher.iterativeDeepening(ctx.board, ctx.max_depth) catch |err| {
            std.debug.print("Helper thread {} error: {}\n", .{ ctx.searcher.thread_id, err });
        };
    }

    pub fn initHelperThreads(num_threads: usize, shared_tt: *tt.TranspositionTable) !void {
        if (num_threads <= 1) {
            return; // No helpers needed for single-threaded search
        }

        for (search_helpers.items) |*helper| {
            helper.deinit();
        }
        search_helpers.clearRetainingCapacity();
        threads.clearRetainingCapacity();

        try search_helpers.ensureTotalCapacity(std.heap.c_allocator, num_threads - 1);
        try threads.ensureTotalCapacity(std.heap.c_allocator, num_threads - 1);

        // Create helper searchers (thread 0 is the main searcher)
        var i: usize = 1;
        while (i < num_threads) : (i += 1) {
            // var helper = Searcher.init();
            var helper = Searcher{};
            helper.initInPlace();
            helper.thread_id = i;
            helper.silent_output = true; // not used but for future
            helper.tt_table = shared_tt;
            try search_helpers.append(std.heap.c_allocator, helper);
        }
    }

    pub fn startParallelSearch(
        main_searcher: *Searcher,
        board: *brd.Board,
        max_depth: ?u8,
        num_threads: usize,
    ) !void {
        if (num_threads <= 1) {
            return;
        }

        if (search_helpers.items.len != num_threads - 1) {
            try initHelperThreads(num_threads, main_searcher.tt_table);
        }

        threads.clearRetainingCapacity();

        main_searcher.root_board = board;

        for (search_helpers.items) |*helper| {
            var board_copy = try std.heap.c_allocator.create(brd.Board);
            board_copy.copyFrom(board);

            helper.root_board = board_copy;
            helper.stop = false;
            helper.time_stop = false;

            helper.max_ms = main_searcher.max_ms;
            helper.ideal_ms = main_searcher.ideal_ms;
            helper.min_depth = main_searcher.min_depth;
            helper.force_think = main_searcher.force_think;
            helper.max_nodes = main_searcher.max_nodes;
            helper.soft_max_nodes = main_searcher.soft_max_nodes;

            const ctx = ThreadContext{
                .searcher = helper,
                .board = board_copy,
                .max_depth = max_depth,
            };

            const thread = try std.Thread.spawn(.{}, helperThreadWorker, .{ctx});
            try threads.append(std.heap.c_allocator, thread);
        }
    }

    pub fn waitForHelpers() void {
        for (threads.items) |thread| {
            thread.join();
        }

        for (search_helpers.items) |helper| {
            std.heap.c_allocator.destroy(helper.root_board);
        }
    }

    pub fn stopAllThreads() void {
        tt.stop_signal.store(true, .release);

        for (search_helpers.items) |*helper| {
            helper.stop = true;
            helper.time_stop = true;
        }
    }

    pub fn parallelIterativeDeepening(
        main_searcher: *Searcher,
        board: *brd.Board,
        max_depth: ?u8,
        num_threads: usize,
    ) !SearchResult {
        if (num_threads <= 1) {
            return try main_searcher.iterativeDeepening(board, max_depth);
        }

        tt.stop_signal.store(false, .release);
        main_searcher.stop = false;
        main_searcher.time_stop = false;

        try startParallelSearch(main_searcher, board, max_depth, num_threads);

        const result = try main_searcher.iterativeDeepening(board, max_depth);

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
        stopAllThreads();
        waitForHelpers();

        for (search_helpers.items) |*helper| {
            helper.deinit();
        }

        search_helpers.deinit();
        threads.deinit();
    }

    pub fn iterativeDeepening(self: *Searcher, board: *brd.Board, max_depth: ?u8) !SearchResult {
        self.stop = false;
        self.is_searching = true;
        self.time_stop = false;
        self.time_offset = 0;
        self.prev_depth_ms = 0;
        tt.stop_signal.store(false, .release);
        hist.resetHeuristics(self, false);
        self.nodes = 0;
        self.best_move = mvs.EncodedMove.fromU32(0);
        self.best_move_score = -eval.mate_score;
        self.timer = std.time.Timer.start() catch unreachable;
        self.perspective = board.toMove();
        self.search_score = 0;

        var prev_score: i32 = -eval.mate_score;
        var score: i32 = -eval.mate_score;

        var bm = mvs.EncodedMove.fromU32(0);
        var best_pv: [max_ply]mvs.EncodedMove = undefined;
        var best_pv_length: usize = 0;

        var stability: usize = 0;

        var outer_depth: usize = (self.thread_id % 2) + 1;

        const bound: usize = if (max_depth != null) @as(usize, max_depth.?) else max_ply;

        outer: while (outer_depth <= bound) : (outer_depth += 1) {
            self.ply = 0;
            self.seldepth = 0;
            self.search_depth = outer_depth;

            var alpha = if (outer_depth > 1) prev_score - tp.aspiration_window else -eval.mate_score;
            var beta = if (outer_depth > 1) prev_score + tp.aspiration_window else eval.mate_score;
            var delta: i32 = tp.aspiration_window;

            const depth = outer_depth;

            var window_failed = false;
            while (true) {
                // self.search_depth = @max(self.search_depth, depth);
                self.nmp_min_ply = 0;

                if (depth == outer_depth) {
                    score = self.negamax(board, board.toMove(), depth, alpha, beta, false, NodeType.Root, false);
                }
                else {
                    score = self.negamax(board, board.toMove(), depth, alpha, beta, false, NodeType.PV, false);
                }


                if (self.time_stop or self.should_stop()) {
                    self.time_stop = true;
                    tt.stop_signal.store(true, .release);
                    break :outer;
                }

                if (score <= alpha) {
                    beta = @divTrunc(alpha + beta, 2);
                    alpha = @max(alpha - delta, -eval.mate_score);
                    delta = @min(delta * 2, eval.mate_score);
                    window_failed = true;
                } else if (score >= beta) {
                    beta = @min(beta + delta, eval.mate_score);
                    delta = @min(delta * 2, eval.mate_score);
                    window_failed = false;
                } else {
                    window_failed = false;
                    break;
                }
            }

            if (self.best_move.toU32() != bm.toU32()) {
                stability = 0;
            } else {
                stability += 1;
            }

            if (!window_failed) {
                bm = self.best_move;
                best_pv = self.pv[0];
                best_pv_length = self.pv_length[0];
            }

            if (!self.silent_output) {
                var total_nodes = self.nodes;
                for (search_helpers.items) |helper| {
                    total_nodes += helper.nodes;
                }

                self.printInfo(total_nodes, score, best_pv[0..best_pv_length], std.heap.c_allocator);
            }

            var factor: f32 = @max(0.65, 1.3 - 0.03 * @as(f32, @floatFromInt(stability)));

            if (stability == 0) {
                factor = @min(factor * 1.2, 1.5);
            }

            if (score - prev_score > tp.aspiration_window) {
                factor *= 1.3;
            } else if (prev_score - score > tp.aspiration_window) {
                factor *= 1.5;
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

        self.tt_table.incrememtAge();

        // Guard against null moves
        if (self.best_move.toU32() == 0) {
            if (self.tt_table.get(board.game_state.zobrist)) |e| {
                self.best_move = e.move;
            }
            if (self.best_move.toU32() == 0) {
                const move_list = self.move_gen.generateMoves(board, false);
                if (move_list.len > 0) {
                    self.best_move = move_list.items[0];
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

    pub fn negamax(self: *Searcher, board: *brd.Board, color: brd.Color, depth_: usize, alpha_: i32, beta_: i32, is_null: bool, comptime node_type: NodeType, cutnode: bool) i32 {
        var alpha = alpha_;
        var beta = beta_;
        var depth = depth_;

        self.pv_length[self.ply] = 0;

        if (self.nodes & 2047 == 0 and self.should_stop()) {
            self.time_stop = true;
            tt.stop_signal.store(true, .release);
            return 0;
        }

        self.seldepth = @max(self.seldepth, self.ply);

        const is_root = comptime (node_type == NodeType.Root);
        const on_pv = comptime (node_type != NodeType.NonPV);

        if (self.ply == max_ply) {
            return board.evaluateNNUE();
        }

        const in_check: bool = self.move_gen.isInCheck(board, color);

        if (depth == 0) {
            return self.qsearch(board, color, alpha, beta);
        }

        if (board.isDraw(self.ply)) {
            return 0;
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

        var hash_move = mvs.EncodedMove.fromU32(0);
        var tt_hit = false;
        var tt_eval: i32 = 0;
        var tt_e_flag: tt.EstimationType = .None;
        var tt_depth: usize = 0;
        const entry = self.tt_table.get(board.game_state.zobrist);

        if (entry) |e| {
            tt_hit = true;
            tt_eval = e.eval;
            tt_depth = @as(usize, @intCast(e.depth));
            tt_e_flag = e.flag;

            if (tt_eval > eval.mate_score - 256 and tt_eval <= eval.mate_score) {
                tt_eval -= @as(i32, @intCast(self.ply));
            } else if (tt_eval < -eval.mate_score + 256 and tt_eval >= -eval.mate_score) {
                tt_eval += @as(i32, @intCast(self.ply));
            }

            hash_move = e.move;

            if (is_root) {
                self.best_move = hash_move;
                self.best_move_score = tt_eval;
            }

            if (!is_null and !on_pv and !is_root and e.depth >= @as(u8, @intCast(depth))) {
                switch (e.flag) {
                    .Exact => return tt_eval,
                    .Under => alpha = @max(alpha, tt_eval),
                    .Over => beta = @min(beta, tt_eval),
                    .None => {},
                }
                if (alpha >= beta) {
                    return tt_eval;
                }
            }
        }

        var static_eval: i32 = undefined;
        if (in_check) {
            static_eval = -eval.mate_score + @as(i32, @intCast(self.ply));
        } else if (tt_hit) {
            static_eval = tt_eval;
        } else if (is_null) {
            static_eval = -self.eval_history[self.ply - 1];
        } else if (self.excluded_moves[self.ply].toU32() != 0) {
            static_eval = self.eval_history[self.ply];
        } else {
            static_eval = board.evaluateNNUE();
            static_eval += hist.getCorrection(self, color, board);
        }

        var best_score: i32 = static_eval;

        var low_estimate_score: i32 = -eval.mate_score - 1;
        self.eval_history[self.ply] = static_eval;

        const improving: bool = !in_check and self.ply >= 2 and static_eval > self.eval_history[self.ply - 2];

        const has_non_pawns = board.hasNonPawnMaterial(color);

        var last_move: mvs.EncodedMove = mvs.EncodedMove.fromU32(0);
        if (self.ply > 0) {
            last_move = self.move_history[self.ply - 1];
        }
        var last_last_last_move = mvs.EncodedMove.fromU32(0);
        if (self.ply > 2) {
            last_last_last_move = self.move_history[self.ply - 3];
        }

        if (depth >= 3 and !in_check and !tt_hit and self.excluded_moves[self.ply].toU32() == 0 and (on_pv or cutnode)) {
            var r = @divTrunc(depth, 4);
            if (r < 1) {
                r = 1;
            }
            depth = depth - r;
        }

        if (!in_check and !on_pv and self.excluded_moves[self.ply].toU32() == 0) {
            low_estimate_score = if (!tt_hit or entry.?.flag == tt.EstimationType.Under) static_eval else tt_eval;

            // reverse futility pruning
            if (@abs(beta) < eval.mate_score - 256 and
                depth <= @as(usize, @intCast(tp.rfp_depth)))
            {
                var n: i32 = @as(i32, @intCast(depth)) * tp.rfp_mul;

                if (improving) {
                    n -= tp.rfp_improve;
                }

                if (static_eval - n >= beta) {
                    return beta;
                }
            }

            // razoring
            if (depth <= 4) {
                const threshold = tp.razoring_base + (tp.razoring_mul * @as(i32, @intCast(depth)));
                if (static_eval + threshold < alpha) {
                    return self.qsearch(board, color, alpha, beta);
                }
            }

            // null move pruning
            var nmp_static_eval: i32 = static_eval;
            if (improving) {
                nmp_static_eval += tp.nmp_improve;
            }

            if (!is_null and depth >= 4 and self.ply >= self.nmp_min_ply and nmp_static_eval >= beta and has_non_pawns) {
                var r = tp.nmp_base + depth / tp.nmp_depth_div;
                r += @as(usize, @intCast(@min(4, @divTrunc(static_eval - beta, @as(i32, @intCast(tp.nmp_beta_div))))));

                if (cutnode) {
                    r += 1;
                }

                r = @min(r, depth);

                self.ply += 1;
                board.makeNullMove();
                var null_score = -self.negamax(board, brd.flipColor(color), depth - r, -beta, -beta + 1, true, NodeType.NonPV, false);
                self.ply -= 1;
                board.unmakeNullMove();

                if (self.time_stop) {
                    return 0;
                }

                if (null_score >= beta) {
                    if (null_score >= eval.mate_score - 256) {
                        null_score = beta;
                    }
                    return null_score;
                }
            }
        }

        // Actually run search
        var move_list = self.move_gen.generateMoves(board, false);
        const move_count: usize = move_list.len;

        var quiet_moves: mvs.MoveList = mvs.MoveList.init();
        var other_moves: mvs.MoveList = mvs.MoveList.init();

        self.killer[self.ply + 1][0] = mvs.EncodedMove.fromU32(0);
        self.killer[self.ply + 1][1] = mvs.EncodedMove.fromU32(0);

        if (move_count == 0) {
            // checkmate
            if (in_check) {
                return -eval.mate_score + @as(i32, @intCast(self.ply));
            } else {
                // stalemate
                return 0;
            }
        }

        var eval_moves = mp.scoreMoves(self, board, &move_list, hash_move, is_null);

        var best_move = mvs.EncodedMove.fromU32(0);
        best_score = -eval.mate_score + @as(i32, @intCast(self.ply));

        var skip_quiet: bool = false;
        var quiet_count: usize = 0;
        var other_count: usize = 0;
        var searched_moves: usize = 0;

        for (0..move_count) |i| {
            var move = mp.getNextBest(&move_list, &eval_moves, i);
            if (move.toU32() == self.excluded_moves[self.ply].toU32()) {
                continue;
            }

            const is_capture = move.capture == 1;
            const is_killer = move.toU32() == self.killer[self.ply][0].toU32() or move.toU32() == self.killer[self.ply][1].toU32();

            if (depth <= 5 and !is_root and i > 1 and !in_check and !on_pv) {
                var lmp_threshold: usize = tp.lmp_base + depth * tp.lmp_mul;

                lmp_threshold += self.thread_id;

                if (improving and !on_pv) {
                    lmp_threshold += tp.lmp_improve;
                }

                // Prune if we have searched enough quiet moves
                if (quiet_count > lmp_threshold) {
                    skip_quiet = true;
                }
            }

            if (!is_capture) {
                quiet_moves.addEncodedMove(move);
                quiet_count += 1;
            } else {
                other_moves.addEncodedMove(move);
                other_count += 1;
            }

            const is_important = is_killer or (move.promoted_piece == @intFromEnum(brd.Pieces.Queen));

            if (skip_quiet and !is_capture and !is_important) {
                continue;
            }

            if (!is_capture and !is_important and !in_check and !on_pv and
                depth <= 4 and searched_moves >= 2)
            {
                const hist_score = self.history[@intFromEnum(color)][move.start_square][move.end_square];
                const hist_threshold: i32 = -@as(i32, @intCast(depth)) * 1536;
                if (hist_score < hist_threshold) {
                    continue;
                }
            }

            // futility pruning
            if (move.capture == 0 and depth <= 8 and !in_check and !on_pv and !is_important and static_eval + ((@as(i32, @intCast(depth)) + 1) * tp.futility_mul) <= alpha) {
                continue;
            }

            // SEE pruning
            if (!is_capture and !in_check and !on_pv and !is_important and depth <= 6 and searched_moves >= 2 and !is_important) {
                if (!see.seeAtLeast(board, self.move_gen, move, -@as(i32, @intCast(depth)) * 25)) {
                    continue;
                }
            }

            if (is_capture and !in_check and !on_pv and depth <= 6 and searched_moves >= 2 and !is_important) {
                if (!see.seeAtLeast(board, self.move_gen, move, -100)) {
                    continue;
                }
            }


            var extension: i32 = 0;

            // Singular Extensions, also double and triple
            if (self.ply > 0 and !is_root and self.ply < depth * 2 and depth >= 7 and
                tt_hit and entry.?.flag != tt.EstimationType.Over and !eval.almostMate(tt_eval) and
            hash_move.toU32() == move.toU32() and entry.?.depth >= depth - 3 and move_list.len >= 2)
            {
                const margin: i32 = @as(i32, @intCast(depth)) * 2;
                const singular_beta = @max(tt_eval - margin, -eval.mate_score + 256);

                self.excluded_moves[self.ply] = hash_move;

                const r = @divTrunc(@as(i32, @intCast(depth)) - 1, 2);
                const singular_depth = @max(r, 1);
                const singular_score = self.negamax(board, color, singular_depth, singular_beta - 1, singular_beta, false, NodeType.NonPV, cutnode);
                self.excluded_moves[self.ply] = mvs.EncodedMove.fromU32(0);

                if (singular_score < singular_beta) {
                    extension = 1;

                    // double extension
                    if (on_pv and singular_score < singular_beta - tp.se_double_threshold) {
                        extension = 2;
                    }

                    // Triple extension for very singular moves
                    if (on_pv and singular_score < singular_beta - (tp.se_double_threshold + tp.se_triple_threshold)) {
                        extension = 3;
                    }
                } else if (singular_beta >= beta) {
                    return singular_beta;
                } else if (tt_eval >= beta) {
                    extension = -1;
                } else if (cutnode) {
                    extension = -1;
                }
            }

            // Recapture Extensions
            if (on_pv and !is_root and self.ply < depth * 2) {
                if (is_capture and last_move.capture == 1 and move.end_square == last_move.end_square) {
                    extension += 1;
                } else if (is_capture and self.ply >= 3 and last_last_last_move.capture == 1 and
                    move.end_square == last_last_last_move.end_square)
                {
                    extension += 1;
                }
            }

            // Pawn Push Extension
            if (on_pv and !is_root and self.ply < depth * 2 and move.capture == 0) {
                if (board.getPieceFromSquare(move.start_square)) |piece| {
                    if (piece == .Pawn) {
                        // Pawn to 7th rank
                        const rank = move.end_square / 8;
                        const is_white = board.toMove() == .White;

                        if ((is_white and rank == 6) or (!is_white and rank == 1)) {
                            extension += 1;
                        }
                    }
                }
            }

            if (in_check) {
                extension += 1;
            }

            if (move_list.len == 1) {
                extension += 1;
            }

            self.move_history[self.ply] = move;
            if (board.getPieceFromSquare(move.start_square)) |p| {
                self.moved_piece_history[self.ply] = .{ .piece = p, .color = board.getColorFromSquare(move.start_square).? };
            } else {
                self.moved_piece_history[self.ply] = .{ .piece = .None, .color = .White };
            }

            self.ply += 1;

            mvs.makeMove(board, move);
            searched_moves += 1;


            if (extension < 0) {
                extension = 0;
            }
            else if (extension > 4) {
                extension = 4;
            }

            const new_depth: usize = @as(usize, @intCast(@as(i32, @intCast(depth)) + extension - 1));

            self.tt_table.prefetch(board.game_state.zobrist);

            var score: i32 = 0;

            const min_lmr_move: usize = if (on_pv) tp.lmr_pv_min else tp.lmr_non_pv_min;
            var do_full_search = false;

            if (on_pv and searched_moves == 1) {
                score = -self.negamax(board, brd.flipColor(color), new_depth, -beta, -alpha, false, NodeType.PV, false);
            } else {
                if (!in_check and depth >= 3 and i >= min_lmr_move) {
                    var reduction: i32 = quiet_lmr[@min(depth, 63)][@min(quiet_count, 63)];

                    if (improving) {
                        reduction -= 1;
                    }

                    if (self.counter_moves[@intFromEnum(color)][move.start_square][move.end_square].toU32() == move.toU32()) {
                        reduction -= 1;
                    }

                    if (!on_pv) {
                        reduction += 1;
                    }

                    if (cutnode) {
                        reduction += 1;
                    }

                    reduction -= @divTrunc(self.history[@intFromEnum(color)][move.start_square][move.end_square], tp.history_div);

                    const reduced_depth: usize = @intCast(std.math.clamp(@as(i32, @intCast(new_depth)) - reduction, 1, @as(i32, @intCast(new_depth + 1))));

                    score = -self.negamax(board, brd.flipColor(color), reduced_depth, -alpha - 1, -alpha, false, NodeType.NonPV, true);

                    do_full_search = score > alpha and reduced_depth < new_depth;
                } else {
                    do_full_search = !on_pv or i > 0;
                }

                if (do_full_search) {
                    score = -self.negamax(board, brd.flipColor(color), new_depth, -alpha - 1, -alpha, false, NodeType.NonPV, !cutnode);
                }

                if (on_pv and ((score > alpha and score < beta) or i == 0)) {
                    score = -self.negamax(board, brd.flipColor(color), new_depth, -beta, -alpha, false, NodeType.PV, false);
                }
            }

            self.ply -= 1;
            mvs.undoMove(board, move);

            if (self.time_stop) {
                return 0;
            }

            if (score > best_score) {
                best_score = score;
                best_move = move;

                if (!is_null) {
                    self.pv[self.ply][0] = move;
                    std.mem.copyForwards(mvs.EncodedMove, self.pv[self.ply][1..(self.pv_length[self.ply + 1] + 1)], self.pv[self.ply + 1][0..(self.pv_length[self.ply + 1])]);

                    self.pv_length[self.ply] = self.pv_length[self.ply + 1] + 1;
                }

                if (score > alpha) {
                    alpha = score;
                    if (is_root) {
                        self.best_move = best_move;
                        self.best_move_score = best_score;
                    }

                    if (alpha >= beta) {
                        break;
                    }
                }
            }
        }

        if (!in_check and !is_null and best_move.capture == 0 and (best_score > -eval.mate_score and best_score < eval.mate_score) and self.excluded_moves[self.ply].toU32() == 0 and !(best_score >= beta and best_score <= static_eval) and !(best_move.toU32() == 0 and best_score >= static_eval)) {
            hist.updateCorrection(self, color, board, best_move, best_score, static_eval, depth);
        }

        if (alpha >= beta and !(best_move.capture == 1) and !(best_move.promoted_piece != 0)) {
            hist.updateQuietHistory(self, color, best_move, &quiet_moves, is_null, depth);
        }

        if (alpha >= beta and best_move.capture == 1) {
            hist.updateCaptureHistory(self, board, color, best_move, &other_moves, depth);
        }

        if (!skip_quiet and self.excluded_moves[self.ply].toU32() == 0) {
            var tt_flag = tt.EstimationType.Over;
            if (best_score >= beta) {
                tt_flag = tt.EstimationType.Under;
            } else if (alpha != alpha_) {
                tt_flag = tt.EstimationType.Exact;
            }

            self.tt_table.set(
                tt.Entry{
                    .hash = board.game_state.zobrist,
                    .eval = best_score,
                    .move = best_move,
                    .flag = tt_flag,
                    .depth = @as(u8, @intCast(depth)),
                    .age = self.tt_table.getAge(),
                },
            );
        }
        return best_score;
    }

    pub fn qsearch(self: *Searcher, board: *brd.Board, color: brd.Color, alpha_: i32, beta_: i32) i32 {
        var alpha = alpha_;
        const beta = beta_;

        if (self.nodes & 2047 == 0 and self.should_stop()) {
            self.time_stop = true;
            return 0;
        }

        self.pv_length[self.ply] = 0;

        if (board.isDraw(self.ply)) {
            return 0;
        }

        if (self.ply >= max_ply) {
            return board.evaluateNNUE();
        }

        self.nodes += 1;

        const in_check: bool = self.move_gen.isInCheck(board, color);

        var best_score = -eval.mate_score + @as(i32, @intCast(self.ply));
        var static_eval: i32 = best_score;

        if (!in_check) {
            static_eval = board.evaluateNNUE();
            static_eval += hist.getCorrection(self, color, board);

            best_score = static_eval;

            if (best_score >= beta) {
                return best_score;
            }
            if (best_score > alpha) {
                alpha = best_score;
            }
        }

        const queen_val = 950;

        if (!in_check) {
            if (static_eval + queen_val + tp.q_delta_margin < alpha) {
                return alpha;
            }
        }

        var hash_move = mvs.EncodedMove.fromU32(0);
        const entry = self.tt_table.get(board.game_state.zobrist);

        if (entry) |e| {
            hash_move = e.move;
            if (e.flag == .Exact) {
                return e.eval;
            } else if (e.flag == .Under and e.eval >= beta) {
                return e.eval;
            } else if (e.flag == .Over and e.eval <= alpha) {
                return e.eval;
            }
        }

        var move_list: mvs.MoveList = undefined;
        if (in_check) {
            move_list = self.move_gen.generateMoves(board, false);
            if (move_list.len == 0) {
                // checkmate
                if (in_check) {
                    return -eval.mate_score + @as(i32, @intCast(self.ply));
                } else {
                    return 0;
                }
            }
        } else {
            move_list = self.move_gen.generateCaptureMoves(board, color);
        }

        const move_size = move_list.len;

        var eval_list = mp.scoreMoves(self, board, &move_list, hash_move, false);

        for (0..move_size) |i| {
            const move = mp.getNextBest(&move_list, &eval_list, i);

            if (move.capture == 1) {
                const see_value = see.seeCapture(board, self.move_gen, move);

                if (see_value < tp.q_see_min) {
                    continue;
                }

                var captured_piece_value: i32 = 0;
                captured_piece_value = see.see_values[@as(usize, @intCast(move.captured_piece)) + 1];

                if (see_value < tp.q_see_margin and
                captured_piece_value < 300 and
                static_eval + see_value + captured_piece_value + tp.q_delta_margin < alpha)
            {
                    continue;
                }
            }

            self.move_history[self.ply] = move;
            var moved_piece = PieceColor{
                .piece = .None,
                .color = .White,
            };
            if (board.getPieceFromSquare(move.start_square)) |p| {
                moved_piece = .{ .piece = p, .color = board.getColorFromSquare(move.start_square).? };
            }
            self.moved_piece_history[self.ply] = moved_piece;
            self.ply += 1;
            mvs.makeMove(board, move);

            self.tt_table.prefetch(board.game_state.zobrist);
            const score = -self.qsearch(board, brd.flipColor(color), -beta, -alpha);
            self.ply -= 1;
            mvs.undoMove(board, move);

            if (self.time_stop) {
                return 0;
            }

            if (score > best_score) {
                best_score = score;
                if (score > alpha) {
                    alpha = best_score;

                    if (score >= beta) {
                        return beta;
                    }
                }
            }
        }

        if (!in_check and move_size == 0 and self.ply > 0) {
            const last = self.move_history[self.ply - 1];
            const has_non_pawns_us = board.hasNonPawnMaterial(color);

            // Only relevant if we just lost a rook/queen and have no pieces left
            if (!has_non_pawns_us and (last.captured_piece == @intFromEnum(brd.Pieces.Rook) or last.captured_piece == @intFromEnum(brd.Pieces.Queen))) {

                // Check if any pawn can push forward (if so, can't be stalemate)
                const pawn_bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Pawn)];
                // Compute all occupied squares by unioning both sides
                var occupied: u64 = 0;
                inline for (0..2) |c| {
                    inline for (0..6) |p| {
                        occupied |= board.piece_bb[c][p];
                    }
                }

                const pawn_pushes_exist = if (color == .White)
                ((pawn_bb << 8) & ~occupied) != 0
                    else
                ((pawn_bb >> 8) & ~occupied) != 0;

                if (!pawn_pushes_exist) {
                    const all_moves = self.move_gen.generateMoves(board, false);
                    if (all_moves.len == 0) {
                        return 0; // stalemate — don't return a negative stand-pat
                    }
                }
            }
        }

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

    pub fn printInfo(self: *Searcher, nodes: u64, score: i32, pv: []const mvs.EncodedMove, allocator: std.mem.Allocator) void {
        const elapsed_ms = self.timer.read() / std.time.ns_per_ms;
        const nps: u64 = if (elapsed_ms > 0) (nodes * 1000) / elapsed_ms else 0;
        const hashfull = self.tt_table.getFillPermill();
 
        var stdout_writer = std.fs.File.stdout().writer(&self.stdout_buffer);
        const stdout = &stdout_writer.interface;
 
        var pv_string_buffer: [512]u8 = @splat(0);
        var pv_string_len: usize = 0;
        for (pv) |move| {
            const cur_move_str = move.uciToString(allocator) catch {
                return; // If conversion fails, skip printing the PV
            };
            defer allocator.free(cur_move_str);
            const needed_len = pv_string_len + cur_move_str.len + 1;
            if (needed_len > pv_string_buffer.len) {
                break;
            }
            std.mem.copyForwards(u8, pv_string_buffer[pv_string_len..], cur_move_str);
            pv_string_len += cur_move_str.len;
            pv_string_buffer[pv_string_len] = ' ';
            pv_string_len += 1;
        }
        const pv_string = pv_string_buffer[0..pv_string_len];
 
        var score_buf: [64]u8 = undefined;
        const score_string = formatScore(score, &score_buf);
 
        stdout.print("info depth {d} seldepth {d} {s} time {d} nodes {d} nps {d} hashfull {d} pv {s}\n", .{
            self.search_depth,
            self.seldepth,
            score_string,
            elapsed_ms,
            nodes,
            nps,
            hashfull,
            pv_string,
        }) catch return;
        stdout.flush() catch {};
    }
};
