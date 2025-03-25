const std = @import("std");
const mvs = @import("../chess/moves.zig");
const brd = @import("../chess/board.zig");
const eval = @import("eval.zig");
const tt = @import("transposition.zig");

pub const inf: f64 = 100000.0;

pub const SearchStats = struct {
    maxDepth: usize,
    nodes: usize,
    captures: usize,
    alphabeta_cutoffs: usize,
    transposition_cutoffs: usize,
    failed_high: usize,
    failed_low: usize,

    pub fn init() SearchStats {
        return SearchStats{
            .maxDepth = 0,
            .nodes = 0,
            .captures = 0,
            .alphabeta_cutoffs = 0,
            .transposition_cutoffs = 0,
            .failed_high = 0,
            .failed_low = 0,
        };
    }

    pub fn print(self: SearchStats) void {
        std.debug.print("Search Stats:\n", .{});
        std.debug.print("  Max Depth: {}\n", .{self.maxDepth});
        std.debug.print("  Nodes: {}\n", .{self.nodes});
        std.debug.print("  Captures: {}\n", .{self.captures});
        std.debug.print("  Alpha-Beta Cutoffs: {}\n", .{self.alphabeta_cutoffs}); 
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
        result.search_result = searchDepth(board, move_gen, table, depth, &result.stats, start_time, max_time);
    }
    result.stats.maxDepth = @intCast(depth);
    return result;
}

// assumption that board is not checkmate or draw
fn searchDepth(board: *brd.Board, move_gen: *mvs.MoveGen, table: *tt.TranspositionTable, depth: isize, stats: *SearchStats, start_time: isize, max_time: isize) SearchResult {
    const color: f64 = if (board.game_state.side_to_move == brd.Color.White) 1.0 else -1.0;
    const move_list = move_gen.generateMoves(board, false);
    var best_move: ?mvs.EncodedMove = null;
    var best_eval = -inf * color;
    var valid_move_found = false;

    const zobrist_key = board.game_state.zobrist;
    const tt_entry = table.get(zobrist_key);
    if (tt_entry != null and tt_entry.?.depth >= depth) {
        if (tt_entry.?.estimation == tt.EstimationType.Exact) {
            return SearchResult{
                .bestMove = tt_entry.?.move,
                .eval = tt_entry.?.score,
            };
        } else if (tt_entry.?.estimation == tt.EstimationType.Under and tt_entry.?.score > best_eval) {
            best_eval = tt_entry.?.score;
            best_move = tt_entry.?.move;
        }
    }

    for (0..move_list.current) |m| {
        const move = move_list.list[m];
        mvs.makeMove(board, move);

        if (std.time.milliTimestamp() - start_time >= max_time) {
            mvs.undoMove(board, move);
            break;
       }

        if (kingInCheck(board, move_gen, brd.flipColor(board.game_state.side_to_move))) {
            mvs.undoMove(board, move);
            continue;
        }

        const score = -alphaBeta(board, move_gen, table, depth - 1, -inf, -best_eval, -color, stats, start_time, max_time);
        mvs.undoMove(board, move);

        if (score > best_eval) {
            best_eval = score;
            best_move = move;
            valid_move_found = true;
        }
    }

    if (!valid_move_found) {
        @branchHint(.cold);
        if (kingInCheck(board, move_gen, board.game_state.side_to_move)) {
            return SearchResult{
                .bestMove = mvs.EncodedMove{},
                .eval = -inf * color,
            };
        } else {
            return SearchResult{
                .bestMove = mvs.EncodedMove{},
                .eval = 0,
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

    if (std.time.milliTimestamp() - start_time >= max_time) {
        return eval.evaluate(board) * color;
    }

    const zobrist_key = board.game_state.zobrist;
    const tt_entry = table.get(zobrist_key);
    if (tt_entry != null and tt_entry.?.depth >= depth) {
        stats.transposition_cutoffs += 1;
        if (tt_entry.?.estimation == tt.EstimationType.Exact) {
            return tt_entry.?.score;
        } else if (tt_entry.?.estimation == tt.EstimationType.Under and tt_entry.?.score >= beta) {
            stats.failed_high += 1;
            return tt_entry.?.score;
        } else if (tt_entry.?.estimation == tt.EstimationType.Over and tt_entry.?.score <= alpha) {
            stats.failed_low += 1;
            return tt_entry.?.score;
        }
    }

    if (depth <= 0) {
        return eval.evaluate(board) * color;
    }

    var a = alpha;
    var best_score = -inf;
    var best_move: ?mvs.EncodedMove = null;
    var estimation_type = tt.EstimationType.Over;

    const move_list = move_gen.generateMoves(board, false);
    var valid_move_count: usize = 0;

    for (0..move_list.current) |m| {
        const move = move_list.list[m];
        mvs.makeMove(board, move);

        if (kingInCheck(board, move_gen, brd.flipColor(board.game_state.side_to_move))) {
            mvs.undoMove(board, move);
            continue;
        }

        valid_move_count += 1;

        const score = -alphaBeta(board, move_gen, table, depth - 1, -beta, -a, -color, stats, start_time, max_time);
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
            return 0;
        }
    }

    if (best_move != null) {
        table.set(estimation_type, best_move.?, depth, best_score, zobrist_key);
    }

    return best_score;
}

// color is the color of the king
inline fn kingInCheck(board: *brd.Board, move_gen: *mvs.MoveGen, color: brd.Color) bool {
    const king_square = brd.getLSB(board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.King)]);
    return move_gen.isAttacked(king_square, brd.flipColor(color), board);
}
