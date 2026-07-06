const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const fen = @import("fen");
const srch = @import("search");
const tt = @import("transposition");
const eval = @import("eval");
const pawn_tt = @import("pawn_tt");
const datagen = @import("datagen");
const nnue = @import("nnue");
const perft = @import("perft");
const tp = @import("tunable_parameters");
const tb = @import("tb");

var move_overhead: u64 = 15;

pub const EXPECTED_BENCH_NODES: u64 = 4232113;

pub const SearchLimits = struct {
    wtime: ?u64 = null,
    btime: ?u64 = null,
    winc: ?u64 = null,
    binc: ?u64 = null,
    movestogo: ?u32 = null,
    depth: ?u32 = null,
    nodes: ?u64 = null,
    mate: ?u32 = null,
    movetime: ?u64 = null,
    infinite: bool = false,
    ponder: bool = false,
    searchmoves: ?[]mvs.EncodedMove = null,
};

pub const UciOption = struct {
    name: []const u8,
    type: enum { check, spin, combo, button, string },
    default: ?[]const u8 = null,
    min: ?i32 = null,
    max: ?i32 = null,
    vars: ?[][]const u8 = null,
};

const SearchContext = struct {
    protocol: *UciProtocol,
    board: *brd.Board,
    max_depth: ?u8 = null,
    root_color: brd.Color = .White,
};

fn searchThreadFn(ctx: *SearchContext) void {
    const protocol = ctx.protocol;
    const root_color = ctx.root_color;

    defer {
        // Destroy the context using the engine's internal allocator
        protocol.allocator.destroy(ctx.board);
        protocol.allocator.destroy(ctx);
        @atomicStore(bool, &protocol.is_searching, false, .release);
    }

    const result = protocol.searcher.parallelIterativeDeepening(
        ctx.board,
        ctx.max_depth,
        ctx.protocol.threads,
    ) catch |err| {
        std.debug.print("Search thread error: {}\n", .{err});
        return;
    };

    while (@atomicLoad(bool, &protocol.is_pondering, .acquire)) {
        std.Thread.sleep(1_000_000); // 1ms
    }

    outputBestMove(protocol, result, root_color) catch |err| {
        std.debug.print("Output error in search thread: {}\n", .{err});
    };
}

fn moveToUciStr(protocol: *UciProtocol, move: mvs.EncodedMove, color: brd.Color) ![]const u8 {
    if (protocol.chess960 and move.castling == 1) {
        const kingside = (move.end_square % 8) == 6; // g-file = kingside
        const rook_sq = protocol.board.game_state.rookSquare(color, kingside);
        const start_file: u8 = move.start_square % 8;
        const start_rank: u8 = @as(u8, @intCast(move.start_square / 8)) + 1;
        const rook_file: u8 = @as(u8, @intCast(rook_sq % 8));
        const rook_rank: u8 = @as(u8, @intCast(rook_sq / 8)) + 1;
        return std.fmt.allocPrint(protocol.allocator, "{c}{d}{c}{d}", .{
            'a' + start_file, start_rank,
            'a' + rook_file,  rook_rank,
        });
    }
    return move.uciToString(protocol.allocator);
}

fn outputBestMove(protocol: *UciProtocol, result: srch.SearchResult, root_color: brd.Color) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const move_str = try moveToUciStr(protocol, result.move, root_color);
    defer protocol.allocator.free(move_str);

    if (result.pv_length >= 2) {
        const ponder_str = try result.pv[1].uciToString(protocol.allocator);
        defer protocol.allocator.free(ponder_str);
        try stdout.print("bestmove {s} ponder {s}\n", .{ move_str, ponder_str });
    } else {
        try stdout.print("bestmove {s}\n", .{move_str});
    }

    try stdout.flush();
}

pub const UciProtocol = struct {
    board: brd.Board,
    allocator: std.mem.Allocator,
    debug_mode: bool = false,
    should_quit: bool = false,
    is_searching: bool = false,
    chess960: bool = false,
    hash_size_mb: u32 = 256,
    threads: usize = 1,
    searcher: *srch.Searcher,
    tt_table: tt.TranspositionTable = undefined,

    search_thread: ?std.Thread = null,
    is_pondering: bool = false,
    ponder_limits: SearchLimits = .{},
    ponder_side: brd.Color = .White,

    pub fn init(a: std.mem.Allocator) !*UciProtocol {
        const protocol = try a.create(UciProtocol);
        errdefer a.destroy(protocol);

        @memset(std.mem.asBytes(protocol), 0);

        protocol.allocator = a;
        protocol.board.game_state = brd.GameState.init();
        protocol.hash_size_mb = 64;

        srch.search_helpers = .empty;
        srch.threads = .empty;

        const searcher_ptr = try a.create(srch.Searcher);
        errdefer a.destroy(searcher_ptr);

        searcher_ptr.* = srch.Searcher{};
        searcher_ptr.initInPlace();
        errdefer searcher_ptr.deinit();

        protocol.searcher = searcher_ptr;

        nnue.initWeights();

        protocol.tt_table = try tt.TranspositionTable.init(a, protocol.hash_size_mb);
        searcher_ptr.tt_table = &protocol.tt_table;

        return protocol;
    }

    pub fn deinit(self: *UciProtocol) void {
        self.stopSearch();
        srch.Searcher.deinitThreading();
        tb.deinit();
        self.searcher.deinit();
        self.allocator.destroy(self.searcher);
        self.tt_table.deinit(self.allocator);
        const a = self.allocator;
        a.destroy(self);
    }

    pub fn receiveCommand(self: *UciProtocol, command: []const u8) !void {
        var tokenizer = std.mem.tokenizeScalar(u8, command, ' ');
        var parts = try std.ArrayList([]const u8).initCapacity(self.allocator, 32);
        defer parts.deinit(self.allocator);

        while (tokenizer.next()) |token| {
            try parts.append(self.allocator, token);
        }
        if (parts.items.len == 0) return;

        const commandName = parts.items[0];
        const args = parts.items[1..];

        if (std.mem.eql(u8, commandName, "uci")) {
            try self.handleUci();
        } else if (std.mem.eql(u8, commandName, "isready")) {
            try respond("readyok");
        } else if (std.mem.eql(u8, commandName, "debug")) {
            if (args.len > 0 and std.mem.eql(u8, args[0], "on")) {
                self.debug_mode = true;
            } else if (args.len > 0 and std.mem.eql(u8, args[0], "off")) {
                self.debug_mode = false;
            } else {
                try fen.debugPrintBoard(&self.board);
            }
        } else if (std.mem.eql(u8, commandName, "ucinewgame")) {
            try self.newGame();
        } else if (std.mem.eql(u8, commandName, "position")) {
            try self.handlePosition(args);
        } else if (std.mem.eql(u8, commandName, "go")) {
            try self.handleGo(args);
        } else if (std.mem.eql(u8, commandName, "stop")) {
            self.stopSearch();
        } else if (std.mem.eql(u8, commandName, "ponderhit")) {
            self.handlePonderHit();
        } else if (std.mem.eql(u8, commandName, "quit")) {
            self.stopSearch();
            self.should_quit = true;
        } else if (std.mem.eql(u8, commandName, "setoption")) {
            try self.handleSetOption(args);
        } else if (std.mem.eql(u8, commandName, "register")) {
            try respond("registration checking");
        } else if (std.mem.eql(u8, commandName, "d")) {
            try self.printBoard();
        } else if (std.mem.eql(u8, commandName, "datagen")) {
            try self.handleDatagen(args);
        } else if (std.mem.eql(u8, commandName, "eval")) {
            const eval_score = self.board.evaluateNNUE();
            try respond(try std.fmt.allocPrint(self.allocator, "Evaluation: {d}", .{eval_score}));
        } else if (std.mem.eql(u8, commandName, "hce")) {
            const hce_score = eval.evaluate(&self.board, self.searcher.move_gen, -eval.mate_score, eval.mate_score, true);
            try respond(try std.fmt.allocPrint(self.allocator, "HCE Evaluation: {d}", .{hce_score}));
        } else if (std.mem.eql(u8, commandName, "perft")) {
            try self.handlePerft(args);
        } else if (std.mem.eql(u8, commandName, "bench")) {
            try self.handleBench(args);
        } else if (std.mem.eql(u8, commandName, "bench-expected")) {
            try respond(try std.fmt.allocPrint(self.allocator, "{d}", .{EXPECTED_BENCH_NODES}));
        } else {
            if (self.debug_mode) {
                try respond("Unknown command");
            }
        }
    }

    fn stopSearch(self: *UciProtocol) void {
        self.searcher.stop = true;
        self.searcher.force_think = false;
        tt.stop_signal.store(true, .release);
        srch.Searcher.stopAllThreads();

        @atomicStore(bool, &self.is_pondering, false, .release);

        if (self.search_thread) |thread| {
            thread.join();
            self.search_thread = null;
        }

        self.is_searching = false;
    }

    fn handlePonderHit(self: *UciProtocol) void {
        if (!@atomicLoad(bool, &self.is_pondering, .acquire)) return;

        @atomicStore(bool, &self.searcher.force_think, false, .release);

        for (srch.search_helpers.items) |helper| {
            @atomicStore(bool, &helper.force_think, false, .release);
        }

        @atomicStore(bool, &self.is_pondering, false, .release);
    }

    fn handleGo(self: *UciProtocol, args: [][]const u8) !void {
        if (self.search_thread != null) {
            self.stopSearch();
        }

        var limits = SearchLimits{};
        var i: usize = 0;

        while (i < args.len) {
            const arg = args[i];

            if (std.mem.eql(u8, arg, "wtime") and i + 1 < args.len) {
                limits.wtime = try std.fmt.parseInt(u64, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "btime") and i + 1 < args.len) {
                limits.btime = try std.fmt.parseInt(u64, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "winc") and i + 1 < args.len) {
                limits.winc = try std.fmt.parseInt(u64, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "binc") and i + 1 < args.len) {
                limits.binc = try std.fmt.parseInt(u64, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "movestogo") and i + 1 < args.len) {
                limits.movestogo = try std.fmt.parseInt(u32, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "depth") and i + 1 < args.len) {
                limits.depth = try std.fmt.parseInt(u32, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "nodes") and i + 1 < args.len) {
                limits.nodes = try std.fmt.parseInt(u64, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "mate") and i + 1 < args.len) {
                limits.mate = try std.fmt.parseInt(u32, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "movetime") and i + 1 < args.len) {
                limits.movetime = try std.fmt.parseInt(u64, args[i + 1], 10);
                i += 2;
            } else if (std.mem.eql(u8, arg, "infinite")) {
                limits.infinite = true;
                i += 1;
            } else if (std.mem.eql(u8, arg, "ponder")) {
                limits.ponder = true;
                i += 1;
            } else if (std.mem.eql(u8, arg, "searchmoves")) {
                i += 1;
            } else {
                i += 1;
            }
        }

        self.searcher.stop = false;
        self.searcher.time_stop = false;
        tt.stop_signal.store(false, .release);

        if (limits.ponder) {
            var real_limits = limits;
            real_limits.ponder = false;
            const time_alloc = self.calculateTimeAllocation(&real_limits, self.board.toMove());
            self.searcher.max_ms = time_alloc.max_ms;
            self.searcher.ideal_ms = time_alloc.ideal_ms;
            self.searcher.force_think = true;
            self.ponder_limits = limits;
            self.ponder_side = self.board.toMove();
            @atomicStore(bool, &self.is_pondering, true, .release);
        } else {
            self.searcher.force_think = false;
            const time_alloc = self.calculateTimeAllocation(&limits, self.board.toMove());
            self.searcher.max_ms = time_alloc.max_ms;
            self.searcher.ideal_ms = time_alloc.ideal_ms;
            @atomicStore(bool, &self.is_pondering, false, .release);
        }

        // try srch.search_helpers.resize(self.allocator, self.threads);
        // try srch.threads.resize(self.allocator, self.threads);

        self.is_searching = true;

        const ctx = try self.allocator.create(SearchContext);

        ctx.protocol = self;
        ctx.max_depth = if (limits.depth) |d| @as(u8, @intCast(@min(d, 255))) else null;
        ctx.root_color = self.board.toMove();

        ctx.board = try self.allocator.create(brd.Board);
        ctx.board.copyFrom(&self.board);

        const spawn_config = std.Thread.SpawnConfig{
            .stack_size = 8 * 1024 * 1024,
        };

        self.search_thread = try std.Thread.spawn(spawn_config, searchThreadFn, .{ctx});
    }

    fn handleUci(self: *UciProtocol) !void {
        try respond("id name Ursus 1.0 " ++ @tagName(nnue.TARGET));
        try respond("id author Zander");

        try respond("option name Ponder type check default false");
        try respond("option name Hash type spin default 256 min 1 max 16384");
        try respond("option name Threads type spin default 1 min 1 max 1024");
        try respond("option name UCI_Chess960 type check default false");
        try respond("option name SyzygyPath type string default <empty>");
        try respond("option name SyzygyProbeDepth type spin default 1 min 1 max 100");
        try respond("option name Overhead type spin default 15 min 0 max 1000");
        try respond("option name Clear Hash type button");

        // Tunable search parameters.
        // try respond("option name aspiration_window type spin default 22 min 5 max 100");
        // try respond("option name rfp_mul type spin default 51 min 20 max 150");
        // try respond("option name rfp_improve type spin default 55 min 20 max 150");
        // try respond("option name nmp_improve type spin default 29 min 0 max 200");
        // try respond("option name nmp_base type spin default 4 min 1 max 10");
        // try respond("option name nmp_depth_div type spin default 3 min 1 max 10");
        // try respond("option name nmp_beta_div type spin default 150 min 50 max 400");
        // try respond("option name razoring_base type spin default 299 min 100 max 600");
        // try respond("option name razoring_mul type spin default 73 min 20 max 200");
        try respond("option name lmp_improve type spin default 219 min 50 max 500");
        try respond("option name lmp_base type spin default 503 min 100 max 1000");
        try respond("option name lmp_mul type spin default 185 min 50 max 500");
        try respond("option name futility_mul type spin default 157 min 50 max 400");
        // try respond("option name q_see_min type spin default -150 min -500 max 0");
        // try respond("option name q_see_margin type spin default -41 min -200 max 0");
        // try respond("option name q_delta_margin type spin default 201 min 50 max 500");
        try respond("option name lmr_base type spin default 75 min 25 max 150");
        try respond("option name lmr_div type spin default 225 min 100 max 400");
        try respond("option name lmr_noisy_base type spin default -15 min -100 max 100");
        try respond("option name lmr_noisy_div type spin default 315 min 100 max 500");

        // try respond("option name lmr_pv_min type spin default 4 min 1 max 10");
        // try respond("option name lmr_non_pv_min type spin default 2 min 1 max 10");
        // try respond("option name se_double_threshold type spin default 35 min 0 max 200");
        // try respond("option name se_triple_threshold type spin default 40 min 0 max 200");
        try respond("option name history_div type spin default 8252 min 1024 max 32768");
        // try respond("option name corr_div_bm type spin default 10 min 1 max 50");
        // try respond("option name corr_div_nobm type spin default 8 min 1 max 50");
        // try respond("option name corr_np_update_weight type spin default 178 min 32 max 512");
        // try respond("option name corr_pawn_read_weight type spin default 188 min 32 max 512");
        // try respond("option name corr_np_read_weight type spin default 122 min 32 max 512");
        // try respond("option name corr_major_read_weight type spin default 102 min 32 max 512");
        // try respond("option name corr_minor_read_weight type spin default 111 min 32 max 512");
        // try respond("option name corr_read_divisor type spin default 127393 min 16384 max 524288");
        // try respond("option name probcut_margin type spin default 250 min 0 max 1000");
        // try respond("option name probcut_improve type spin default 1050 min 0 max 2000");
        // try respond("option name probcut_min_see type spin default 150 min 0 max 500");

        try self.newGame();

        try respond("uciok");

        srch.quiet_lmr = srch.initQuietLMR();
        srch.noisy_lmr = srch.initNoisyLMR();
    }

    fn handleSetOption(self: *UciProtocol, args: [][]const u8) !void {
        if (args.len < 2 or !std.mem.eql(u8, args[0], "name")) {
            if (self.debug_mode) {
                try respond("Error: setoption requires 'name' keyword");
            }
            return;
        }

        var name_end: usize = 1;
        while (name_end < args.len and !std.mem.eql(u8, args[name_end], "value")) {
            name_end += 1;
        }

        const option_name = try std.mem.join(self.allocator, " ", args[1..name_end]);
        defer self.allocator.free(option_name);

        if (std.mem.eql(u8, option_name, "Hash")) {
            if (args.len < name_end + 2) {
                if (self.debug_mode) {
                    try respond("Error: Hash option requires a value");
                }
                return;
            }
            const new_size_mb = try std.fmt.parseInt(u32, args[name_end + 1], 10);
            if (new_size_mb == self.hash_size_mb) {
                return; // No change needed
            }
            self.hash_size_mb = new_size_mb;

            self.tt_table.deinit(self.allocator);
            self.tt_table = try tt.TranspositionTable.init(self.allocator, self.hash_size_mb);
            self.searcher.tt_table = &self.tt_table;
        } else if (std.mem.eql(u8, option_name, "Clear Hash")) {
            self.tt_table.reset();
            if (pawn_tt.pawn_tt_initialized) {
                pawn_tt.pawn_tt.reset();
            }
        } else if (std.mem.eql(u8, option_name, "Ponder")) {
            // TODO: ?
        } else if (std.mem.eql(u8, option_name, "UCI_Chess960")) {
            if (args.len >= name_end + 2) {
                self.chess960 = std.mem.eql(u8, args[name_end + 1], "true");
                self.searcher.chess960 = self.chess960;
            }
        } else if (std.mem.eql(u8, option_name, "Threads")) {
            if (args.len < name_end + 2) {
                if (self.debug_mode) {
                    try respond("Error: Threads option requires a value");
                }
                return;
            }
            const new_thread_count = try std.fmt.parseInt(usize, args[name_end + 1], 10);
            self.threads = new_thread_count;
        } else if (std.mem.eql(u8, option_name, "SyzygyPath")) {
            self.stopSearch();

            if (args.len < name_end + 2) {
                return;
            }
            const path = try std.mem.join(self.allocator, " ", args[name_end + 1 ..]);
            defer self.allocator.free(path);
            const path_z = try self.allocator.dupeZ(u8, path);
            defer self.allocator.free(path_z);

            tb.deinit();
            if (path.len == 0 or std.mem.eql(u8, path, "<empty>")) {
            } else if (!tb.init(path_z)) {
                if (self.debug_mode) try respond("info string Syzygy: failed to load tablebases");
            } else {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "info string Syzygy tablebases loaded, max {d} pieces",
                    .{tb.largest()},
                );
                defer self.allocator.free(msg);
                try respond(msg);
            }
        } else if (std.mem.eql(u8, option_name, "SyzygyProbeDepth")) {
            if (args.len >= name_end + 2) {
                tp.tb_probe_depth = try std.fmt.parseInt(usize, args[name_end + 1], 10);
            }
        } else if (std.mem.eql(u8, option_name, "Overhead")) {
            if (args.len >= name_end + 2) {
                move_overhead = try std.fmt.parseInt(u64, args[name_end + 1], 10);
            }

        // } 
        // else if (std.mem.eql(u8, option_name, "aspiration_window")) {
        //     if (args.len >= name_end + 2) {
        //         tp.aspiration_window = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 5, 100);
        //     }
        // } else if (std.mem.eql(u8, option_name, "rfp_mul")) {
        //     if (args.len >= name_end + 2) {
        //         tp.rfp_mul = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 20, 150);
        //     }
        // } else if (std.mem.eql(u8, option_name, "rfp_improve")) {
        //     if (args.len >= name_end + 2) {
        //         tp.rfp_improve = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 20, 150);
        //     }
        // } else if (std.mem.eql(u8, option_name, "nmp_improve")) {
        //     if (args.len >= name_end + 2) {
        //         tp.nmp_improve = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 0, 200);
        //     }
        // } else if (std.mem.eql(u8, option_name, "nmp_base")) {
        //     if (args.len >= name_end + 2) {
        //         tp.nmp_base = @intCast(std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 1, 10));
        //     }
        // } else if (std.mem.eql(u8, option_name, "nmp_depth_div")) {
        //     if (args.len >= name_end + 2) {
        //         tp.nmp_depth_div = @intCast(std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 1, 10));
        //     }
        // } else if (std.mem.eql(u8, option_name, "nmp_beta_div")) {
        //     if (args.len >= name_end + 2) {
        //         tp.nmp_beta_div = @intCast(std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 50, 400));
        //     }
        // } else if (std.mem.eql(u8, option_name, "razoring_base")) {
        //     if (args.len >= name_end + 2) {
        //         tp.razoring_base = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 100, 600);
        //     }
        // } else if (std.mem.eql(u8, option_name, "razoring_mul")) {
        //     if (args.len >= name_end + 2) {
        //         tp.razoring_mul = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 20, 200);
        //     }
        } else if (std.mem.eql(u8, option_name, "lmp_improve")) {
            if (args.len >= name_end + 2) {
                tp.lmp_improve = @intCast(std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 50, 500));
            }
        } else if (std.mem.eql(u8, option_name, "lmp_base")) {
            if (args.len >= name_end + 2) {
                tp.lmp_base = @intCast(std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 100, 1000));
            }
        } else if (std.mem.eql(u8, option_name, "lmp_mul")) {
            if (args.len >= name_end + 2) {
                tp.lmp_mul = @intCast(std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 50, 500));
            }
        } else if (std.mem.eql(u8, option_name, "futility_mul")) {
            if (args.len >= name_end + 2) {
                tp.futility_mul = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 50, 400);
            }
        // } else if (std.mem.eql(u8, option_name, "q_see_min")) {
        //     if (args.len >= name_end + 2) {
        //         tp.q_see_min = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), -500, 0);
        //     }
        // } else if (std.mem.eql(u8, option_name, "q_see_margin")) {
        //     if (args.len >= name_end + 2) {
        //         tp.q_see_margin = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), -200, 0);
        //     }
        // } else if (std.mem.eql(u8, option_name, "q_delta_margin")) {
        //     if (args.len >= name_end + 2) {
        //         tp.q_delta_margin = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 50, 500);
        //     }
        } else if (std.mem.eql(u8, option_name, "lmr_base")) {
            if (args.len >= name_end + 2) {
                tp.lmr_base = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 25, 150);
                srch.quiet_lmr = srch.initQuietLMR();
            }
        } else if (std.mem.eql(u8, option_name, "lmr_div")) {
            if (args.len >= name_end + 2) {
                tp.lmr_div = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 100, 400);
                srch.quiet_lmr = srch.initQuietLMR();
            }
            else if (std.mem.eql(u8, option_name, "lmr_noisy_base")) {
                if (args.len >= name_end + 2) {
                    tp.lmr_noisy_base = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), -100, 100);
                    srch.noisy_lmr = srch.initNoisyLMR();
                }
            } else if (std.mem.eql(u8, option_name, "lmr_noisy_div")) {
                if (args.len >= name_end + 2) {
                    tp.lmr_noisy_div = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 100, 500);
                    srch.noisy_lmr = srch.initNoisyLMR();
                }
            }
        // } else if (std.mem.eql(u8, option_name, "lmr_pv_min")) {
        //     if (args.len >= name_end + 2) {
        //         tp.lmr_pv_min = @intCast(std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 1, 10));
        //     }
        // } else if (std.mem.eql(u8, option_name, "lmr_non_pv_min")) {
        //     if (args.len >= name_end + 2) {
        //         tp.lmr_non_pv_min = @intCast(std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 1, 10));
        //     }
        // } else if (std.mem.eql(u8, option_name, "se_double_threshold")) {
        //     if (args.len >= name_end + 2) {
        //         tp.se_double_threshold = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 0, 200);
        //     }
        // } else if (std.mem.eql(u8, option_name, "se_triple_threshold")) {
        //     if (args.len >= name_end + 2) {
        //         tp.se_triple_threshold = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 0, 200);
        //     }
        } else if (std.mem.eql(u8, option_name, "history_div")) {
            if (args.len >= name_end + 2) {
                tp.history_div = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 1024, 32768);
            }
        // } else if (std.mem.eql(u8, option_name, "corr_div_bm")) {
        //     if (args.len >= name_end + 2) {
        //         tp.corr_div_bm = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 1, 50);
        //     }
        // } else if (std.mem.eql(u8, option_name, "corr_div_nobm")) {
        //     if (args.len >= name_end + 2) {
        //         tp.corr_div_nobm = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 1, 50);
        //     }
        // } else if (std.mem.eql(u8, option_name, "corr_np_update_weight")) {
        //     if (args.len >= name_end + 2) {
        //         tp.corr_np_update_weight = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 32, 512);
        //     }
        // } else if (std.mem.eql(u8, option_name, "corr_pawn_read_weight")) {
        //     if (args.len >= name_end + 2) {
        //         tp.corr_pawn_read_weight = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 32, 512);
        //     }
        // } else if (std.mem.eql(u8, option_name, "corr_np_read_weight")) {
        //     if (args.len >= name_end + 2) {
        //         tp.corr_np_read_weight = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 32, 512);
        //     }
        // } else if (std.mem.eql(u8, option_name, "corr_major_read_weight")) {
        //     if (args.len >= name_end + 2) {
        //         tp.corr_major_read_weight = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 32, 512);
        //     }
        // } else if (std.mem.eql(u8, option_name, "corr_minor_read_weight")) {
        //     if (args.len >= name_end + 2) {
        //         tp.corr_minor_read_weight = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 32, 512);
        //     }
        // } else if (std.mem.eql(u8, option_name, "corr_read_divisor")) {
        //     if (args.len >= name_end + 2) {
        //         tp.corr_read_divisor = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 16384, 524288);
        //     }
        // } else if (std.mem.eql(u8, option_name, "probcut_margin")) {
        //     if (args.len >= name_end + 2) {
        //         tp.probcut_margin = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 0, 1000);
        //     }
        // } else if (std.mem.eql(u8, option_name, "probcut_improve")) {
        //     if (args.len >= name_end + 2) {
        //         tp.probcut_improve = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 0, 2000);
        //     }
        // } else if (std.mem.eql(u8, option_name, "probcut_min_see")) {
        //     if (args.len >= name_end + 2) {
        //         tp.probcut_min_see = std.math.clamp(try std.fmt.parseInt(i32, args[name_end + 1], 10), 0, 500);
        //     }
        } else {
            if (self.debug_mode) {
                try respond("Unknown option");
            }
        }

        // setup pawn_tt
        // if (!pawn_tt.pawn_tt_initialized) {
            // try pawn_tt.TranspositionTable.initGlobal(self.hash_size_mb / 8);
        // }
    }

    fn respond(response: []const u8) !void {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("{s}\n", .{response});
        try stdout.flush();
    }

    pub fn newGame(self: *UciProtocol) !void {
        self.tt_table.reset();


        // Safely zero out the massive board directly in memory
        @memset(std.mem.asBytes(&self.board), 0);

        // Re-initialize only what's needed
        self.board.game_state = brd.GameState.init();
        fen.setupStartingPosition(&self.board);
        self.board.refreshNNUE();
        self.is_searching = false;
    }

    fn handleBench(self: *UciProtocol, args: [][]const u8) !void {
        const depth: u32 = if (args.len >= 1) std.fmt.parseInt(u32, args[0], 10) catch 13 else 13;

        var total_nodes: u64 = 0;
        var timer = try std.time.Timer.start();

        for (bench_positions) |fen_str| {
            self.tt_table.reset();
            @memset(std.mem.asBytes(&self.board), 0);
            self.board.game_state = brd.GameState.init();
            try fen.parseFEN(&self.board, fen_str);
            self.board.refreshNNUE();

            self.searcher.stop = false;
            self.searcher.max_ms = std.math.maxInt(u64);
            self.searcher.ideal_ms = std.math.maxInt(u64);
            self.searcher.nodes = 0;

            _ = try self.searcher.parallelIterativeDeepening(&self.board, @intCast(depth), 1);
            total_nodes += self.searcher.nodes;
        }

        const elapsed_ns = timer.read();
        const nps = total_nodes * std.time.ns_per_s / @max(elapsed_ns, 1);

        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "{d} nodes {d} nps", .{ total_nodes, nps });
        try respond(msg);
    } 

    fn handlePosition(self: *UciProtocol, args: [][]const u8) !void {
        if (args.len == 0) {
            if (self.debug_mode) {
                try respond("Error: position command requires arguments");
            }
            return;
        }

        if (std.mem.eql(u8, args[0], "startpos")) {
            @memset(std.mem.asBytes(&self.board), 0);

            // Re-initialize only what is needed
            self.board.game_state = brd.GameState.init();
            fen.setupStartingPosition(&self.board);
            self.board.refreshNNUE();

            var j: usize = 1;
            if (j < args.len and std.mem.eql(u8, args[j], "moves")) {
                j += 1;
                for (args[j..]) |move_str| {
                    const move = mvs.parseMove(&self.board, move_str, self.chess960) orelse {
                        if (self.debug_mode) {
                            try respond("Error: invalid move");
                        }
                        return;
                    };
                    mvs.makeMove(&self.board, move);
                }
            }
        } else if (std.mem.eql(u8, args[0], "fen")) {
            var fen_parts = try std.ArrayList([]const u8).initCapacity(self.allocator, 32);
            defer fen_parts.deinit(self.allocator);

            var j: usize = 1;
            while (j < args.len and !std.mem.eql(u8, args[j], "moves")) : (j += 1) {
                try fen_parts.append(self.allocator, args[j]);
            }

            const fen_str = try std.mem.join(self.allocator, " ", fen_parts.items);
            defer self.allocator.free(fen_str);

            try fen.parseFEN(&self.board, fen_str);
            self.board.refreshNNUE();

            if (j < args.len and std.mem.eql(u8, args[j], "moves")) {
                j += 1;
                for (args[j..]) |move_str| {
                    const move = mvs.parseMove(&self.board, move_str, self.chess960) orelse {
                        if (self.debug_mode) {
                            try respond("Error: invalid move");
                        }
                        return;
                    };
                    mvs.makeMove(&self.board, move);
                }
            }
        } else {
            if (self.debug_mode) {
                try respond("Error: invalid position command");
            }
        }
    }

    fn printBoard(self: *UciProtocol) !void {
        try fen.debugPrintBoard(&self.board);
    }

    fn handleDatagen(self: *UciProtocol, args: [][]const u8) !void {
        _ = self;
        const config = datagen.parseCommand(args);
        try datagen.run(config);
    }

    pub fn sendInfo(self: *UciProtocol, comptime fmt: []const u8, args: anytype) !void {
        if (!self.is_searching) return;

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try stdout.print("info ", .{});
        try stdout.print(fmt, args);
        try stdout.flush();
    }

    fn handlePerft(self: *UciProtocol, args: [][]const u8) !void {
        if (args.len == 0) {
            if (self.debug_mode) {
                try respond("Error: perft command requires a depth argument");
            }
            return;
        }

        const depth = try std.fmt.parseInt(u32, args[0], 10);
        if (depth == 0) {
            if (self.debug_mode) {
                try respond("Error: perft depth must be greater than 0");
            }
            return;
        }
        try perft.runPerft(self.searcher.move_gen, &self.board, depth);
    }

    fn calculateTimeAllocation(self: *const UciProtocol, limits: *const SearchLimits, side_to_move: brd.Color) struct { max_ms: u64, ideal_ms: u64 } {
        if (limits.movetime) |mt| {
            return .{ .max_ms = mt, .ideal_ms = mt };
        }
        if (limits.infinite or limits.ponder) {
            return .{ .max_ms = std.math.maxInt(u64), .ideal_ms = std.math.maxInt(u64) };
        }
        const our_time = if (side_to_move == .White) limits.wtime else limits.btime;
        const our_inc = if (side_to_move == .White) limits.winc else limits.binc;
        if (our_time) |time| {
            const safe_time = time -| move_overhead;
            const increment = our_inc orelse 0;
            var moves_remaining: u64 = if (limits.movestogo) |mtg| mtg else blk: {
                if (increment == 0) break :blk @as(u64, 35);
                if (increment < 200) break :blk @as(u64, 30);
                break :blk @as(u64, 25);
            };
            if (self.tt_table.getFillPermill() > 800) {
                moves_remaining -= 5;
            } else if (self.tt_table.getFillPermill() < 200) {
                moves_remaining += 5;
            }
            const total_time = safe_time + (increment * (moves_remaining - 1));
            const base_time = total_time / moves_remaining;
            var ideal_ms = @min(base_time * 9 / 10, safe_time -| 50);
            const calculated_max = @min(ideal_ms * 3, safe_time * 4 / 10);
            var max_ms = @max(ideal_ms, calculated_max);
            max_ms = @min(max_ms, time);
            ideal_ms = @min(ideal_ms, max_ms * 8 / 10);
            return .{
                .max_ms = @max(max_ms, 1),
                .ideal_ms = @max(ideal_ms, 1),
            };
        }
        return .{ .max_ms = std.math.maxInt(u64), .ideal_ms = std.math.maxInt(u64) };
    }
};

const bench_positions = [_][]const u8{
        "r3k2r/2pb1ppp/2pp1q2/p7/1nP1B3/1P2P3/P2N1PPP/R2QK2R w KQkq - 0 14",
        "4rrk1/2p1b1p1/p1p3q1/4p3/2P2n1p/1P1NR2P/PB3PP1/3R1QK1 b - - 2 24",
        "r3qbrk/6p1/2b2pPp/p3pP1Q/PpPpP2P/3P1B2/2PB3K/R5R1 w - - 16 42",
        "6k1/1R3p2/6p1/2Bp3p/3P2q1/P7/1P2rQ1K/5R2 b - - 4 44",
        "8/8/1p2k1p1/3p3p/1p1P1P1P/1P2PK2/8/8 w - - 3 54",
        "7r/2p3k1/1p1p1qp1/1P1Bp3/p1P2r1P/P7/4R3/Q4RK1 w - - 0 36",
        "r1bq1rk1/pp2b1pp/n1pp1n2/3P1p2/2P1p3/2N1P2N/PP2BPPP/R1BQ1RK1 b - - 2 10",
        "3r3k/2r4p/1p1b3q/p4P2/P2Pp3/1B2P3/3BQ1RP/6K1 w - - 3 87",
        "2r4r/1p4k1/1Pnp4/3Qb1pq/8/4BpPp/5P2/2RR1BK1 w - - 0 42",
        "4q1bk/6b1/7p/p1p4p/PNPpP2P/KN4P1/3Q4/4R3 b - - 0 37",
        "2q3r1/1r2pk2/pp3pp1/2pP3p/P1Pb1BbP/1P4Q1/R3NPP1/4R1K1 w - - 2 34",
        "1r2r2k/1b4q1/pp5p/2pPp1p1/P3Pn2/1P1B1Q1P/2R3P1/4BR1K b - - 1 37",
        "r3kbbr/pp1n1p1P/3ppnp1/q5N1/1P1pP3/P1N1B3/2P1QP2/R3KB1R b KQkq - 0 17",
        "8/6pk/2b1Rp2/3r4/1R1B2PP/P5K1/8/2r5 b - - 16 42",
        "1r4k1/4ppb1/2n1b1qp/pB4p1/1n1BP1P1/7P/2PNQPK1/3RN3 w - - 8 29",
        "8/p2B4/PkP5/4p1pK/4Pb1p/5P2/8/8 w - - 29 68",
        "3r4/ppq1ppkp/4bnp1/2pN4/2P1P3/1P4P1/PQ3PBP/R4K2 b - - 2 20",
        "5rr1/4n2k/4q2P/P1P2n2/3B1p2/4pP2/2N1P3/1RR1K2Q w - - 1 49",
        "1r5k/2pq2p1/3p3p/p1pP4/4QP2/PP1R3P/6PK/8 w - - 1 51",
        "q5k1/5ppp/1r3bn1/1B6/P1N2P2/BQ2P1P1/5K1P/8 b - - 2 34",
        "r1b2k1r/5n2/p4q2/1ppn1Pp1/3pp1p1/NP2P3/P1PPBK2/1RQN2R1 w - - 0 22",
        "r1bqk2r/pppp1ppp/5n2/4b3/4P3/P1N5/1PP2PPP/R1BQKB1R w KQkq - 0 5",
        "r1bqr1k1/pp1p1ppp/2p5/8/3N1Q2/P2BB3/1PP2PPP/R3K2n b Q - 1 12",
        "r1bq2k1/p4r1p/1pp2pp1/3p4/1P1B3Q/P2B1N2/2P3PP/4R1K1 b - - 2 19",
        "r4qk1/6r1/1p4p1/2ppBbN1/1p5Q/P7/2P3PP/5RK1 w - - 2 25",
        "r7/6k1/1p6/2pp1p2/7Q/8/p1P2K1P/8 w - - 0 32",
        "r3k2r/ppp1pp1p/2nqb1pn/3p4/4P3/2PP4/PP1NBPPP/R2QK1NR w KQkq - 1 5",
        "3r1rk1/1pp1pn1p/p1n1q1p1/3p4/Q3P3/2P5/PP1NBPPP/4RRK1 w - - 0 12",
        "5rk1/1pp1pn1p/p3Brp1/8/1n6/5N2/PP3PPP/2R2RK1 w - - 2 20",
        "8/1p2pk1p/p1p1r1p1/3n4/8/5R2/PP3PPP/4R1K1 b - - 3 27",
        "8/4pk2/1p1r2p1/p1p4p/Pn5P/3R4/1P3PP1/4RK2 w - - 1 33",
        "8/5k2/1pnrp1p1/p1p4p/P6P/4R1PK/1P3P2/4R3 b - - 1 38",
        "8/8/1p1kp1p1/p1pr1n1p/P6P/1R4P1/1P3PK1/1R6 b - - 15 45",
        "8/8/1p1k2p1/p1prp2p/P2n3P/6P1/1P1R1PK1/4R3 b - - 5 49",
        "8/8/1p4p1/p1p2k1p/P2npP1P/4K1P1/1P6/3R4 w - - 6 54",
        "8/8/1p4p1/p1p2k1p/P2n1P1P/4K1P1/1P6/6R1 b - - 6 59",
        "8/5k2/1p4p1/p1pK3p/P2n1P1P/6P1/1P6/4R3 b - - 14 63",
        "8/1R6/1p1K1kp1/p6p/P1p2P1P/6P1/1Pn5/8 w - - 0 67",
        "1rb1rn1k/p3q1bp/2p3p1/2p1p3/2P1P2N/PP1RQNP1/1B3P2/4R1K1 b - - 4 23",
        "4rrk1/pp1n1pp1/q5p1/P1pP4/2n3P1/7P/1P3PB1/R1BQ1RK1 w - - 3 22",
        "r2qr1k1/pb1nbppp/1pn1p3/2ppP3/3P4/2PB1NN1/PP3PPP/R1BQR1K1 w - - 4 12",
        "2r2k2/8/4P1R1/1p6/8/P4K1N/7b/2B5 b - - 0 55",
        "6k1/5pp1/8/2bKP2P/2P5/p4PNb/B7/8 b - - 1 44",
        "2rqr1k1/1p3p1p/p2p2p1/P1nPb3/2B1P3/5P2/1PQ2NPP/R1R4K w - - 3 25",
        "r1b2rk1/p1q1ppbp/6p1/2Q5/8/4BP2/PPP3PP/2KR1B1R b - - 2 14",
        "6r1/5k2/p1b1r2p/1pB1p1p1/1Pp3PP/2P1R1K1/2P2P2/3R4 w - - 1 36",
        "rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2",
        "2rr2k1/1p4bp/p1q1p1p1/4Pp1n/2PB4/1PN3P1/P3Q2P/2RR2K1 w - f6 0 20",
        "3br1k1/p1pn3p/1p3n2/5pNq/2P1p3/1PN3PP/P2Q1PB1/4R1K1 w - - 0 23",
        "2r2b2/5p2/5k2/p1r1pP2/P2pB3/1P3P2/K1P3R1/7R w - - 23 93",
};
