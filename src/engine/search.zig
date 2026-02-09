const std = @import("std");
const mvs = @import("moves");
const brd = @import("board");
const eval = @import("eval");
const tt = @import("transposition");
const see = @import("see");
const pawn_tt = @import("pawn_tt");

inline fn kingInCheck(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) bool {
    return move_gen.isInCheck(board, color);
}

pub const max_ply = 128;
pub const max_game_ply = 1024;

pub const aspiration_window: i32 = 25;
pub const rfp_depth: i32 = 6;
pub const rfp_mul: i32 = 50;
pub const rfp_improve: i32 = 75;

pub const nmp_improve: i32 = 50;
pub const nmp_base: usize = 3;
pub const nmp_depth_div: usize = 3;
pub const nmp_beta_div: usize = 150;

pub const razoring_margin: i32 = 300;

const lmp_table = [_]usize{ 5, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64 }; 

pub const quiet_lmr: [64][64]i32 = blk: {
    break :blk initQuietLMR();
};

fn initQuietLMR() [64][64]i32 {
    @setEvalBranchQuota(1000000);
    var table: [64][64]i32 = undefined;
    for (1..64) |d| {
        for (1..64) |m| {
            const a = 0.5 * std.math.log(f32, std.math.e, @as(f32, @floatFromInt(d))) * std.math.log(f32, std.math.e, @as(f32, @floatFromInt(m))) + 0.75;
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

pub const Searcher = struct {
    min_depth: usize = 1,
    max_ms: u64 = 0,
    ideal_ms: u64 = 0,
    force_think: bool = false,
    search_depth: usize = 0,
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

    hash_history: std.ArrayList(u64) = undefined,
    eval_history: [max_ply]i32 = undefined,
    move_history: [max_ply]mvs.EncodedMove = undefined,
    moved_piece_history: [max_ply]PieceColor = undefined,
    killer: [max_ply][2]mvs.EncodedMove = undefined,
    history: [2][64][64]i32 = undefined,
    counter_moves: [2][64][64]mvs.EncodedMove = undefined,
    excluded_moves: [max_ply]mvs.EncodedMove = undefined,
    continuation: *[12][64][64][64]i32 = undefined,

    nmp_min_ply: usize = 0,

    thread_id: usize = 0,
    root_board: *brd.Board = undefined,
    silent_ouput: bool = false,

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
        s.hash_history = std.ArrayList(u64).initCapacity(std.heap.c_allocator, max_game_ply) catch {
            std.debug.panic("Failed to initialize hash history", .{});
        };
        s.resetHeuristics(true);
        std.debug.print("Searcher initialized.\n", .{});
        return s;
    }

    pub fn initInPlace(self: *Searcher) void {
        std.debug.print("Initializing searcher...\n", .{});
        self.timer = std.time.Timer.start() catch unreachable;
        self.move_gen = mvs.MoveGen.init();
        self.continuation = std.heap.page_allocator.create([12][64][64][64]i32) catch unreachable;
        self.hash_history = std.ArrayList(u64).initCapacity(std.heap.c_allocator, max_game_ply) catch unreachable;
        self.resetHeuristics(true);
        std.debug.print("Searcher initialized.\n", .{});
    }

    pub fn deinit(self: *Searcher) void {
        self.hash_history.deinit(std.heap.c_allocator);
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
            self.moved_piece_history[i] = PieceColor{
                .piece = .None,
                .color = .White,
            };
        }

        for (0..64) |j| {
            for (0..64) |k| {
                for (0..2) |c| {
                    if (total) {
                        self.history[c][j][k] = 0;
                    } else {
                        self.history[c][j][k] = @divTrunc(self.history[c][j][k], 2);
                    }
                    self.counter_moves[c][j][k] = mvs.EncodedMove.fromU32(0);
                }

                for (0..12) |l| {
                    for (0..64) |m| {
                        self.continuation[l][j][k][m] = 0;
                    }
                }
            }
        }
    }

    pub inline fn should_stop(self: *Searcher) bool {
        return self.stop or
            (self.thread_id == 0 and self.search_depth > self.min_depth and
                ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
                    (!self.force_think and self.timer.read() / std.time.ns_per_ms >= self.max_ms)));
    }

    pub inline fn should_not_continue(self: *Searcher, factor: f32) bool {
        return self.stop or
            (self.thread_id == 0 and self.search_depth > self.min_depth and
                ((self.max_nodes != null and self.nodes >= self.max_nodes.?) or
                    (!self.force_think and self.timer.read() / std.time.ns_per_ms >= @min(self.ideal_ms, @as(u64, @intFromFloat(@as(f32, @floatFromInt(self.ideal_ms)) * factor))))));
    }

    pub inline fn iterative_deepening(self: *Searcher, board: *brd.Board, max_depth: ?u8) !SearchResult {
        self.stop = false;
        self.is_searching = true;
        self.time_stop = false;
        self.resetHeuristics(false);
        self.nodes = 0;
        self.best_move = mvs.EncodedMove.fromU32(0);
        self.best_move_score = -eval.mate_score;
        self.timer = std.time.Timer.start() catch unreachable;

        if (!tt.global_tt_initialized or tt.global_tt.items.items.len == 0) {
            std.debug.print("Initializing transposition table...\n", .{});
            try tt.TranspositionTable.initGlobal(64);
            std.debug.print("Transposition table initialized with {} entries.\n", .{tt.global_tt.items.items.len});
        }

        if (!pawn_tt.pawn_tt_initialized or pawn_tt.pawn_tt.items.items.len == 0) {
            std.debug.print("Initializing pawn transposition table...\n", .{});
            try pawn_tt.TranspositionTable.initGlobal(8);
            std.debug.print("Pawn transposition table initialized with {} entries.\n", .{pawn_tt.pawn_tt.items.items.len});
        }

        var prev_score: i32 = -eval.mate_score;
        var score: i32 = -eval.mate_score;

        var bm = mvs.EncodedMove.fromU32(0);

        var stability: usize = 0;

        var outer_depth: usize = 1;
        const bound: usize = if (max_depth != null) @as(usize, max_depth.?) else max_game_ply - 2;

        outer: while (outer_depth <= bound) : (outer_depth += 1) {
            self.ply = 0;
            self.seldepth = 0;

            var alpha = -eval.mate_score;
            var beta = eval.mate_score;
            var delta = eval.mate_score;

            var depth = outer_depth;

            while (true) {
                // std.debug.print("Starting search at depth {} with alpha={} and beta={}\n", .{depth, alpha, beta});
                self.search_depth = @max(self.search_depth, depth);
                self.nmp_min_ply = 0;

                score = self.negamax(board, board.toMove(), depth, alpha, beta, false, if (depth == outer_depth) NodeType.Root else NodeType.PV, false);

                if (self.time_stop or self.should_stop()) {
                    self.time_stop = true;
                    break :outer;
                }

                if (score <= alpha) {
                    beta = @divTrunc(alpha + beta, 2);
                    alpha = @max(alpha - delta, -eval.mate_score);
                } else if (score >= beta) {
                    beta = @min(beta + delta, eval.mate_score);
                    if (depth > 1 and (outer_depth < 4 or depth > outer_depth - 4)) {
                        depth -= 1;
                    }
                } else {
                    break;
                }

                delta += @divTrunc(delta, 4);
            }

            if (self.best_move.toU32() != bm.toU32()) {
                stability = 0;
            } else {
                stability += 1;
            }

            bm = self.best_move;

            var factor: f32 = @max(0.5, 1.1 - 0.03 * @as(f32, @floatFromInt(stability)));

            if (score - prev_score > aspiration_window) {
                factor *= 1.1;
            }

            prev_score = score;

            if (self.should_not_continue(factor)) {
                break;
            }

            outer_depth += 1;
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
            .time_ms = self.timer.read() / std.time.ns_per_ms,
            .pv = self.pv[0],
            .pv_length = self.pv_length[0],
        };
    }

    pub fn negamax(self: *Searcher, board: *brd.Board, color: brd.Color, depth_: usize, alpha_: i32, beta_: i32, is_null: bool, node_type: NodeType, cutnode: bool) i32 {
        // std.debug.print("Entering negamax: depth={}, alpha={}, beta={}, is_null={}, node_type={}\n", .{depth_, alpha_, beta_, is_null, node_type});
        var alpha = alpha_;
        var beta = beta_;
        var depth = depth_;

        self.pv_length[self.ply] = 0;

        if (self.nodes & 2047 == 0 and self.should_stop()) {
            self.time_stop = true;
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
        const entry = tt.global_tt.get(board.game_state.zobrist);

        if (entry) |e| {
            tt_hit = true;
            tt_eval = e.eval;

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

        // If no TT hit do quick 1 ply search to populate TT
        if (depth >= 8 and !tt_hit and (on_pv or is_root)) {
            const iid_depth = 1;

            // Perform the shallow search to populat TT
            _ = self.negamax(board, color, iid_depth, alpha, beta, false, node_type, false);

            // Check TT again to see if we found a move
            if (tt.global_tt.get(board.game_state.zobrist)) |e| {
                hash_move = e.move;
                tt_hit = true;
                tt_eval = e.eval;
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

            // null move pruning
            var nmp_static_eval: i32 = static_eval;
            if (improving) {
                nmp_static_eval += nmp_improve;
            }

            if ((board.game_state.en_passant_square == null) and !is_null and depth >= 3 and self.ply >= self.nmp_min_ply and nmp_static_eval >= beta and has_non_pawns) {
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

                    if (depth < 12 or self.nmp_min_ply > 0) {
                        return null_score;
                    }

                    self.nmp_min_ply = self.ply + @as(usize, @intCast((depth - r) * 3 / 4));

                    const verify_score = self.negamax(board, color, depth - 1, beta - 1, beta, false, NodeType.NonPV, false);

                    self.nmp_min_ply = 0;

                    if (self.time_stop) {
                        return 0;
                    }

                    if (verify_score >= beta) {
                        return verify_score;
                    }
                }
            }

            // razoring
            if (depth <= 2 and static_eval + razoring_margin < alpha) {
                return self.quiescenceSearch(board, color, alpha, beta);
            }
        }

        // Actually run search
        var move_list = self.move_gen.generateMoves(board, false);
        const move_count: usize = move_list.len;

        var quiet_moves: mvs.MoveList = mvs.MoveList.init();

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
        var legals: usize = 0;

        for (0..move_count) |i| {
            // std.debug.print("Selecting move {}/{} at depth {}, legals so far: {}, quiet_count: {}, skip_quiet: {}\n", .{i, move_count, depth, legals, quiet_count, skip_quiet});
            var move = getNextBest(&move_list, &eval_moves, i);
            if (move.toU32() == self.excluded_moves[self.ply].toU32()) {
                continue;
            }

            const is_capture = move.capture == 1;
            const is_killer = move.toU32() == self.killer[self.ply][0].toU32() or move.toU32() == self.killer[self.ply][1].toU32();

            if (!is_capture) {
                quiet_moves.addEncodedMove(move);
                quiet_count += 1;
            }

            const is_important = is_killer or move.promoted_piece != 0;

            if (skip_quiet and !is_capture and !is_important) {
                continue;
            }

            if (!is_root and i > 1 and !in_check and !on_pv and has_non_pawns) {

                var lmp_threshold: usize = 0;
                if (depth < lmp_table.len) {
                    lmp_threshold = lmp_table[depth];
                } else {
                    lmp_threshold = 4 + depth * 2; // Fallback for high depths
                }

                if (improving) {
                    lmp_threshold += 2; // Allow checking more moves if we are improving
                }

                // Prune if we have searched enough quiet moves
                if (quiet_count > lmp_threshold) {
                    skip_quiet = true;
                }
            }

            legals += 1;

            if (move.capture == 0 and depth <= 8 and !in_check and !on_pv and !is_important and !is_killer and static_eval + ((@as(i32, @intCast(depth)) + 1) * 200) <= alpha) {
                continue; // Prune this move
            }

            var extension: i32 = 0;
            if (self.ply > 0 and !is_root and self.ply < depth * 2 and depth >= 7 and tt_hit and entry.?.flag != tt.EstimationType.Over and !eval.almostMate(tt_eval) and hash_move.toU32() == move.toU32() and entry.?.depth >= depth - 3) {
                const margin: i32 = @intCast(depth);
                const singular_beta = @max(tt_eval - margin, -eval.mate_score + 256);

                self.excluded_moves[self.ply] = hash_move;
                const singular_score = self.negamax(board, color, (depth - 1) / 2, singular_beta - 1, singular_beta, true, NodeType.NonPV, cutnode);
                self.excluded_moves[self.ply] = mvs.EncodedMove.fromU32(0);
                if (singular_score < singular_beta) {
                    extension = 1;
                } else if (singular_beta >= beta) {
                    return singular_beta;
                } else if (tt_eval >= beta) {
                    extension = -2;
                } else if (cutnode) {
                    extension = -1;
                }
            } else if (on_pv and !is_root and self.ply < depth * 2) {
                // recapture extension
                if (is_capture and (((last_move.capture == 1)) and move.end_square == last_move.end_square) or (last_last_last_move.capture == 1 and move.end_square == last_last_last_move.end_square)) {
                    extension = 1;
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

            if (kingInCheck(board, &self.move_gen, color)) {
                mvs.undoMove(board, move);
                self.ply -= 1;
                continue;
            }

            self.hash_history.append(std.heap.c_allocator, board.game_state.zobrist) catch {
                std.debug.panic("Failed to append to hash history", .{});
            };

            tt.global_tt.prefetch(board.game_state.zobrist);

            var score: i32 = 0;

            const min_lmr_move: usize = if (on_pv) 5 else 3;
            var do_full_search = false;

            if (on_pv and legals == 1) {
                score = -self.negamax(board, brd.flipColor(color), new_depth, -beta, -alpha, false, NodeType.PV, false);
            } else {
                if (!in_check and depth >= 3 and i >= min_lmr_move and !is_capture) {
                    var reduction: i32 = quiet_lmr[@min(depth, 63)][@min(i, 63)];

                    if (self.thread_id % 2 == 1) {
                        reduction -= 1;
                    }

                    if (improving) {
                        reduction -= 1;
                    }

                    if (!on_pv) {
                        reduction += 1;
                    }

                    reduction -= @divTrunc(self.history[@intFromEnum(color)][move.start_square][move.end_square], 6144);

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
            _ = self.hash_history.pop();

            if (self.time_stop) {
                return 0;
            }

            if (score > best_score) {
                best_score = score;
                best_move = move;

                if (is_root) {
                    self.best_move = best_move;
                    self.best_move_score = best_score;
                }

                if (!is_null) {
                    self.pv[self.ply][0] = move;
                    // std.mem.copyForwards(mvs.EncodedMove, self.pv[self.ply][1..(self.pv_length[self.ply + 1] + 1)], self.pv[self.ply + 1][0..(self.pv_length[self.ply + 1])]);
                    std.mem.copyForwards(mvs.EncodedMove, self.pv[self.ply][1..(self.pv_length[self.ply + 1] + 1)], self.pv[self.ply + 1][0..(self.pv_length[self.ply + 1])]);

                    self.pv_length[self.ply] = self.pv_length[self.ply + 1] + 1;
                }

                if (score > alpha) {
                    alpha = score;

                    if (alpha >= beta) {
                        break;
                    }
                }
            }
        }

        if (alpha >= beta and !(best_move.capture == 1) and !(best_move.promoted_piece != 0)) {
            var temp = self.killer[self.ply][0];
            if (temp.toU32() != best_move.toU32()) {
                self.killer[self.ply][1] = temp;
                self.killer[self.ply][0] = best_move;
            }

            const adj = @min(1536, @as(i32, @intCast(if (static_eval <= alpha) depth + 1 else depth)) * 384 - 384);

            if (!is_null and self.ply >= 1) {
                const last = self.move_history[self.ply - 1];
                self.counter_moves[@intFromEnum(color)][last.start_square][last.end_square] = best_move;
            }

            const b = best_move.toU32();
            const max_history: i32 = 16384;

            for (quiet_moves.items) |m| {
                const is_best = m.toU32() == b;
                const hist = self.history[@intFromEnum(color)][m.start_square][m.end_square] * adj;
                if (is_best) {
                    self.history[@intFromEnum(color)][m.start_square][m.end_square] += adj - @divTrunc(hist, max_history);
                } else {
                    self.history[@intFromEnum(color)][m.start_square][m.end_square] += -adj - @divTrunc(hist, max_history);
                }

                if (!is_null and self.ply >= 1) {
                    const plies: [3]usize = .{ 0, 1, 3 };
                    for (plies) |p| {
                        if (self.ply >= p + 1) {
                            const prev = self.move_history[self.ply - p - 1];
                            if (prev.toU32() == 0) continue;

                            const piece_color = self.moved_piece_history[self.ply - p - 1];
                            const pc_index = @as(usize, @intCast(@intFromEnum(piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(piece_color.piece)));
                            const cont_hist = self.continuation[pc_index][prev.start_square][prev.end_square][best_move.start_square] * adj;
                            if (is_best) {
                                self.continuation[pc_index][prev.start_square][prev.end_square][best_move.start_square] += adj - @divTrunc(cont_hist, max_history);
                            } else {
                                self.continuation[pc_index][prev.start_square][prev.end_square][best_move.start_square] += -adj - @divTrunc(cont_hist, max_history);
                            }
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
                    .age = tt.global_tt.age,
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
            static_eval = eval.evaluate(board, &self.move_gen, alpha, beta, true);
            best_score = static_eval;

            if (best_score >= beta) {
                return beta;
            }
            if (best_score > alpha) {
                alpha = best_score;
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
                return -eval.mate_score + @as(i32, @intCast(self.ply));
            }
        } else {
            move_list = self.move_gen.generateCaptureMoves(board, color);
        }

        const move_size = move_list.len;

        var eval_list = self.scoreMoves(board, &move_list, hash_move, false);

        for (0..move_size) |i| {
            const move = getNextBest(&move_list, &eval_list, i);

            if (see.seeCapture(board, &self.move_gen, move) < -200) {
                continue;
            }
            //
            // const see_value = see.seeCapture(board, &self.move_gen, move);
            // var captured_piece_value: i32 = 0;
            //
            // if (move.capture == 1) {
            //     captured_piece_value = see.see_values[@as(usize, @intCast(move.captured_piece)) + 1];
            // }

            // if (see_value < 0 and 
            // captured_piece_value < 300 and  // Not capturing Q/R
            // static_eval + see_value + captured_piece_value + 200 < alpha) {
            //     continue;
            // }


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

        var index: usize = 0;
        for (move_list.items) |move| {
            var score: i32 = 0;
            if (move.promoted_piece != 0) {
                // Assume queen is basically always better then rook or bishop promotion
                // Knight is more likely to be a good alternative
                if (move.promoted_piece == @intFromEnum(brd.Pieces.Queen)) {
                    score += 1_000_000;
                } else if (move.promoted_piece == @intFromEnum(brd.Pieces.Knight)) {
                    score += 600_000;
                }
            }

            if (hm == move.toU32()) {
                score += 6_000_000;
            } else if (move.capture == 1) {
                const see_score = see.seeCapture(board, &self.move_gen, move);
                if (see_score > 0) {
                    score += 1_000_000 + (see_score * 2);
                } else {
                    score += see_score;
                }
            } else {
                const last = if (self.ply > 0) self.move_history[self.ply - 1] else mvs.EncodedMove.fromU32(0);
                if (self.killer[self.ply][0].toU32() == move.toU32()) {
                    score += 900_000;
                } else if (self.killer[self.ply][1].toU32() == move.toU32()) {
                    score += 800_000;
                } else if (self.ply >= 1 and self.counter_moves[@intFromEnum(board.toMove())][last.start_square][last.end_square].toU32() == move.toU32()) {
                    score += 600_000;
                } else {
                    score += self.history[@intFromEnum(board.toMove())][move.start_square][move.end_square];
                    if (!is_null and self.ply >= 1) {
                        const plies: [3]usize = .{ 0, 1, 3 };
                        for (plies) |p| {
                            const divider: i32 = 1;
                            if (self.ply >= p + 1) {
                                const prev = self.move_history[self.ply - p - 1];
                                if (prev.toU32() == 0) continue;

                                const piece_color = self.moved_piece_history[self.ply - p];
                                const pc_index = @as(usize, @intCast(@intFromEnum(piece_color.color))) * 6 + @as(usize, @intCast(@intFromEnum(piece_color.piece)));
                                score += @divTrunc(self.continuation[pc_index][prev.start_square][prev.end_square][move.start_square], divider);
                            }
                        }
                    }
                }
            }
            scores[index] = score;
            index += 1;
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
};
