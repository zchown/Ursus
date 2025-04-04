const std = @import("std");
const mvs = @import("../chess/moves.zig");
const brd = @import("../chess/board.zig");
const eval = @import("eval.zig");
const tt = @import("transposition.zig");

pub const inf: f64 = 100000.0;
const late_move_reduction: f64 = 0.5;
const late_move_reduction_depth: isize = 3;

pub const SearchStats = struct {
    maxDepth: usize,
    nodes: usize,
    captures: usize,
    alphabeta_cutoffs: usize,
    transposition_cutoffs: usize,
    failed_high: usize,
    failed_low: usize,
    quiescence_nodes: usize,

    pub fn init() SearchStats {
        return SearchStats{
            .maxDepth = 0,
            .nodes = 0,
            .captures = 0,
            .alphabeta_cutoffs = 0,
            .transposition_cutoffs = 0,
            .failed_high = 0,
            .failed_low = 0,
            .quiescence_nodes = 0,
        };
    }

    pub fn print(self: SearchStats) void {
        std.debug.print("Search Stats:\n", .{});
        std.debug.print("  Max Depth: {}\n", .{self.maxDepth});
        std.debug.print("  Nodes: {}\n", .{self.nodes});
        std.debug.print("  Captures: {}\n", .{self.captures});
        std.debug.print("  Alpha-Beta Cutoffs: {}\n", .{self.alphabeta_cutoffs});
        std.debug.print("  Quiescence Nodes: {}\n", .{self.quiescence_nodes});
    }
};

pub const SearchResult = struct {
    bestMove: mvs.EncodedMove,
    eval: f64,
    pub fn init() SearchResult {
        return SearchResult{
            .bestMove = mvs.EncodedMove{},
            .eval = 0,
        };
    }
};

pub const TotalSearchResult = struct {
    search_result: SearchResult,
    stats: SearchStats,
    pub fn init() TotalSearchResult {
        return TotalSearchResult{
            .search_result = SearchResult.init(),
            .stats = SearchStats.init(),
        };
    }
};

pub fn search(board: *brd.Board, move_gen: *mvs.MoveGen, table: *tt.TranspositionTable, max_time: isize) TotalSearchResult {
    var result = TotalSearchResult.init();
    var depth: isize = 0;
    const start_time = std.time.milliTimestamp();
    while (std.time.milliTimestamp() - start_time < max_time) {
        depth += 1;
        std.debug.print("Depth: {}\n", .{depth});
        const temp = searchDepth(board, move_gen, table, depth, &result.stats, start_time, max_time);
        if (temp.bestMove == mvs.EncodedMove{} or std.time.milliTimestamp() - start_time >= max_time) {
            break;
        } else {
            result.search_result = temp;
        }
    }
    result.stats.maxDepth = @intCast(depth);
    result.search_result.bestMove.printAlgebraic();
    return result;
}

// assumption that board is not checkmate or draw
fn searchDepth(board: *brd.Board, move_gen: *mvs.MoveGen, table: *tt.TranspositionTable, d: isize, stats: *SearchStats, start_time: isize, max_time: isize) SearchResult {
    const color: f64 = if (board.game_state.side_to_move == brd.Color.White) 1.0 else -1.0;
    const move_list = move_gen.generateMoves(board, false);
    var best_move: ?mvs.EncodedMove = null;
    var best_eval = -inf;
    var valid_move_found = false;
    var depth = d;

    const zobrist_key = board.game_state.zobrist;

    std.debug.print("Move List: {}\n", .{move_list.current});
    std.debug.print("color: {}\n", .{color});

    for (0..move_list.current) |m| {
        const move = move_list.list[m];
        // std.debug.print("Move: {}\n", .{move});

        if (std.time.milliTimestamp() - start_time >= max_time) {
            // std.debug.print("Time limit reached\n", .{});
            if (depth > 1) {
                if (valid_move_found) {
                    return SearchResult{
                        .bestMove = best_move.?,
                        .eval = best_eval,
                    };
                } else {
                    return SearchResult{
                        .bestMove = mvs.EncodedMove{},
                        .eval = -inf,
                    };
                }
            }
            depth = 1;
        }

        mvs.makeMove(board, move);

        if (kingInCheck(board, move_gen, brd.flipColor(board.game_state.side_to_move))) {
            std.debug.print("Move puts king in check\n", .{});
            mvs.undoMove(board, move);
            continue;
        }

        const score = -alphaBeta(board, move_gen, table, depth - 1, -inf, -best_eval, -color, stats, start_time, max_time);
        std.debug.print("Score: {}\n", .{score});
        mvs.undoMove(board, move);

        if (score > best_eval) {
            best_eval = score;
            best_move = move;
            valid_move_found = true;
        }
    }

    if (!valid_move_found) {
        std.debug.print("No valid moves found\n", .{});
        // @panic("No valid moves found");
        if (kingInCheck(board, move_gen, board.game_state.side_to_move)) {
            return SearchResult{
                .bestMove = mvs.EncodedMove{},
                .eval = -inf * color,
            };
        } else {
            return SearchResult{
                .bestMove = mvs.EncodedMove{},
                .eval = -inf * color,
            };
        }
    }

    const estimation_type = tt.EstimationType.Exact;
    table.set(estimation_type, best_move.?, depth, best_eval, zobrist_key);

    return SearchResult{
        .bestMove = best_move.?,
        .eval = best_eval,
    };
}

fn alphaBeta(board: *brd.Board, move_gen: *mvs.MoveGen, table: *tt.TranspositionTable, depth: isize, alpha: f64, beta: f64, color: f64, stats: *SearchStats, start_time: isize, max_time: isize) f64 {
    stats.nodes += 1;

    const zobrist_key = board.game_state.zobrist;
    const entry = table.get(zobrist_key);
    if (entry != null) {
        if (entry.?.depth >= depth) {
            switch (entry.?.estimation) {
                tt.EstimationType.Exact => {
                    stats.transposition_cutoffs += 1;
                    return entry.?.score;
                },
                tt.EstimationType.Over => {
                    if (entry.?.score >= beta) {
                        stats.transposition_cutoffs += 1;
                        return entry.?.score;
                    }
                },
                tt.EstimationType.Under => {
                    if (entry.?.score <= alpha) {
                        stats.transposition_cutoffs += 1;
                        return entry.?.score;
                    }
                },
            }
        }
    }

    if (std.time.milliTimestamp() - start_time >= max_time) {
        return eval.evaluate(board) * color;
    }

    if (depth <= 0) {
        // Instead of immediately evaluating, continue with quiescence search
        return -quiescenceSearch(board, move_gen, table, alpha, beta, -color, stats, start_time, max_time);
    }

    var a = alpha;
    var best_score = -inf;
    var best_move: ?mvs.EncodedMove = null;
    var estimation_type = tt.EstimationType.Over;

    var move_list = move_gen.generateMoves(board, false);
    sortMoveList(&move_list);
    var valid_move_count: usize = 0;

    var d = depth;
    var reduction_flag = false;

    for (0..move_list.current) |m| {
        if (!reduction_flag and @as(f64, @floatFromInt(move_list.current)) * late_move_reduction < @as(f64, @floatFromInt(m))) {
            d = depth - late_move_reduction_depth;
            reduction_flag = true;
        }

        const move = move_list.list[m];
        mvs.makeMove(board, move);

        if (kingInCheck(board, move_gen, brd.flipColor(board.game_state.side_to_move))) {
            mvs.undoMove(board, move);
            continue;
        }

        valid_move_count += 1;

        const score = -alphaBeta(board, move_gen, table, d - 1, -beta, -a, -color, stats, start_time, max_time);
        mvs.undoMove(board, move);

        if (score > best_score) {
            best_score = score;
            best_move = move;

            if (score > a) {
                a = score;
                estimation_type = tt.EstimationType.Exact;

                if (a >= beta) {
                    stats.alphabeta_cutoffs += 1;
                    estimation_type = tt.EstimationType.Under;
                    break;
                }
            }
        }
    }

    if (valid_move_count == 0) {
        @branchHint(.cold);
        if (kingInCheck(board, move_gen, board.game_state.side_to_move)) {
            return (-inf + @as(f64, @floatFromInt(depth))) * color;
        } else {
            return -inf * color;
        }
    }

    if (best_move != null) {
        table.set(estimation_type, best_move.?, depth, best_score, zobrist_key);
    }

    return best_score;
}

// Quiescence search function - continues search on capture moves to reach quiet positions
fn quiescenceSearch(board: *brd.Board, move_gen: *mvs.MoveGen, table: *tt.TranspositionTable, alpha: f64, beta: f64, color: f64, stats: *SearchStats, start_time: isize, max_time: isize) f64 {
    stats.quiescence_nodes += 1;

    if (std.time.milliTimestamp() - start_time >= max_time) {
        return eval.evaluate(board) * color;
    }

    const stand_pat = eval.evaluate(board) * color;

    if (stand_pat >= beta) {
        return stand_pat;
    }

    var a = alpha;
    if (stand_pat > a) {
        a = stand_pat;
    }

    const move_list = move_gen.generateMoves(board, true);

    for (0..move_list.current) |m| {
        const move = move_list.list[m];
        stats.captures += 1;

        if (!isLikelyGoodCapture(move)) {
            continue;
        }

        mvs.makeMove(board, move);

        if (kingInCheck(board, move_gen, brd.flipColor(board.game_state.side_to_move))) {
            mvs.undoMove(board, move);
            continue;
        }

        const score = -quiescenceSearch(board, move_gen, table, -beta, -a, -color, stats, start_time, max_time);
        mvs.undoMove(board, move);

        if (score >= beta) {
            return score;
        }
        if (score > a) {
            a = score;
        }
    }

    return a;
}

fn isLikelyGoodCapture(move: mvs.EncodedMove) bool {
    const attacker = move.piece;

    const victim = move.captured_piece;

    const piece_values = [_]i32{ 0, 100, 320, 330, 500, 900, 20000 };

    if (piece_values[victim] >= piece_values[(attacker)]) {
        return true;
    }

    return false;
}

inline fn kingInCheck(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) bool {
    const king_square = brd.getLSB(board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.King)]);
    return move_gen.isAttacked(king_square, brd.flipColor(color), board);
}

inline fn scoreMove(move: mvs.EncodedMove) f64 {
    var score: f64 = 0.0;

    const piece_values = [_]f64{ 0.0, 1.0, 3.2, 3.3, 5.0, 9.0, 20000.0 };

    if (move.capture == 1) {
        score += piece_values[move.captured_piece];
        score -= piece_values[move.piece];
    }
    if (move.promoted_piece != 0) {
        score += piece_values[move.promoted_piece];
    }
    return score;
}

inline fn sortMoveList(move_list: *mvs.MoveList) void {
    const move_count = move_list.current;
    var scored_moves: [218]f64 = undefined;

    // Score all moves first
    for (0..move_count) |i| {
        scored_moves[i] = scoreMove(move_list.list[i]);
    }

    // Now quick sort them
    quickSortMoves(move_list.list[0..move_count], scored_moves[0..move_count], 0, @as(isize, (@intCast(move_count))) - 1);
}

fn quickSortMoves(moves: []mvs.EncodedMove, scores: []f64, low: isize, high: isize) void {
    if (low < high) {
        const pi = partition(moves, scores, low, high);
        quickSortMoves(moves, scores, low, pi - 1);
        quickSortMoves(moves, scores, pi + 1, high);
    }
}

fn partition(moves: []mvs.EncodedMove, scores: []f64, low: isize, high: isize) isize {
    const pivot = scores[@as(usize, @intCast(high))];
    var i = low - 1;

    var j: isize = low;
    while (j <= high - 1) : (j += 1) {
        if (scores[@as(usize, @intCast(j))] > pivot) {
            i += 1;
            swapMoves(moves, scores, @as(usize, @intCast(i)), @as(usize, @intCast(j)));
        }
    }

    swapMoves(moves, scores, @as(usize, @intCast(i + 1)), @as(usize, @intCast(high)));
    return i + 1;
}

fn swapMoves(moves: []mvs.EncodedMove, scores: []f64, a: usize, b: usize) void {
    const temp_score = scores[a];
    scores[a] = scores[b];
    scores[b] = temp_score;

    const temp_move = moves[a];
    moves[a] = moves[b];
    moves[b] = temp_move;
}
