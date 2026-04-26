const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const fen_mod = @import("fen");
const srch = @import("search");
const eval = @import("eval");
const tt = @import("transposition");
const pawn_tt = @import("pawn_tt");
const hist = @import("history");

pub const DatagenConfig = struct {
    num_nodes: u64 = 5000,

    // 0 = run forever (interrupt with Ctrl+C)
    games_per_thread: u32 = 0,

    num_threads: u32 = 10,

    // Fallback: random legal moves from startpos when no opening book is provided.
    random_plies: u32 = 10,

    adjudication_score: i32 = 2500,

    adjudication_count: u32 = 8,

    draw_adjudication_score: i32 = 5,

    draw_adjudication_count: u32 = 16,

    max_game_plies: u32 = 512,

    output_path: []const u8 = "datagen.vf",

    // Path to an EPD book
    opening_book_path: ?[]const u8 = null,

    // How many games to buffer in memory before flushing to disk.
    flush_interval: u32 = 64,
};

const GameResult = enum(u8) {
    BlackWin = 0,
    Draw = 1,
    WhiteWin = 2,
    Ongoing = 3,
};

// ── Viriformat binary encoding ──
// Per-game format:
//   32 bytes: starting position header (marlinformat board)
//    4 bytes: per move (u16 move + i16 eval), repeated
//    4 bytes: null terminator

const ViriMove = packed struct {
    move_data: u16,
    eval_score: i16, // white-relative
};

const ViriHeader = packed struct {
    occupancy: u64,
    pieces: u128, // 32 nibbles packed (was [16]u8, but packed structs can't hold arrays)
    ep_and_stm: u8, // bit 7 = side_to_move (1=black), bits 0-6 = ep square (64=none)
    halfmove_clock: u8,
    fullmove_clock: u16,
    score: i16, // unused, set to 0
    outcome: u8, // 0=black win, 1=draw, 2=white win
    extra: u8, // datagen version
};

const max_moves_per_game = 512;

const ViriGame = struct {
    header: ViriHeader,
    moves: [max_moves_per_game]ViriMove,
    move_count: usize,

    fn init() ViriGame {
        return .{
            .header = std.mem.zeroes(ViriHeader),
            .moves = undefined,
            .move_count = 0,
        };
    }

    fn setStartingBoard(self: *ViriGame, board: *const brd.Board) void {
        // Build occupancy
        var occupancy: u64 = 0;
        for (0..brd.num_colors) |ci| {
            for (0..brd.num_pieces) |pi| {
                occupancy |= board.piece_bb[ci][pi];
            }
        }
        self.header.occupancy = occupancy;

        // Pack pieces: iterate set bits of occupancy, encode each piece as a 4-bit nibble
        var pieces: u128 = 0;
        var occ = occupancy;
        var idx: u7 = 0;
        while (occ != 0) {
            const sq: u6 = @intCast(@ctz(occ));
            const piece_nibble: u128 = @intCast(encodePieceAt(board, sq));

            pieces |= piece_nibble << (@as(u7, idx) * 4);
            idx += 1;
            occ &= occ - 1;
        }
        self.header.pieces = pieces;

        // EP square + side to move
        const ep_sq: u8 = if (board.game_state.en_passant_square) |ep| @intCast(ep) else 64;
        const stm_bit: u8 = if (board.game_state.side_to_move == .Black) 0x80 else 0;
        self.header.ep_and_stm = stm_bit | ep_sq;

        self.header.halfmove_clock = @intCast(board.game_state.halfmove_clock);
        self.header.fullmove_clock = @intCast(board.game_state.fullmove_number);
        self.header.score = 0; // unused
        self.header.outcome = 0; // set at end
        self.header.extra = 0; // datagen version
    }

    fn addMove(self: *ViriGame, move_data: mvs.EncodedMove, white_score: i16, board: *const brd.Board) void {
        if (self.move_count >= max_moves_per_game) return;
        self.moves[self.move_count] = .{
            .move_data = encodeViriMove(move_data, board),
            .eval_score = white_score,
        };
        self.move_count += 1;
    }

    fn finish(self: *ViriGame, result: GameResult) void {
        self.header.outcome = @intFromEnum(result);
    }

    fn writeToFile(self: *const ViriGame, file: std.fs.File) !void {
        // Header (32 bytes)
        const header_bytes: *const [32]u8 = @ptrCast(&self.header);
        try file.writeAll(header_bytes);

        // Moves (4 bytes each)
        const move_bytes: [*]const u8 = @ptrCast(&self.moves);
        try file.writeAll(move_bytes[0 .. self.move_count * 4]);

        // Null terminator (4 bytes)
        const null_term = [_]u8{ 0, 0, 0, 0 };
        try file.writeAll(&null_term);
    }
};

fn encodePieceAt(board: *const brd.Board, sq: u6) u8 {
    const mask: u64 = @as(u64, 1) << sq;
    // Viriformat piece encoding (4 bits):
    //   0-5: white pawn..king (piece_type - 1 for 0-indexed, but pawn=0)
    //   8-13: black pawn..king
    //   6: white castling rook, 14: black castling rook
    for (0..brd.num_colors) |ci| {
        for (0..brd.num_pieces) |pi| {
            if (board.piece_bb[ci][pi] & mask != 0) {
                // pi: 0=Pawn, 1=Knight, 2=Bishop, 3=Rook, 4=Queen, 5=King
                var nibble: u8 = @intCast(pi);
                if (ci == 1) nibble += 8; // black pieces

                // Check if this is a castling rook
                if (pi == @intFromEnum(brd.Pieces.Rook)) {
                    if (isCastlingRook(board, sq, @enumFromInt(ci))) {
                        nibble = if (ci == 0) 6 else 14;
                    }
                }
                return nibble;
            }
        }
    }
    return 0; // shouldn't happen if occupancy is correct
}

fn isCastlingRook(board: *const brd.Board, sq: u6, color: brd.Color) bool {
    const gs = board.game_state;
    const cr = gs.castling_rights;
    if (color == .White) {
        if ((cr & @intFromEnum(brd.CastleRights.WhiteQueenside) != 0) and
            @as(usize, sq) == gs.rookSquare(.White, false)) return true;
        if ((cr & @intFromEnum(brd.CastleRights.WhiteKingside) != 0) and
            @as(usize, sq) == gs.rookSquare(.White, true)) return true;
    } else {
        if ((cr & @intFromEnum(brd.CastleRights.BlackQueenside) != 0) and
            @as(usize, sq) == gs.rookSquare(.Black, false)) return true;
        if ((cr & @intFromEnum(brd.CastleRights.BlackKingside) != 0) and
            @as(usize, sq) == gs.rookSquare(.Black, true)) return true;
    }
    return false;
}

fn encodeViriMove(move_data: mvs.EncodedMove, board: *const brd.Board) u16 {
    const from: u16 = @intCast(move_data.start_square);
    var to: u16 = @intCast(move_data.end_square);

    var flag: u16 = 0;
    if (move_data.castling == 1) {
        flag = 0b10_00;
        // Viriformat uses king → rook's *original* square (Chess960 UCI convention).
        // Our EncodedMove stores the king's destination (g-file = KS, c-file = QS).
        // Look up the actual rook square from board state before the move is applied.
        const moving_color = board.game_state.side_to_move;
        const kingside = (move_data.end_square % 8) == 6; // g-file = 6
        to = @intCast(board.game_state.rookSquare(moving_color, kingside));
    } else if (move_data.en_passant == 1) {
        flag = 0b01_00;
    } else if (move_data.promoted_piece != 0) {
        const promo: u16 = switch (move_data.promoted_piece) {
            @intFromEnum(brd.Pieces.Knight) => 0b11_00,
            @intFromEnum(brd.Pieces.Bishop) => 0b11_01,
            @intFromEnum(brd.Pieces.Rook) => 0b11_10,
            @intFromEnum(brd.Pieces.Queen) => 0b11_11,
            else => 0b00_00,
        };
        flag = promo;
    }

    return from | (to << 6) | (flag << 12);
}

const OpeningBook = struct {
    positions: [][]const u8,
    arena: std.heap.ArenaAllocator,

    fn load(allocator: std.mem.Allocator, path: []const u8) !OpeningBook {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();

        const raw = try std.fs.cwd().readFileAlloc(a, path, 256 * 1024 * 1024);

        var list = try std.ArrayList([]const u8).initCapacity(a, 1000000);

        var line_iter = std.mem.splitScalar(u8, raw, '\n');
        while (line_iter.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            const fen = extractFenPart(a, line) catch continue;
            try list.append(a, fen);
        }

        if (list.items.len == 0) return error.EmptyBook;

        std.debug.print("Opening book: loaded {d} positions from {s}\n", .{
            list.items.len,
            path,
        });

        return .{
            .positions = try list.toOwnedSlice(a),
            .arena = arena,
        };
    }

    fn deinit(self: *OpeningBook) void {
        self.arena.deinit();
    }

    fn pick(self: *const OpeningBook, rng: *Rng) []const u8 {
        return self.positions[rng.bounded(self.positions.len)];
    }
};

fn extractFenPart(allocator: std.mem.Allocator, line: []const u8) ![]const u8 {
    var fields: [6][]const u8 = .{""} ** 6;
    var count: usize = 0;

    var iter = std.mem.tokenizeScalar(u8, line, ' ');
    while (iter.next()) |tok| : (count += 1) {
        if (count >= 6) break;
        fields[count] = tok;
    }

    if (count < 4) return error.InvalidEpd;

    if (count >= 6) {
        return std.fmt.allocPrint(allocator, "{s} {s} {s} {s} {s} {s}", .{
            fields[0], fields[1], fields[2], fields[3], fields[4], fields[5],
        });
    } else {
        return std.fmt.allocPrint(allocator, "{s} {s} {s} {s} 0 1", .{
            fields[0], fields[1], fields[2], fields[3],
        });
    }
}

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

pub var stop_signal = std.atomic.Value(bool).init(false);

fn playSingleGame(
    searcher: *srch.Searcher,
    rng: *Rng,
    config: *const DatagenConfig,
    game: *ViriGame,
    book: ?*const OpeningBook,
) bool {
    game.* = ViriGame.init();

    var board = brd.Board.init();

    if (book) |b| {
        const fen = b.pick(rng);
        fen_mod.parseFEN(&board, fen) catch return false;
    } else {
        fen_mod.setupStartingPosition(&board);

        const jiggle: i32 = if (rng.next() % 2 == 0) -1 else 1;
        const actual_plies: u32 = @intCast(@max(0, @as(i32, @intCast(config.random_plies)) + jiggle));

        var random_ok = true;
        for (0..actual_plies) |_| {
            var move_list = searcher.move_gen.generateMoves(&board, false);

            var legal_count: usize = 0;
            var legal_moves: [218]mvs.EncodedMove = undefined;
            for (move_list.items[0..move_list.len]) |move_data| {
                mvs.makeMove(&board, move_data);
                if (!searcher.move_gen.isInCheck(&board, board.justMoved())) {
                    legal_moves[legal_count] = move_data;
                    legal_count += 1;
                }
                mvs.undoMove(&board, move_data);
            }
            if (legal_count == 0) {
                random_ok = false;
                break;
            }
            const pick = rng.bounded(legal_count);
            mvs.makeMove(&board, legal_moves[pick]);
        }

        if (!random_ok) return false;
    }

    if (board.isDraw(0)) return false;

    {
        searcher.soft_max_nodes = 2 * config.num_nodes;
        _ = searcher.iterativeDeepening(&board, null) catch return false;
        const opening_eval = searcher.best_move_score;
        const abs_eval = if (opening_eval < 0) -opening_eval else opening_eval;
        if (abs_eval > 400) return false;
    }

    // Viriformat recording starts here — the opening phase (book lookup or
    // random plies) is complete and no moves have been added to `game` yet.
    // Only moves played by the search loop below are ever passed to
    // game.addMove, so random opening moves can never appear in the output.
    game.setStartingBoard(&board);

    var result: GameResult = .Ongoing;
    var ply: u32 = 0;
    var win_adj_counter: u32 = 0;
    var draw_adj_counter: u32 = 0;

    while (result == .Ongoing and ply < config.max_game_plies) {
        if (stop_signal.load(.acquire)) break;

        if (board.isDraw(0)) {
            result = .Draw;
            break;
        }

        var move_list = searcher.move_gen.generateMoves(&board, false);
        var has_legal = false;
        for (move_list.items[0..move_list.len]) |move_data| {
            mvs.makeMove(&board, move_data);
            if (!searcher.move_gen.isInCheck(&board, board.justMoved())) {
                has_legal = true;
            }
            mvs.undoMove(&board, move_data);
            if (has_legal) break;
        }

        if (!has_legal) {
            const in_check = searcher.move_gen.isInCheck(&board, board.toMove());
            if (in_check) {
                result = if (board.toMove() == .White) .BlackWin else .WhiteWin;
            } else {
                result = .Draw;
            }
            break;
        }

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

        // Node jitter: +-20% of num_nodes to maintain positional variety
        const jitter_range: i64 = @intCast(config.num_nodes / 5);
        const random_offset: i64 = @as(i64, @intCast(rng.next() % @as(u64, @intCast(jitter_range * 2)))) - jitter_range;
        const node_count: u64 = @intCast(@max(1000, @as(i64, @intCast(config.num_nodes)) + random_offset));

        searcher.soft_max_nodes = node_count;
        const search_result = searcher.iterativeDeepening(&board, null) catch break;

        const score = search_result.score;
        const best_move = search_result.move;

        if (best_move.toU32() == 0) break;

        // White-relative score for viriformat
        const white_score: i16 = blk: {
            const clamped = std.math.clamp(score, -32000, 32000);
            break :blk if (board.toMove() == .White) @intCast(clamped) else @intCast(-clamped);
        };

        const abs_score = if (score < 0) -score else score;
        if (abs_score >= config.adjudication_score) {
            win_adj_counter += 1;
            if (win_adj_counter >= config.adjudication_count) {
                if (score > 0) {
                    result = if (board.toMove() == .White) .WhiteWin else .BlackWin;
                } else {
                    result = if (board.toMove() == .White) .BlackWin else .WhiteWin;
                }
                break;
            }
        } else {
            win_adj_counter = 0;
        }

        if (abs_score <= config.draw_adjudication_score) {
            draw_adj_counter += 1;
            if (draw_adj_counter >= config.draw_adjudication_count) {
                result = .Draw;
                break;
            }
        } else {
            draw_adj_counter = 0;
        }

        // Record the position. Bullet trainer handles all per-position
        // filtering (in-check, post-capture, score range, early ply skipping).
        game.addMove(best_move, white_score, &board);

        mvs.makeMove(&board, best_move);
        ply += 1;
    }

    if (result == .Ongoing) result = .Draw;

    game.finish(result);
    return true;
}

const ThreadContext = struct {
    thread_id: u32,
    config: *const DatagenConfig,
    positions_written: std.atomic.Value(u64),
    games_played: std.atomic.Value(u64),
    opening_book: ?*const OpeningBook,
};

fn workerThread(ctx: *ThreadContext) void {
    var thread_tt = tt.TranspositionTable.init(std.heap.c_allocator, 16) catch |err| {
        std.debug.print("Thread {d}: Failed to allocate TT: {}\n", .{ ctx.thread_id, err });
        return;
    };
    defer thread_tt.deinit(std.heap.c_allocator);

    var searcher = srch.Searcher{
        .timer = std.time.Timer.start() catch return,
        .move_gen = std.heap.c_allocator.create(mvs.MoveGen) catch return,
        .continuation = std.heap.c_allocator.create([12][64][64][64]i32) catch return,
        .tt_table = &thread_tt,
    };
    searcher.move_gen.init();
    hist.resetHeuristics(&searcher, true);
    searcher.silent_output = true;
    searcher.thread_id = ctx.thread_id;
    defer searcher.deinit();

    var rng = Rng.init(@as(u64, ctx.thread_id) * 6364136223846793005 +% @as(u64, @intCast(std.time.milliTimestamp())));

    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}.thread{d}", .{ ctx.config.output_path, ctx.thread_id }) catch return;

    const file = std.fs.cwd().openFile(path, .{ .mode = .write_only }) catch
        std.fs.cwd().createFile(path, .{}) catch |err| {
        std.debug.print("Thread {d}: Failed to open output file: {}\n", .{ ctx.thread_id, err });
        return;
    };
    file.seekFromEnd(0) catch {};
    defer file.close();

    const buf_capacity = @as(usize, ctx.config.flush_interval) + 16;
    var game_buffer = std.heap.c_allocator.alloc(ViriGame, buf_capacity) catch |err| {
        std.debug.print("Thread {d}: Failed to allocate game buffer: {}\n", .{ ctx.thread_id, err });
        return;
    };
    defer std.heap.c_allocator.free(game_buffer);

    var game = ViriGame.init();
    var total_games: u64 = 0;
    var total_positions: u64 = 0;
    var games_since_flush: u32 = 0;
    var buf_count: usize = 0;

    const unlimited = ctx.config.games_per_thread == 0;

    while (!stop_signal.load(.acquire)) {
        if (!unlimited and total_games >= ctx.config.games_per_thread) break;

        searcher.tt_table.reset();

        const ok = playSingleGame(&searcher, &rng, ctx.config, &game, ctx.opening_book);
        if (!ok) continue;

        game_buffer[buf_count] = game;
        buf_count += 1;

        total_games += 1;
        total_positions += game.move_count;
        games_since_flush += 1;

        if (games_since_flush >= ctx.config.flush_interval) {
            for (0..buf_count) |i| {
                game_buffer[i].writeToFile(file) catch |err| {
                    std.debug.print("Thread {d}: Write error: {}\n", .{ ctx.thread_id, err });
                    return;
                };
            }
            buf_count = 0;
            games_since_flush = 0;
        }

        ctx.games_played.store(total_games, .release);
        ctx.positions_written.store(total_positions, .release);
    }

    for (0..buf_count) |i| {
        game_buffer[i].writeToFile(file) catch {};
    }

    std.debug.print("Thread {d}: Done. {d} games, {d} positions written to {s}\n", .{
        ctx.thread_id,
        total_games,
        total_positions,
        path,
    });
}

const ExistingData = struct {
    games: u64,
    positions: u64,
};

fn countExistingViriData(path: []const u8, num_threads: u32) ExistingData {
    var total = ExistingData{ .games = 0, .positions = 0 };
    var path_buf: [256]u8 = undefined;

    for (0..num_threads) |i| {
        const thread_path = std.fmt.bufPrint(&path_buf, "{s}.thread{d}", .{ path, i }) catch continue;
        const data = countSingleViriFile(thread_path);
        total.games += data.games;
        total.positions += data.positions;
    }
    return total;
}

fn countSingleViriFile(path: []const u8) ExistingData {
    var result = ExistingData{ .games = 0, .positions = 0 };
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch return result;
    defer file.close();

    // Read through the file: 32-byte header, then 4-byte entries until null terminator
    while (true) {
        var header_buf: [32]u8 = undefined;
        const header_read = file.readAll(&header_buf) catch return result;
        if (header_read < 32) break;

        result.games += 1;

        while (true) {
            var move_buf: [4]u8 = undefined;
            const move_read = file.readAll(&move_buf) catch return result;
            if (move_read < 4) return result;

            if (move_buf[0] == 0 and move_buf[1] == 0 and move_buf[2] == 0 and move_buf[3] == 0) break;
            result.positions += 1;
        }
    }
    return result;
}

pub fn run(config: DatagenConfig) !void {
    const unlimited = config.games_per_thread == 0;
    std.debug.print("Starting datagen: {d} threads", .{config.num_threads});
    if (unlimited) {
        std.debug.print(" (unlimited games, Ctrl+C to stop)\n", .{});
    } else {
        std.debug.print(" x {d} games, nodes {d}\n", .{ config.games_per_thread, config.num_nodes });
    }
    std.debug.print("Output: {s} (viriformat, append mode)\n", .{config.output_path});

    // Load opening book if a path was provided
    var maybe_book: ?OpeningBook = null;
    defer if (maybe_book) |*b| b.deinit();

    if (config.opening_book_path) |book_path| {
        maybe_book = OpeningBook.load(std.heap.c_allocator, book_path) catch |err| blk: {
            std.debug.print("Warning: failed to load opening book '{s}': {} — falling back to random plies\n", .{ book_path, err });
            break :blk null;
        };
    } else {
        std.debug.print("No opening book specified — using {d} random plies\n", .{config.random_plies});
    }

    const book_ptr: ?*const OpeningBook = if (maybe_book != null) &maybe_book.? else null;

    // Scan existing files for cumulative tracking
    const existing = countExistingViriData(config.output_path, config.num_threads);
    if (existing.games > 0) {
        std.debug.print("Resuming: found {d} existing games, {d} existing positions\n", .{
            existing.games,
            existing.positions,
        });
    }

    if (!pawn_tt.pawn_tt_initialized) {
        try pawn_tt.TranspositionTable.initGlobal(16);
    }

    stop_signal.store(false, .release);
    var timer = try std.time.Timer.start();

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
            .opening_book = book_ptr,
        };
        thread_handles[i] = try std.Thread.spawn(.{}, workerThread, .{&thread_contexts[i]});
    }

    // Progress monitor
    var all_done = false;
    while (!all_done) {
        std.Thread.sleep(15 * std.time.ns_per_s);

        var session_games: u64 = 0;
        var session_positions: u64 = 0;
        all_done = true;
        for (thread_contexts) |ctx| {
            session_games += ctx.games_played.load(.acquire);
            session_positions += ctx.positions_written.load(.acquire);
            if (unlimited) {
                if (!stop_signal.load(.acquire)) all_done = false;
            } else {
                if (ctx.games_played.load(.acquire) < config.games_per_thread) all_done = false;
            }
        }

        const total_games = existing.games + session_games;
        const total_positions = existing.positions + session_positions;

        const elapsed_s = timer.read() / std.time.ns_per_s;
        const elapsed_s_safe = if (elapsed_s == 0) 1 else elapsed_s;
        const games_per_sec = session_games / elapsed_s_safe;
        const pos_per_sec = session_positions / elapsed_s_safe;
        const pos_per_hour = pos_per_sec * 3600;

        std.debug.print("[{d}s] session: {d} games, {d} games/s, {d} positions, {d} pos/s ({d} pos/hr) | total: {d} games, {d} positions ({d}.{d}B), {d} pos/s\n", .{
            elapsed_s,
            session_games,
            games_per_sec,
            session_positions,
            pos_per_sec,
            pos_per_hour,
            total_games,
            total_positions,
            total_positions / 1_000_000_000,
            (total_positions % 1_000_000_000) / 100_000_000,
            pos_per_sec,
        });

        if (stop_signal.load(.acquire)) all_done = true;
    }

    for (thread_handles) |handle| {
        handle.join();
    }

    // Final summary
    var final_session_games: u64 = 0;
    var final_session_positions: u64 = 0;
    for (thread_contexts) |ctx| {
        final_session_games += ctx.games_played.load(.acquire);
        final_session_positions += ctx.positions_written.load(.acquire);
    }
    const elapsed_s = timer.read() / std.time.ns_per_s;

    const final_total_games = existing.games + final_session_games;
    const final_total_positions = existing.positions + final_session_positions;

    printSummary(final_session_games, final_session_positions, final_total_games, final_total_positions, elapsed_s);

    if (config.num_threads > 1) {
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

fn printSummary(session_games: u64, session_positions: u64, total_games: u64, total_positions: u64, elapsed_s: u64) void {
    const safe_s = if (elapsed_s == 0) 1 else elapsed_s;
    const mins = elapsed_s / 60;
    const secs = elapsed_s % 60;
    std.debug.print("\n=== Datagen Complete ===\n", .{});
    std.debug.print("Session:   {d} games, {d} positions\n", .{ session_games, session_positions });
    std.debug.print("Total:     {d} games, {d} positions ({d}.{d}B)\n", .{
        total_games,
        total_positions,
        total_positions / 1_000_000_000,
        (total_positions % 1_000_000_000) / 100_000_000,
    });
    std.debug.print("Time:      {d}m {d}s\n", .{ mins, secs });
    std.debug.print("Speed:     {d} games/s, {d} pos/s\n", .{
        session_games / safe_s,
        session_positions / safe_s,
    });
    if (session_games > 0) {
        std.debug.print("Avg:       {d} positions/game\n", .{ session_positions / session_games });
    }
}

pub fn parseCommand(args: [][]const u8) DatagenConfig {
    var config = DatagenConfig{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "nodes") and i + 1 < args.len) {
            config.num_nodes = std.fmt.parseInt(u64, args[i + 1], 10) catch 10000;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "games") and i + 1 < args.len) {
            config.games_per_thread = std.fmt.parseInt(u32, args[i + 1], 10) catch 0;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "threads") and i + 1 < args.len) {
            config.num_threads = std.fmt.parseInt(u32, args[i + 1], 10) catch 1;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "output") and i + 1 < args.len) {
            config.output_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "book") and i + 1 < args.len) {
            config.opening_book_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "random_plies") and i + 1 < args.len) {
            config.random_plies = std.fmt.parseInt(u32, args[i + 1], 10) catch 8;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "adjudication") and i + 1 < args.len) {
            config.adjudication_score = std.fmt.parseInt(i32, args[i + 1], 10) catch 2500;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "flush") and i + 1 < args.len) {
            config.flush_interval = std.fmt.parseInt(u32, args[i + 1], 10) catch 100;
            i += 1;
        }
    }

    return config;
}
