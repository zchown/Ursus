const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const fen_mod = @import("fen");
const srch = @import("search");
const eval = @import("eval");
const tt = @import("transposition");
const pawn_tt = @import("pawn_tt");

pub const DatagenConfig = struct {
    num_nodes : u64 = 5000,

    games_per_thread: u32 = 100,

    num_threads: u32 = 10,

    random_plies: u32 = 8,

    skip_early_plies: u32 = 12,

    adjudication_score: i32 = 2500,

    adjudication_count: u32 = 4,

    max_game_plies: u32 = 256,

    output_path: []const u8 = "data.txt",

    format: OutputFormat = .text,

    min_score: i32 = 0,

    max_score: i32 = 10000,
};

pub const OutputFormat = enum {
    text,
};

const GameResult = enum(u8) {
    WhiteWin = 0,
    BlackWin = 1,
    Draw = 2,
    Ongoing = 3,
};

fn resultToStr(result: GameResult) []const u8 {
    return switch (result) {
        .WhiteWin => "1.0",
        .BlackWin => "0.0",
        .Draw => "0.5",
        .Ongoing => "?",
    };
}

const SavedPosition = struct {
    fen_buf: [128]u8,
    fen_len: usize,
    score: i16,
    stm: brd.Color,
    result: GameResult,
    // Board state for binary output (piece bitboards + game state)
    piece_bb: [brd.num_colors][brd.num_pieces]brd.Bitboard,
    side_to_move: brd.Color,
};

const max_saved_per_game = 512;

const GameBuffer = struct {
    positions: [max_saved_per_game]SavedPosition,
    count: usize,

    fn init() GameBuffer {
        return .{
            .positions = undefined,
            .count = 0,
        };
    }

    fn add(self: *GameBuffer, pos: SavedPosition) void {
        if (self.count < max_saved_per_game) {
            self.positions[self.count] = pos;
            self.count += 1;
        }
    }

    fn setResult(self: *GameBuffer, result: GameResult) void {
        for (0..self.count) |i| {
            self.positions[i].result = result;
        }
    }
};

const Rng = struct {
    state: [4]u64,

    fn init(seed: u64) Rng {
        var s: [4]u64 = undefined;
        var z = seed;
        for (0..4) |i| {
            z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
            z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
            z = z ^ (z >> 31);
            s[i] = z;
        }
        return .{ .state = s };
    }

    fn next(self: *Rng) u64 {
        const result = std.math.rotl(u64, self.state[1] *% 5, 7) *% 9;
        const t = self.state[1] << 17;
        self.state[2] ^= self.state[0];
        self.state[3] ^= self.state[1];
        self.state[1] ^= self.state[2];
        self.state[0] ^= self.state[3];
        self.state[2] ^= t;
        self.state[3] = std.math.rotl(u64, self.state[3], 45);
        return result;
    }

    fn bounded(self: *Rng, bound: usize) usize {
        if (bound == 0) return 0;
        return @intCast(self.next() % @as(u64, @intCast(bound)));
    }
};

fn boardToFen(board: *const brd.Board, buf: []u8) usize {
    var idx: usize = 0;

    const piece_chars = [2][6]u8{
        [_]u8{ 'P', 'N', 'B', 'R', 'Q', 'K' },
        [_]u8{ 'p', 'n', 'b', 'r', 'q', 'k' },
    };

    // Piece placement
    var rank: usize = 8;
    while (rank > 0) {
        rank -= 1;
        var empty: u8 = 0;
        for (0..8) |file| {
            const sq = rank * 8 + file;
            var found = false;
            for (0..brd.num_colors) |c| {
                for (0..brd.num_pieces) |p| {
                    if (board.piece_bb[c][p] & (@as(brd.Bitboard, 1) << @intCast(sq)) != 0) {
                        if (empty > 0) {
                            buf[idx] = '0' + empty;
                            idx += 1;
                            empty = 0;
                        }
                        buf[idx] = piece_chars[c][p];
                        idx += 1;
                        found = true;
                        break;
                    }
                }
                if (found) break;
            }
            if (!found) {
                empty += 1;
            }
        }
        if (empty > 0) {
            buf[idx] = '0' + empty;
            idx += 1;
        }
        if (rank > 0) {
            buf[idx] = '/';
            idx += 1;
        }
    }

    // Side to move
    buf[idx] = ' ';
    idx += 1;
    buf[idx] = if (board.game_state.side_to_move == .White) 'w' else 'b';
    idx += 1;

    // Castling rights
    buf[idx] = ' ';
    idx += 1;
    const cr = board.game_state.castling_rights;
    if (cr == 0) {
        buf[idx] = '-';
        idx += 1;
    } else {
        if (cr & @intFromEnum(brd.CastleRights.WhiteKingside) != 0) {
            buf[idx] = 'K';
            idx += 1;
        }
        if (cr & @intFromEnum(brd.CastleRights.WhiteQueenside) != 0) {
            buf[idx] = 'Q';
            idx += 1;
        }
        if (cr & @intFromEnum(brd.CastleRights.BlackKingside) != 0) {
            buf[idx] = 'k';
            idx += 1;
        }
        if (cr & @intFromEnum(brd.CastleRights.BlackQueenside) != 0) {
            buf[idx] = 'q';
            idx += 1;
        }
    }

    // En passant
    buf[idx] = ' ';
    idx += 1;
    if (board.game_state.en_passant_square) |ep| {
        buf[idx] = 'a' + @as(u8, @intCast(ep % 8));
        idx += 1;
        buf[idx] = '1' + @as(u8, @intCast(ep / 8));
        idx += 1;
    } else {
        buf[idx] = '-';
        idx += 1;
    }

    // Halfmove clock and fullmove number
    buf[idx] = ' ';
    idx += 1;
    idx += writeU32(buf[idx..], board.game_state.halfmove_clock);
    buf[idx] = ' ';
    idx += 1;
    idx += writeU32(buf[idx..], board.game_state.fullmove_number);

    return idx;
}

fn writeU32(buf: []u8, val: anytype) usize {
    const v: u32 = @intCast(val);
    if (v == 0) {
        buf[0] = '0';
        return 1;
    }
    var tmp: [10]u8 = undefined;
    var len: usize = 0;
    var remaining = v;
    while (remaining > 0) {
        tmp[len] = @intCast('0' + (remaining % 10));
        len += 1;
        remaining /= 10;
    }

    for (0..len) |i| {
        buf[i] = tmp[len - 1 - i];
    }
    return len;
}

fn writeI16(buf: []u8, val: i16) usize {
    var idx: usize = 0;
    var v = val;
    if (v < 0) {
        buf[idx] = '-';
        idx += 1;
        v = -v;
    }
    idx += writeU32(buf[idx..], @as(u32, @intCast(v)));
    return idx;
}

fn playSingleGame(
    searcher: *srch.Searcher,
    rng: *Rng,
    config: *const DatagenConfig,
    game_buf: *GameBuffer,
) void {
    game_buf.* = GameBuffer.init();

    var board = brd.Board.init();
    fen_mod.setupStartingPosition(&board);

    var random_ok = true;
    for (0..config.random_plies) |_| {
        var move_list = searcher.move_gen.generateMoves(&board, false);

        // Filter to legals
        var legal_count: usize = 0;
        var legal_moves: [218]mvs.EncodedMove = undefined;
        for (move_list.items[0..move_list.len]) |move| {
            mvs.makeMove(&board, move);
            if (!searcher.move_gen.isInCheck(&board, board.justMoved())) {
                legal_moves[legal_count] = move;
                legal_count += 1;
            }
            mvs.undoMove(&board, move);
        }
        if (legal_count == 0) {
            random_ok = false;
            break;
        }
        const pick = rng.bounded(legal_count);
        mvs.makeMove(&board, legal_moves[pick]);
    }

    if (!random_ok) return;

    if (srch.Searcher.isDraw(&board, 0)) return;

    {
        const opening_eval = eval.evaluate(&board, &searcher.move_gen, -eval.mate_score, eval.mate_score, true);
        const abs_eval = if (opening_eval < 0) -opening_eval else opening_eval;
        if (abs_eval > config.adjudication_score) return;
    }

    var result: GameResult = .Ongoing;
    var ply: u32 = 0;
    var adjudication_counter: u32 = 0;

    while (result == .Ongoing and ply < config.max_game_plies) {
        if (srch.Searcher.isDraw(&board, 0)) {
            result = .Draw;
            break;
        }

        var move_list = searcher.move_gen.generateMoves(&board, false);
        var has_legal = false;
        for (move_list.items[0..move_list.len]) |move| {
            mvs.makeMove(&board, move);
            if (!searcher.move_gen.isInCheck(&board, board.justMoved())) {
                has_legal = true;
            }
            mvs.undoMove(&board, move);
            if (has_legal) break;
        }

        if (!has_legal) {
            const in_check = searcher.move_gen.isInCheck(&board, board.toMove());
            if (in_check) {
                // Checkmate
                result = if (board.toMove() == .White) .BlackWin else .WhiteWin;
            } else {
                // Stalemate
                result = .Draw;
            }
            break;
        }

        // Search this position
        searcher.stop = false;
        searcher.is_searching = true;
        searcher.time_stop = false;
        searcher.silent_output = true;
        searcher.max_ms = std.math.maxInt(u64);
        searcher.ideal_ms = std.math.maxInt(u64);
        searcher.max_nodes = null;
        searcher.soft_max_nodes = null;
        searcher.force_think = false;

        tt.stop_signal.store(false, .release);

        searcher.max_nodes = @as(u64, config.num_nodes);
        const search_result = searcher.iterativeDeepening(&board, null) catch {
            break;
        };

        const score = search_result.score;
        const best_move = search_result.move;

        if (best_move.toU32() == 0) break;

        // Adjudication
        const abs_score = if (score < 0) -score else score;
        if (abs_score >= config.adjudication_score) {
            adjudication_counter += 1;
            if (adjudication_counter >= config.adjudication_count) {
                if (score > 0) {
                    result = if (board.toMove() == .White) .WhiteWin else .BlackWin;
                } else {
                    result = if (board.toMove() == .White) .BlackWin else .WhiteWin;
                }
                break;
            }
        } else {
            adjudication_counter = 0;
        }

        // Record position if it passes filters
        const in_check = searcher.move_gen.isInCheck(&board, board.toMove());
        const is_capture = best_move.capture == 1;
        const past_opening = ply >= config.skip_early_plies;
        const score_in_range = abs_score >= config.min_score and abs_score <= config.max_score;
        const not_mate_score = abs_score < (eval.mate_score - 256);

        var q_flag = false;

        const q_score = searcher.quiescenceSearch(&board, board.game_state.side_to_move, -eval.mate_score, eval.mate_score);
        const static_score = eval.evaluate(&board, &searcher.move_gen, -eval.mate_score, eval.mate_score, true);

        // If quiescence score is very different from static eval, it's likely a tactical position that we don't want to include
        if (q_score < static_score - 300 or q_score > static_score + 300) {
            q_flag = true;
        }

        if (!q_flag and past_opening and !in_check and !is_capture and score_in_range and not_mate_score) {
            
            var pos: SavedPosition = undefined;
            pos.fen_len = boardToFen(&board, &pos.fen_buf);
            pos.score = @intCast(std.math.clamp(score, -32000, 32000));
            pos.stm = board.toMove();
            pos.result = .Ongoing; // Updated at eog
            pos.piece_bb = board.piece_bb;
            pos.side_to_move = board.game_state.side_to_move;
            game_buf.add(pos);
        }

        mvs.makeMove(&board, best_move);
        ply += 1;
    }

    // If max plies call draw
    if (result == .Ongoing) {
        result = .Draw;
    }

    game_buf.setResult(result);
}

const ThreadContext = struct {
    thread_id: u32,
    config: *const DatagenConfig,
    positions_written: std.atomic.Value(u64),
    games_played: std.atomic.Value(u64),
};

fn workerThread(ctx: *ThreadContext) void {
    var thread_tt = tt.TranspositionTable.init(std.heap.c_allocator, 16) catch |err| {
        std.debug.print("Thread {d}: Failed to allocate TT: {}\n", .{ ctx.thread_id, err });
        return;
    };
    defer thread_tt.deinit(std.heap.c_allocator);

    var searcher = srch.Searcher{
        .timer = std.time.Timer.start() catch return,
        .move_gen = mvs.MoveGen.init(),
        .continuation = std.heap.c_allocator.create([12][64][64][64]i32) catch return,
        .tt_table = &thread_tt,
    };
    searcher.resetHeuristics(true);
    searcher.silent_output = true;
    searcher.thread_id = ctx.thread_id;
    defer searcher.deinit();

    var rng = Rng.init(@as(u64, ctx.thread_id) * 6364136223846793005 +% @as(u64, @intCast(std.time.milliTimestamp())));

    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}.thread{d}", .{ ctx.config.output_path, ctx.thread_id }) catch return;

    const file = std.fs.cwd().createFile(path, .{}) catch |err| {
        std.debug.print("Thread {d}: Failed to create output file: {}\n", .{ ctx.thread_id, err });
        return;
    };
    defer file.close();

    var game_buf = GameBuffer.init();
    var total_positions: u64 = 0;
    var write_buf: [256]u8 = undefined;

    for (0..ctx.config.games_per_thread) |game_num| {
        playSingleGame(&searcher, &rng, ctx.config, &game_buf);

        for (0..game_buf.count) |i| {
            const pos = &game_buf.positions[i];

            // Text format bullet-compatible text: "fen | score | result")
            const fen_str = pos.fen_buf[0..pos.fen_len];
            const result_str = resultToStr(pos.result);
            const wdl_score: i16 = if (pos.stm == .White) pos.score else -pos.score;

            var line_len: usize = 0;
            @memcpy(write_buf[line_len..][0..fen_str.len], fen_str);
            line_len += fen_str.len;
            @memcpy(write_buf[line_len..][0..3], " | ");
            line_len += 3;
            line_len += writeI16(write_buf[line_len..], wdl_score);
            @memcpy(write_buf[line_len..][0..3], " | ");
            line_len += 3;
            @memcpy(write_buf[line_len..][0..result_str.len], result_str);
            line_len += result_str.len;
            write_buf[line_len] = '\n';
            line_len += 1;

            file.writeAll(write_buf[0..line_len]) catch |err| {
                std.debug.print("Thread {d}: Write error: {}\n", .{ ctx.thread_id, err });
                return;
            };
            total_positions += 1;
        }

        ctx.games_played.store(@as(u64, @intCast(game_num + 1)), .release);
        ctx.positions_written.store(total_positions, .release);
    }

    std.debug.print("Thread {d}: Done. {d} games, {d} positions written to {s}\n", .{
        ctx.thread_id,
        ctx.config.games_per_thread,
        total_positions,
        path,
    });
}

pub fn run(config: DatagenConfig) !void {
    std.debug.print("Starting datagen: {d} threads x {d} games, nodes {d}\n", .{
        config.num_threads,
        config.games_per_thread,
        config.num_nodes,
    });
    std.debug.print("Output: {s} (format: {s})\n", .{
        config.output_path,
        @tagName(config.format),
    });
    if (!pawn_tt.pawn_tt_initialized) {
        try pawn_tt.TranspositionTable.initGlobal(16);
    }

    const total_games: u64 = @as(u64, config.num_threads) * @as(u64, config.games_per_thread);
    var timer = try std.time.Timer.start();

    if (config.num_threads == 1) {
        // Single-threaded
        var ctx = ThreadContext{
            .thread_id = 0,
            .config = &config,
            .positions_written = std.atomic.Value(u64).init(0),
            .games_played = std.atomic.Value(u64).init(0),
        };
        workerThread(&ctx);

        const elapsed_s = timer.read() / std.time.ns_per_s;
        const positions = ctx.positions_written.load(.acquire);
        const games = ctx.games_played.load(.acquire);
        printSummary(games, positions, elapsed_s);
    } else {
        // Multi-threaded
        var thread_contexts = try std.heap.c_allocator.alloc(ThreadContext, config.num_threads);
        defer std.heap.c_allocator.free(thread_contexts);
        var thread_handles = try std.heap.c_allocator.alloc(std.Thread, config.num_threads);
        defer std.heap.c_allocator.free(thread_handles);
        for (0..config.num_threads) |i| {
            thread_contexts[i] = .{
                .thread_id = @intCast(i),
                .config = &config,
                .positions_written = std.atomic.Value(u64).init(0),
                .games_played = std.atomic.Value(u64).init(0),
            };
            thread_handles[i] = try std.Thread.spawn(.{}, workerThread, .{&thread_contexts[i]});
        }

        // Progress monitor: poll every 15 seconds until all threads finish
        var all_done = false;
        while (!all_done) {
            std.Thread.sleep(15 * std.time.ns_per_s);

            var games_done: u64 = 0;
            var positions_done: u64 = 0;
            all_done = true;
            for (thread_contexts) |ctx| {
                const g = ctx.games_played.load(.acquire);
                games_done += g;
                positions_done += ctx.positions_written.load(.acquire);
                if (g < config.games_per_thread) all_done = false;
            }

            const elapsed_s = timer.read() / std.time.ns_per_s;
            const elapsed_s_safe = if (elapsed_s == 0) 1 else elapsed_s;
            const pct = (games_done * 100) / total_games;
            const games_per_sec = games_done / elapsed_s_safe;
            const pos_per_sec = positions_done / elapsed_s_safe;
            const remaining_games = total_games -| games_done;
            const eta_s = if (games_per_sec > 0) remaining_games / games_per_sec else 0;

            std.debug.print("[{d}s] {d}/{d} games ({d}%%) | {d} positions | {d} games/s | {d} pos/s | ETA ~{d}s\n", .{
                elapsed_s,
                games_done,
                total_games,
                pct,
                positions_done,
                games_per_sec,
                pos_per_sec,
                eta_s,
            });
        }

        for (thread_handles) |handle| {
            handle.join();
        }

        // Final summary
        var final_games: u64 = 0;
        var final_positions: u64 = 0;
        for (thread_contexts) |ctx| {
            final_games += ctx.games_played.load(.acquire);
            final_positions += ctx.positions_written.load(.acquire);
        }
        const elapsed_s = timer.read() / std.time.ns_per_s;
        printSummary(final_games, final_positions, elapsed_s);

        std.debug.print("Output files: {s}.thread0 .. {s}.thread{d}\n", .{
            config.output_path,
            config.output_path,
            config.num_threads - 1,
        });
        std.debug.print("Merge with: cat {s}.thread* > {s}\n", .{
            config.output_path,
            config.output_path,
        });
    }
}

fn printSummary(games: u64, positions: u64, elapsed_s: u64) void {
    const safe_s = if (elapsed_s == 0) 1 else elapsed_s;
    const mins = elapsed_s / 60;
    const secs = elapsed_s % 60;
    std.debug.print("\n=== Datagen Complete ===\n", .{});
    std.debug.print("Games:     {d}\n", .{games});
    std.debug.print("Positions: {d}\n", .{positions});
    std.debug.print("Time:      {d}m {d}s\n", .{ mins, secs });
    std.debug.print("Speed:     {d} games/s, {d} pos/s\n", .{
        games / safe_s,
        positions / safe_s,
    });
    if (games > 0) {
        std.debug.print("Avg:       {d} positions/game\n", .{positions / games});
    }
}

pub fn parseCommand(args: [][]const u8) DatagenConfig {
    var config = DatagenConfig{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "nodes") and i + 1 < args.len) {
            config.num_nodes = std.fmt.parseInt(u64, args[i + 1], 10) catch 7;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "games") and i + 1 < args.len) {
            config.games_per_thread = std.fmt.parseInt(u32, args[i + 1], 10) catch 5000;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "threads") and i + 1 < args.len) {
            config.num_threads = std.fmt.parseInt(u32, args[i + 1], 10) catch 1;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "output") and i + 1 < args.len) {
            config.output_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "random_plies") and i + 1 < args.len) {
            config.random_plies = std.fmt.parseInt(u32, args[i + 1], 10) catch 8;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "adjudication") and i + 1 < args.len) {
            config.adjudication_score = std.fmt.parseInt(i32, args[i + 1], 10) catch 3000;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "format") and i + 1 < args.len) {
            if (std.mem.eql(u8, args[i + 1], "bullet") or std.mem.eql(u8, args[i + 1], "bin")) {
                config.format = .bullet;
            } else {
                config.format = .text;
            }
            i += 1;
        }
    }

    return config;
}
