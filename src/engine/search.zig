const std = @import("std");
const mvs = @import("moves");
const brd = @import("board");
const eval = @import("eval");
const tt = @import("transposition");
const see = @import("see");

inline fn kingInCheck(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) bool {
    return move_gen.isInCheck(board, color);
}

pub const max_ply = 128;
pub const max_game_ply = 1024;

pub var aspiration_window: i32 = 39;

pub var rfp_depth: i32 = 7;
pub var rfp_mul: i32 = 102;
pub var rfp_improve: i32 = 24;

pub var nmp_improve: i32 = 23;
pub var nmp_base: usize = 3;
pub var nmp_depth_div: usize = 5;
pub var nmp_beta_div: usize = 155;

pub var razoring_base: i32 = 294;
pub var razoring_mul: i32 = 88;

pub var iid_depth: usize = 1;

pub var lmp_improve: usize = 2;
pub var lmp_base: usize = 5;
pub var lmp_mul: usize = 2;

pub var futility_mul: i32 = 165;

const score_hash: i32 = 2_000_000_000;
const score_winning_capture: i32 = 1_000_000;
const score_promotion: i32 = 900_000;
const score_killer_1: i32 = 800_000;
const score_killer_2: i32 = 790_000;
const score_equal_capture: i32 = 700_000;
const score_counter: i32 = 600_000;

pub var q_see_margin: i32 = -35;
pub var q_delta_margin: i32 = 184;

pub var lmr_base: i32 = 64;
pub var lmr_mul: i32 = 36;

pub var lmr_pv_min: usize = 7;
pub var lmr_non_pv_min: usize = 4;

pub var se_reduction: usize = 4;
pub var history_div: i32 = 9319;

pub var quiet_lmr: [64][64]i32 = undefined;

pub fn initQuietLMR() [64][64]i32 {
    const base: f32 = @as(f32, @floatFromInt(lmr_base)) / 10;
    const mul: f32 = @as(f32, @floatFromInt(lmr_mul)) / 10;

    var table: [64][64]i32 = undefined;
    for (1..64) |d| {
        for (1..64) |m| {
            const a = base + std.math.log(f32, std.math.e, @as(f32, @floatFromInt(d))) *
                std.math.log(f32, std.math.e, @as(f32, @floatFromInt(m))) * mul;
            table[d][m] = @as(i32, @intFromFloat(a));
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

    move_gen: mvs.MoveGen = undefined,

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

    eval_history: [max_ply]i32 = undefined,
    move_history: [max_ply]mvs.EncodedMove = undefined,
    moved_piece_history: [max_ply]PieceColor = undefined,
    killer: [max_ply][2]mvs.EncodedMove = undefined,
    history: [2][64][64]i32 = undefined,
    counter_moves: [2][64][64]mvs.EncodedMove = undefined,
    excluded_moves: [max_ply]mvs.EncodedMove = undefined,
    continuation: *[12][64][64][64]i32 = undefined,
    correction: [2][16384]i32 = undefined,
    capture_history: [2][7][64][7]i32 = undefined,

    nmp_min_ply: usize = 0,

    thread_id: usize = 0,
    root_board: *brd.Board = undefined,
    silent_output: bool = false,

    const PieceColor = struct {
        piece: brd.Pieces,
        color: brd.Color,
    };

    pub fn init() Searcher {
        std.debug.print("Initializing searcher...\n", .{});
        var s = Searcher{
            .timer = std.time.Timer.start() catch {
                std.debug.panic("Failed to start timer", .{});
            },
            .move_gen = mvs.MoveGen.init(),
            .continuation = std.heap.c_allocator.create([12][64][64][64]i32) catch {
                std.debug.panic("Failed to allocate continuation table", .{});
            },
        };
        s.resetHeuristics(true);
        std.debug.print("Searcher initialized.\n", .{});

        search_helpers = std.ArrayList(Searcher).initCapacity(std.heap.c_allocator, 4) catch {
            std.debug.panic("Failed to initialize search helpers", .{});
        };

        threads = std.ArrayList(std.Thread).initCapacity(std.heap.c_allocator, 4) catch {
            std.debug.panic("Failed to initialize threads array", .{});
        };

        return s;
    }

    pub fn initInPlace(self: *Searcher) void {
        std.debug.print("Initializing searcher...\n", .{});
        self.timer = std.time.Timer.start() catch unreachable;
        self.move_gen = mvs.MoveGen.init();
        self.continuation = std.heap.page_allocator.create([12][64][64][64]i32) catch unreachable;
        self.resetHeuristics(true);
        std.debug.print("Searcher initialized.\n", .{});
    }

    pub fn deinit(self: *Searcher) void {
        std.heap.c_allocator.destroy(self.continuation);
    }

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
            } else {
                for (&self.correction[c]) |*val| {
                    val.* = @divTrunc(val.* * 1, 8);
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
                            self.capture_history[c][a][j][t] = @divTrunc(self.capture_history[c][a][j][t] * 1, 8);
                        }
                    }
                }
            }

            for (0..64) |k| {
                for (0..2) |c| {
                    if (total) {
                        self.history[c][j][k] = 0;
                    } else {
                        self.history[c][j][k] = @divTrunc(self.history[c][j][k] * 1, 8);
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
                            self.continuation[l][j][k][m] = @divTrunc(self.continuation[l][j][k][m] * 1, 8);
                        }
                    }
                }
            }
        }
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

    pub fn initHelperThreads(num_threads: usize) !void {
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
            var helper = Searcher.init();
            helper.thread_id = i;
            helper.silent_output = true; // not used but for future
            try search_helpers.append(std.heap.c_allocator, helper);
        }

        std.debug.print("Initialized {} helper threads\n", .{num_threads - 1});
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
            try initHelperThreads(num_threads);
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
        tt.stop_signal.store(false, .release);
        self.resetHeuristics(false);
        self.nodes = 0;
        self.best_move = mvs.EncodedMove.fromU32(0);
        self.best_move_score = -eval.mate_score;
        self.timer = std.time.Timer.start() catch unreachable;

        
        var prev_score: i32 = -eval.mate_score;
        var score: i32 = -eval.mate_score;

        var bm = mvs.EncodedMove.fromU32(0);
        var best_pv: [max_ply]mvs.EncodedMove = undefined;
        var best_pv_length: usize = 0;

        var stability: usize = 0;

        var outer_depth: usize = 1;
        const bound: usize = if (max_depth != null) @as(usize, max_depth.?) else max_game_ply - 2;

        outer: while (outer_depth <= bound) : (outer_depth += 1) {
            self.ply = 0;
            self.seldepth = 0;

            var alpha = if (outer_depth > 1) prev_score - aspiration_window else -eval.mate_score;
            var beta = if (outer_depth > 1) prev_score + aspiration_window else eval.mate_score;
            var delta: i32 = aspiration_window;

            const depth = outer_depth;

            var window_failed = false;
            while (true) {
                self.search_depth = @max(self.search_depth, depth);
                self.nmp_min_ply = 0;

                score = self.negamax(board, board.toMove(), depth, alpha, beta, false, if (depth == outer_depth) NodeType.Root else NodeType.PV, false);

                if (self.time_stop or self.should_stop()) {
                    self.time_stop = true;
                    tt.stop_signal.store(true, .release);
                    break :outer;
                }

                if (score <= alpha) {
                    beta = @divTrunc(alpha + beta, 2);
                    alpha = @max(alpha - delta, -eval.mate_score);
                    delta += @divTrunc(delta, 2);
                    window_failed = false; // fail high is still good
                } else if (score >= beta) {
                    beta = @min(beta + delta, eval.mate_score);
                    delta += @divTrunc(delta, 2);
                    window_failed = true;
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

            // bm = self.best_move;
            // best_pv = self.pv[0];
            // best_pv_length = self.pv_length[0];
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

            if (score - prev_score > aspiration_window) {
                factor *= 1.3;
            } else if (prev_score - score > aspiration_window) {
                factor *= 1.5;
            }

            prev_score = score;

            if (self.should_not_continue(factor)) {
                break;
            }
        }

        self.best_move = bm;

        self.is_searching = false;

        tt.global_tt.incrememtAge();

        // Guard against null moves
        if (self.best_move.toU32() == 0) {
            if (tt.global_tt.get(board.game_state.zobrist)) |e| {
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

    pub fn negamax(self: *Searcher, board: *brd.Board, color: brd.Color, depth_: usize, alpha_: i32, beta_: i32, is_null: bool, node_type: NodeType, cutnode: bool) i32 {
        // std.debug.print("Entering negamax: depth={}, alpha={}, beta={}, is_null={}, node_type={}\n", .{depth_, alpha_, beta_, is_null, node_type});
        var alpha = alpha_;
        var beta = beta_;
        var depth = depth_;

        const corr_idx = board.game_state.zobrist & 16383;

        self.pv_length[self.ply] = 0;

        if (self.nodes & 2047 == 0 and self.should_stop()) {
            self.time_stop = true;
            tt.stop_signal.store(true, .release);
            return 0;
        }

        self.seldepth = @max(self.seldepth, self.ply);

        const is_root: bool = node_type == NodeType.Root;
        const on_pv: bool = node_type != NodeType.NonPV;

        if (self.ply == max_ply) {
            // return eval.evaluate(board, &self.move_gen);
            return eval.evaluate(board, &self.move_gen, alpha, beta, true);
        }

        const in_check: bool = kingInCheck(board, &self.move_gen, color);

        // check extension
        if (in_check) {
            depth += 1;
        }

        if (depth == 0) {
            return self.quiescenceSearch(board, color, alpha, beta);
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

        if (!is_root and isDraw(board)) {
            return 0;
        }

        var hash_move = mvs.EncodedMove.fromU32(0);
        var tt_hit = false;
        var tt_eval: i32 = 0;
        var tt_score: i32 = 0;
        var tt_e_flag: tt.EstimationType = .None;
        var tt_depth: usize = 0;
        const entry = tt.global_tt.get(board.game_state.zobrist);

        if (entry) |e| {
            tt_hit = true;
            tt_eval = e.eval;
            tt_depth = @as(usize, @intCast(e.depth));
            tt_score = tt_eval;
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
            static_eval = eval.evaluate(board, &self.move_gen, alpha, beta, true);

            static_eval += @divTrunc(self.correction[@as(usize, @intFromEnum(color))][@as(usize, @intCast(corr_idx))], 256);
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
            depth -= 1;
        }

        if (!in_check and !on_pv and self.excluded_moves[self.ply].toU32() == 0) {
            low_estimate_score = if (!tt_hit or entry.?.flag == tt.EstimationType.Under) static_eval else tt_eval;

            // reverse futility pruning
            if (@abs(beta) < eval.mate_score - 256 and
                depth <= @as(usize, @intCast(rfp_depth)))
            {
                var n: i32 = @as(i32, @intCast(depth)) * rfp_mul;

                if (improving) {
                    n -= rfp_improve;
                }

                if (static_eval - n >= beta) {
                    return beta;
                }
            }

            // razoring
            if (depth <= 4) {
                const threshold = razoring_base + (razoring_mul * @as(i32, @intCast(depth)));
                if (static_eval + threshold < alpha) {
                    return self.quiescenceSearch(board, color, alpha, beta);
                }
            }

            // null move pruning
            var nmp_static_eval: i32 = static_eval;
            if (improving) {
                nmp_static_eval += nmp_improve;
            }

            if (!is_null and depth >= 3 and self.ply >= self.nmp_min_ply and nmp_static_eval >= beta and has_non_pawns) {
                var r = nmp_base + depth / nmp_depth_div;
                r += @as(usize, @intCast(@min(4, @divTrunc(static_eval - beta, @as(i32, @intCast(nmp_beta_div))))));
                r = @min(r, depth);

                self.ply += 1;
                board.makeNullMove();
                var null_score = -self.negamax(board, brd.flipColor(color), depth - r, -beta, -beta + 1, true, NodeType.NonPV, !cutnode);
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

        // if (!in_check and !on_pv and depth >= 5 and @abs(beta) < eval.mate_score - 256) {
        //     var prob_moves = self.move_gen.generateCaptureMoves(board, color);
        //     const prob_beta = beta + probcut_margin;
        //
        //     var prob_scores = self.scoreMoves(board, &prob_moves, mvs.EncodedMove.fromU32(0), false);
        //
        //     for (0..prob_moves.len) |i| {
        //         const move = getNextBest(&prob_moves, &prob_scores, i);
        //
        //         mvs.makeMove(board, move);
        //
        //         if (kingInCheck(board, &self.move_gen, color)) {
        //             mvs.undoMove(board, move);
        //             continue;
        //         }
        //
        //         if (see.seeCapture(board, &self.move_gen, move) <= 0) {
        //             mvs.undoMove(board, move);
        //             continue;
        //         }
        //
        //         self.ply += 1;
        //
        //         const prob_score = -self.negamax(board, brd.flipColor(color), depth - probcut_depth, -prob_beta, -prob_beta + 1, false, NodeType.NonPV, !cutnode);
        //         self.ply -= 1;
        //         mvs.undoMove(board, move);
        //
        //         if (prob_score >= prob_beta) {
        //             return prob_score;
        //         }
        //     }
        // }

        // If no TT hit do quick search to populate TT
        if (depth >= 4 and !tt_hit and (on_pv or is_root or cutnode)) {
            var iid = @min(iid_depth, @divTrunc(depth, 2));
            iid = @max(iid, 1);

            _ = self.negamax(board, color, iid, alpha, beta, false, node_type, false);

            if (tt.global_tt.get(board.game_state.zobrist)) |e| {
                hash_move = e.move;
                tt_hit = true;
                tt_eval = e.eval;
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

        var eval_moves = self.scoreMoves(board, &move_list, hash_move, is_null);

        var best_move = mvs.EncodedMove.fromU32(0);
        best_score = -eval.mate_score + @as(i32, @intCast(self.ply));

        var skip_quiet: bool = false;
        var quiet_count: usize = 0;
        var other_count: usize = 0;
        var legals: usize = 0;
        var searched_moves: usize = 0;

        for (0..move_count) |i| {
            var move = getNextBest(&move_list, &eval_moves, i);
            if (move.toU32() == self.excluded_moves[self.ply].toU32()) {
                continue;
            }

            const is_capture = move.capture == 1;
            const is_killer = move.toU32() == self.killer[self.ply][0].toU32() or move.toU32() == self.killer[self.ply][1].toU32();

            if (!is_capture) {
                quiet_moves.addEncodedMove(move);
                quiet_count += 1;
            } else {
                other_moves.addEncodedMove(move);
                other_count += 1;
            }

            // const is_counter_move = self.counter_moves[@as(usize, @intFromEnum(color))][move.start_square][move.end_square].toU32() == move.toU32();

            const is_important = is_killer or (move.promoted_piece == @intFromEnum(brd.Pieces.Queen));

            if (skip_quiet and !is_capture and !is_important) {
                continue;
            }

            if (depth <= 5 and !is_root and i > 1 and !in_check and !on_pv ) {
                var lmp_threshold: usize = lmp_base + depth * lmp_mul;
                // var lmp_threshold: usize = (3 + depth * depth);

                if (self.thread_id % 2 == 1) {
                    lmp_threshold += 4;
                }

                if (improving) {
                    lmp_threshold += lmp_improve;
                }

                // Prune if we have searched enough quiet moves
                if (quiet_count > lmp_threshold) {
                    skip_quiet = true;
                }
            }

            // futility pruning
            if (move.capture == 0 and depth <= 8 and !in_check and !on_pv and !is_important and !is_killer and static_eval + ((@as(i32, @intCast(depth)) + 1) * futility_mul) <= alpha) {
                continue;
            }

            mvs.makeMove(board, move);
            if (kingInCheck(board, &self.move_gen, color)) {
                mvs.undoMove(board, move);
                continue;
            } else {
                legals += 1;
                mvs.undoMove(board, move);
            }

            var extension: i32 = 0;

            // Singular Extensions, also double and triple
            if (self.ply > 0 and !is_root and self.ply < depth * 2 and depth >= 7 and
                tt_hit and entry.?.flag != tt.EstimationType.Over and !eval.almostMate(tt_eval) and
                hash_move.toU32() == move.toU32() and entry.?.depth >= depth - 3)
            {
                const margin: i32 = @as(i32, @intCast(depth)) * 2;
                const singular_beta = @max(tt_eval - margin, -eval.mate_score + 256);

                self.excluded_moves[self.ply] = hash_move;

                const singular_depth = if (depth > se_reduction) depth - se_reduction else 1;
                const singular_score = self.negamax(board, color, singular_depth, singular_beta - 1, singular_beta, true, NodeType.NonPV, cutnode);
                self.excluded_moves[self.ply] = mvs.EncodedMove.fromU32(0);

                if (singular_score < singular_beta) {
                    extension = 1;

                    // double extension
                    if (!on_pv and singular_score < singular_beta - 20 and self.ply < depth * 2) {
                        extension = 2;
                    }

                    // Triple extension for very singular moves
                    if (!on_pv and singular_score < singular_beta - 40 and self.ply < depth * 2) {
                        extension = 3;
                    }
                } else if (singular_beta >= beta) {
                    return singular_beta;
                }
            }

            // Check Extensions
            // else if (kingInCheck(board, &self.move_gen, brd.flipColor(color))) {
            //     if (self.ply < depth * 2) {
            //         extension = 1;
            //     }
            // }

            // Recapture Extensions
            else if (on_pv and !is_root and self.ply < depth * 2) {
                if (is_capture and last_move.capture == 1 and move.end_square == last_move.end_square) {
                    extension = 1;
                } else if (is_capture and self.ply >= 3 and last_last_last_move.capture == 1 and
                    move.end_square == last_last_last_move.end_square)
                {
                    extension = 1;
                }
            }

            // Pawn Push Extension
            else if (on_pv and !is_root and self.ply < depth * 2 and move.capture == 0) {
                if (board.getPieceFromSquare(move.start_square)) |piece| {
                    if (piece == .Pawn) {
                        // Pawn to 7th rank
                        const rank = move.end_square / 8;
                        const is_white = board.toMove() == .White;

                        if ((is_white and rank == 6) or (!is_white and rank == 1)) {
                            extension = 1;
                        }
                    }
                }
            }

            const new_depth: usize = @as(usize, @intCast(@as(i32, @intCast(depth)) + extension - 1));

            self.move_history[self.ply] = move;
            if (board.getPieceFromSquare(move.start_square)) |p| {
                self.moved_piece_history[self.ply] = .{ .piece = p, .color = board.getColorFromSquare(move.start_square).? };
            } else {
                self.moved_piece_history[self.ply] = .{ .piece = .None, .color = .White };
            }

            self.ply += 1;

            mvs.makeMove(board, move);
            searched_moves += 1;

            tt.global_tt.prefetch(board.game_state.zobrist);

            var score: i32 = 0;

            const min_lmr_move: usize = if (on_pv) lmr_pv_min else lmr_non_pv_min;
            var do_full_search = false;

            if (on_pv and searched_moves == 1) {
                score = -self.negamax(board, brd.flipColor(color), new_depth, -beta, -alpha, false, NodeType.PV, false);
            } else {
                if (!in_check and depth >= 3 and i >= min_lmr_move and !is_capture) {
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

                    reduction -= @divTrunc(self.history[@intFromEnum(color)][move.start_square][move.end_square], history_div);


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

        if (legals == 0) {
            // checkmate
            if (in_check) {
                return -eval.mate_score + @as(i32, @intCast(self.ply));
            } else {
                // stalemate
                return 0;
            }
        }

        if (!in_check and !is_null and (best_score > -eval.mate_score and best_score < eval.mate_score)) {
            const err = best_score - static_eval;
            const current_entry = &self.correction[@intFromEnum(color)][corr_idx];

            const new_val = current_entry.* + @divTrunc(err * 32, 256);
            current_entry.* = std.math.clamp(new_val, -16000, 16000);
        }

        if (alpha >= beta and !(best_move.capture == 1) and !(best_move.promoted_piece != 0)) {
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

        if (alpha >= beta and best_move.capture == 1) {
            // Update capture history for the move that caused beta cutoff
            const captured_piece_idx = @as(usize, @intCast(best_move.captured_piece));

            if (captured_piece_idx < 6) {
                // const bonus = @min(1536, @as(i32, @intCast(depth)) * 256);
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

        if (!skip_quiet and self.excluded_moves[self.ply].toU32() == 0) {
            var tt_flag = tt.EstimationType.Over;
            if (best_score >= beta) {
                tt_flag = tt.EstimationType.Under;
            } else if (alpha != alpha_) {
                tt_flag = tt.EstimationType.Exact;
            }

            tt.global_tt.set(
                tt.Entry{
                    .hash = board.game_state.zobrist,
                    .eval = best_score,
                    .move = best_move,
                    .flag = tt_flag,
                    .depth = @as(u8, @intCast(depth)),
                    .age = tt.global_tt.getAge(),
                },
            );
        }
        return best_score;
    }

    pub fn quiescenceSearch(self: *Searcher, board: *brd.Board, color: brd.Color, alpha_: i32, beta_: i32) i32 {
        var alpha = alpha_;
        const beta = beta_;

        if (self.nodes & 2047 == 0 and self.should_stop()) {
            self.time_stop = true;
            return 0;
        }

        self.pv_length[self.ply] = 0;

        if (isMaterialDraw(board)) {
            return 0;
        }

        if (self.ply >= max_ply) {
            // return eval.evaluate(board, &self.move_gen);
            return eval.evaluate(board, &self.move_gen, alpha, beta, true);
        }

        self.nodes += 1;

        const in_check: bool = kingInCheck(board, &self.move_gen, color);

        var best_score = -eval.mate_score + @as(i32, @intCast(self.ply));
        var static_eval: i32 = best_score;

        if (!in_check) {
            // static_eval = eval.evaluate(board, &self.move_gen);
            static_eval = eval.evaluate(board, &self.move_gen, alpha, beta, false);

            best_score = static_eval;

            if (best_score >= beta) {
                return beta;
            }
            if (best_score > alpha) {
                alpha = best_score;
            }
        }

        const queen_val = 950; // Or your engine's Queen value

        // If not in check (important! don't prune check escapes)
        if (!in_check) {
            // If our position + a free Queen + margin is still failing low...
            if (static_eval + queen_val + q_delta_margin < alpha) {
                return alpha;
            }
        }

        var hash_move = mvs.EncodedMove.fromU32(0);
        const entry = tt.global_tt.get(board.game_state.zobrist);

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

        var eval_list = self.scoreMoves(board, &move_list, hash_move, false);

        for (0..move_size) |i| {
            const move = getNextBest(&move_list, &eval_list, i);

            const see_value = see.seeCapture(board, &self.move_gen, move);

            if (see_value < -200) {
                continue;
            }

            var captured_piece_value: i32 = 0;

            if (move.capture == 1) {
                captured_piece_value = see.see_values[@as(usize, @intCast(move.captured_piece)) + 1];
            }

            if (see_value < q_see_margin and
                captured_piece_value < 300 and
                static_eval + see_value + captured_piece_value + q_delta_margin < alpha)
            {
                continue;
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

            if (kingInCheck(board, &self.move_gen, color)) {
                self.ply -= 1;
                mvs.undoMove(board, move);
                continue;
            }

            tt.global_tt.prefetch(board.game_state.zobrist);
            const score = -self.quiescenceSearch(board, brd.flipColor(color), -beta, -alpha);
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
        return best_score;
    }

    pub fn isDraw(board: *brd.Board) bool {
        // Fifty-move rule
        if (board.game_state.halfmove_clock >= 100) {
            return true;
        }

        // Insufficient material
        if (isMaterialDraw(board)) {
            return true;
        }

        // Threefold repetition
        if (isThreefoldRepetition(board)) {
            return true;
        }

        return false;
    }

    pub fn isMaterialDraw(board: *brd.Board) bool {
        const white_pawns = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Pawn)]);
        const black_pawns = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Pawn)]);

        const white_knights = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Knight)]);
        const black_knights = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Knight)]);

        const white_bishops = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)]);
        const black_bishops = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)]);

        const white_rooks = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Rook)]);
        const black_rooks = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Rook)]);

        const white_queens = @popCount(board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)]);
        const black_queens = @popCount(board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);

        // If any pawns, rooks, or queens exist, there's sufficient material
        if (white_pawns > 0 or black_pawns > 0) return false;
        if (white_rooks > 0 or black_rooks > 0) return false;
        if (white_queens > 0 or black_queens > 0) return false;

        // Count total minor pieces
        const white_minors = white_knights + white_bishops;
        const black_minors = black_knights + black_bishops;

        // King vs King
        if (white_minors == 0 and black_minors == 0) {
            return true;
        }

        // King + minor vs King
        if (white_minors == 1 and black_minors == 0) {
            return true;
        }
        if (white_minors == 0 and black_minors == 1) {
            return true;
        }

        // King + Bishop vs King + Bishop (same colored bishops)
        if (white_bishops == 1 and black_bishops == 1 and
            white_knights == 0 and black_knights == 0)
        {
            // Check if bishops are on same color squares
            const white_bishop_bb = board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)];
            const black_bishop_bb = board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)];

            const dark_squares: u64 = 0xaa55aa55aa55aa55;
            const white_on_dark = (white_bishop_bb & dark_squares) != 0;
            const black_on_dark = (black_bishop_bb & dark_squares) != 0;

            if (white_on_dark == black_on_dark) {
                return true;
            }
        }

        return false;
    }

    pub fn isThreefoldRepetition(board: *brd.Board) bool {
        const current_zobrist = board.game_state.zobrist;
        var repetition_count: u32 = 1;

        const halfmove_limit = @min(board.game_state.halfmove_clock, board.history.history_count);

        var i: usize = 0;
        while (i < halfmove_limit) : (i += 1) {
            const history_index = board.history.history_count - 1 - i;
            const past_state = board.history.history_list[history_index];

            if (past_state.zobrist == current_zobrist) {
                repetition_count += 1;
                if (repetition_count >= 3) {
                    return true;
                }
            }
        }

        return false;
    }

    pub fn scoreMoves(self: *Searcher, board: *brd.Board, move_list: *mvs.MoveList, hash_move: mvs.EncodedMove, is_null: bool) [218]i32 {
        var scores: [218]i32 = @splat(0);
        const hm = hash_move.toU32();

        // Pre-fetch history pointers to avoid lookups in the loop
        const side = @intFromEnum(board.toMove());

        // Counter move lookup prep
        var counter_move_u32: u32 = 0;
        if (self.ply > 0) {
            const last = self.move_history[self.ply - 1];
            counter_move_u32 = self.counter_moves[side][last.start_square][last.end_square].toU32();
        }

        for (move_list.items[0..move_list.len], 0..) |move, i| {
            var score: i32 = 0;
            const move_u32 = move.toU32();

            if (move_u32 == hm) {
                score = score_hash;
            } else if (move.capture == 1) {
                const see_val = see.seeCapture(board, &self.move_gen, move);
                
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

                score += self.capture_history[color_idx][attacking_piece_idx][move.end_square][capture_piece_idx];
            } else {
                if (move.promoted_piece != 0) {
                    if (move.promoted_piece == @intFromEnum(brd.Pieces.Queen)) {
                        score = score_promotion;
                    } else {
                        score = -5_000;
                    }
                } else if (move_u32 == self.killer[self.ply][0].toU32()) {
                    score = score_killer_1;
                } else if (move_u32 == self.killer[self.ply][1].toU32()) {
                    score = score_killer_2;
                } else if (move_u32 == counter_move_u32) {
                    score = score_counter;
                } else {
                    score = self.history[side][move.start_square][move.end_square];
                    if (!is_null and self.ply >= 1) {
                        const plies: [3]usize = .{ 0, 1, 3 };
                        for (plies) |p| {
                            const divider: i32 = 1;
                            if (self.ply >= p + 1) {
                                const prev = self.move_history[self.ply - p - 1];
                                if (prev.toU32() == 0) continue;

                                const piece_color = self.moved_piece_history[self.ply - p - 1];
                                const pc_index = @as(usize, @intCast(@intFromEnum(piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(piece_color.piece)));
                                score += @divTrunc(self.continuation[pc_index][prev.start_square][prev.end_square][move.end_square], divider);
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
        while (j < move_list.len) : (j += 1) {
            if (scores[start_index] < scores[j]) {
                std.mem.swap(mvs.EncodedMove, &move_list.items[start_index], &move_list.items[j]);
                std.mem.swap(i32, &scores[start_index], &scores[j]);
            }
        }
        return move_list.items[start_index];
    }

    pub fn printInfo(self: *Searcher, nodes: u64, score: i32, pv: []const mvs.EncodedMove, allocator: std.mem.Allocator) void {
        const elapsed_ms = self.timer.read() / std.time.ns_per_ms;

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
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

        // output info about the best move found
        stdout.print("info depth {d} seldepth {d} time {d} nodes {d} pv {s} score cp {d}\n", .{ self.search_depth, self.seldepth, elapsed_ms, nodes, pv_string, score }) catch {
            return;
        };
        stdout.flush() catch {};
    }
};
