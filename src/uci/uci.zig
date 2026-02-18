const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const fen = @import("fen");
const srch = @import("search");
const tt = @import("transposition");
const eval = @import("eval");

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

pub const UciProtocol = struct {
    board: brd.Board,
    allocator: std.mem.Allocator,
    debug_mode: bool = false,
    should_quit: bool = false,
    is_searching: bool = false,
    hash_size_mb: u32 = 16,
    searcher: *srch.Searcher,

    pub fn init(a: std.mem.Allocator) !UciProtocol {
        std.debug.print("Initializing UCI protocol...\n", .{});

        const searcher_ptr = try a.create(srch.Searcher);
        errdefer a.destroy(searcher_ptr);

        searcher_ptr.initInPlace();

        return UciProtocol{
            .board = brd.Board.init(),
            .allocator = a,
            .searcher = searcher_ptr,
        };
    }

    pub fn deinit(self: *UciProtocol) void {
        self.searcher.deinit();
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
            // print fen of current position for debugging
            try fen.debugPrintBoard(&self.board);
        } else if (std.mem.eql(u8, commandName, "ucinewgame")) {
            try self.newGame();
        } else if (std.mem.eql(u8, commandName, "position")) {
            try self.handlePosition(args);
        } else if (std.mem.eql(u8, commandName, "go")) {
            try self.handleGo(args);
        } else if (std.mem.eql(u8, commandName, "stop")) {
            self.is_searching = false;
        } else if (std.mem.eql(u8, commandName, "ponderhit")) {
            self.is_searching = true;
        } else if (std.mem.eql(u8, commandName, "quit")) {
            self.should_quit = true;
        } else if (std.mem.eql(u8, commandName, "setoption")) {
            try self.handleSetOption(args);
        } else if (std.mem.eql(u8, commandName, "debug")) {
            try self.handleDebug(args);
        } else if (std.mem.eql(u8, commandName, "register")) {
            // Optional: handle registration if needed
            try respond("registration checking");
        } else if (std.mem.eql(u8, commandName, "d")) {
            try self.printBoard();
        } else {
            if (self.debug_mode) {
                try respond("Unknown command");
            }
        }
    }

    fn handleUci(self: *UciProtocol) !void {
        try respond("id name Ursus");
        try respond("id author Zander");

        try respond("option name aspiration_window type spin default 32 min 10 max 200");
        try respond("option name rfp_depth type spin default 7 min 1 max 12");
        try respond("option name rfp_mul type spin default 90 min 25 max 100");
        try respond("option name rfp_improvement type spin default 41 min 10 max 150");
        try respond("option name nmp_improvement type spin default 31 min 10 max 150");
        try respond("option name nmp_base type spin default 4 min 1 max 8");
        try respond("option name nmp_depth_div type spin default 5 min 1 max 8");
        try respond("option name nmp_beta_div type spin default 155 min 50 max 300");
        try respond("option name razoring_base type spin default 286 min 100 max 600");
        try respond("option name razoring_mul type spin default 84 min 10 max 200");
        try respond("option name probcut_margin type spin default 197 min 50 max 600");
        try respond("option name probcut_depth type spin default 4 min 1 max 8");
        try respond("option name lazy_margin type spin default 813 min 50 max 2000");
        try respond("option name q_see_margin type spin default -27 min -200 max 0");
        try respond("option name q_delta_margin type spin default 192 min 0 max 400");
        try respond("option name lmr_base type spin default 73 min 25 max 125");
        try respond("option name lmr_mul type spin default 41 min 10 max 100");
        try respond("option name lmr_pv_min type spin default 7 min 1 max 10");
        try respond("option name lmr_non_pv_min type spin default 4 min 1 max 10");
        try respond("option name futility_mul type spin default 137 min 25 max 400");
        try respond("option name iid_depth type spin default 1 min 1 max 4");
        // try respond("option name lmp_base type spin default 3 min 0 max 10");
        // try respond("option name lmp_mul type spin default 3 min 0 max 10");
        // try respond("option name lmp_improve type spin default 2 min 0 max 3");
        try respond("option name se_reduction type spin default 4 min 0 max 10");
        try respond("option name history_div type spin default 6229 min 0 max 16384");

        try respond("uciok");

        srch.quiet_lmr = srch.initQuietLMR();

        try self.newGame();
    }

    fn handleDebug(self: *UciProtocol, args: [][]const u8) !void {
        if (args.len > 0) {
            if (std.mem.eql(u8, args[0], "on")) {
                self.debug_mode = true;
            } else if (std.mem.eql(u8, args[0], "off")) {
                self.debug_mode = false;
            }
        }
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
            // TODO: handle hash size option
        } else if (std.mem.eql(u8, option_name, "Clear Hash")) {
            // TODO: handle clear hash option
        } else if (std.mem.eql(u8, option_name, "Ponder")) {
            // TODO: handle ponder option
        }

        if (std.mem.eql(u8, option_name, "aspiration_window")) {
            srch.aspiration_window = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "rfp_depth")) {
            srch.rfp_depth = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "rfp_mul")) {
            srch.rfp_mul = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "rfp_improvement")) {
            srch.rfp_improve = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "nmp_improvement")) {
            srch.nmp_improve = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "nmp_base")) {
            srch.nmp_base = try std.fmt.parseInt(usize, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "nmp_depth_div")) {
            srch.nmp_depth_div = try std.fmt.parseInt(usize, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "nmp_beta_div")) {
            srch.nmp_beta_div = try std.fmt.parseInt(usize, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "razoring_base")) {
            srch.razoring_base = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "razoring_mul")) {
            srch.razoring_mul = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "probcut_margin")) {
            srch.probcut_margin = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "probcut_depth")) {
            srch.probcut_depth = try std.fmt.parseInt(usize, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "lazy_margin")) {
            eval.lazy_margin = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "q_see_margin")) {
            srch.q_see_margin = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "q_delta_margin")) {
            srch.q_delta_margin = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "lmr_base")) {
            srch.lmr_base = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "lmr_mul")) {
            srch.lmr_mul = try std.fmt.parseInt(i32, args[name_end + 1], 10);
            srch.quiet_lmr = srch.initQuietLMR();
        } else if (std.mem.eql(u8, option_name, "lmr_pv_min")) {
            srch.lmr_pv_min = try std.fmt.parseInt(usize, args[name_end + 1], 10);
            srch.quiet_lmr = srch.initQuietLMR();
        } else if (std.mem.eql(u8, option_name, "lmr_non_pv_min")) {
            srch.lmr_non_pv_min = try std.fmt.parseInt(usize, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "futility_mul")) {
            srch.futility_mul = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "iid_depth")) {
            srch.iid_depth = try std.fmt.parseInt(usize, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "se_reduction")) {
            srch.se_reduction = try std.fmt.parseInt(usize, args[name_end + 1], 10);
        } else if (std.mem.eql(u8, option_name, "history_div")) {
            srch.history_div = try std.fmt.parseInt(i32, args[name_end + 1], 10);
        }
    }

    fn respond(response: []const u8) !void {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("{s}\n", .{response});
        try stdout.flush();
    }

    fn newGame(self: *UciProtocol) !void {
        // tt.global_tt.reset();
        self.board = brd.Board.init();
        fen.setupStartingPosition(&self.board);
        self.is_searching = false;
    }

    fn handlePosition(self: *UciProtocol, args: [][]const u8) !void {
        if (args.len == 0) {
            if (self.debug_mode) {
                try respond("Error: position command requires arguments");
            }
            return;
        }

        if (std.mem.eql(u8, args[0], "startpos")) {
            self.board = brd.Board.init();
            fen.setupStartingPosition(&self.board);
            var i: usize = 1;
            if (i < args.len and std.mem.eql(u8, args[i], "moves")) {
                i += 1;
                for (args[i..]) |move_str| {
                    const move = mvs.parseMove(&self.board, move_str) orelse {
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

            var i: usize = 1;
            while (i < args.len and !std.mem.eql(u8, args[i], "moves")) : (i += 1) {
                try fen_parts.append(self.allocator, args[i]);
            }

            const fen_str = try std.mem.join(self.allocator, " ", fen_parts.items);
            defer self.allocator.free(fen_str);

            try fen.parseFEN(&self.board, fen_str);

            if (i < args.len and std.mem.eql(u8, args[i], "moves")) {
                i += 1;
                for (args[i..]) |move_str| {
                    const move = mvs.parseMove(&self.board, move_str) orelse {
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

    fn handleGo(self: *UciProtocol, args: [][]const u8) !void {
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
                // TODO: implement searchmoves parsing
            } else {
                i += 1;
            }
        }

        self.is_searching = true;

        self.is_searching = true;
        const time_allocation = calculateTimeAllocation(&limits, self.board.toMove());
        self.searcher.max_ms = time_allocation.max_ms;
        self.searcher.ideal_ms = time_allocation.ideal_ms;

        const result = try self.searcher.parallelIterativeDeepening(&self.board, null, 2);
        std.debug.print("Search completed", .{});

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        const move_str = try result.move.uciToString(self.allocator);
        defer self.allocator.free(move_str);

        // construct PV string
        var pv_string_buffer: [512]u8 = @splat(0);
        var pv_string_len: usize = 0;
        for (result.pv[0..result.pv_length]) |move| {
            const cur_move_str = try move.uciToString(self.allocator);
            defer self.allocator.free(cur_move_str);
            const needed_len = pv_string_len + cur_move_str.len + 1;
            if (needed_len > pv_string_buffer.len) {
                break; // PV string is too long, stop adding moves
            }
            std.mem.copyForwards(u8, pv_string_buffer[pv_string_len..], cur_move_str);
            pv_string_len += cur_move_str.len;
            pv_string_buffer[pv_string_len] = ' ';
            pv_string_len += 1;
        }
        const pv_string = pv_string_buffer[0..pv_string_len];

        // output info about the best move found
        try stdout.print("info depth {d} seldepth {d} time {d} nodes {d} pv {s} score cp {d}\n",
            .{self.searcher.search_depth, self.searcher.seldepth, result.time_ms, result.nodes, pv_string, result.score});

        try stdout.print("bestmove {s}\n", .{move_str});

        try stdout.flush();
self.is_searching = false;
    }

    fn printBoard(self: *UciProtocol) !void {
        try fen.debugPrintBoard(&self.board);
    }

    pub fn sendInfo(self: *UciProtocol, comptime fmt: []const u8, args: anytype) !void {
        if (!self.is_searching) return;

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("info ", .{});
        try stdout.print(fmt, args);
        try stdout.print("", .{});
        try stdout.flush();
    }
};

fn calculateTimeAllocation(limits: *const SearchLimits, side_to_move: brd.Color) struct { max_ms: u64, ideal_ms: u64 } {
    const overhead: u64 = 30;

    if (limits.movetime) |mt| {
        return .{ .max_ms = mt, .ideal_ms = mt };
    }
    if (limits.infinite or limits.ponder) {
        return .{ .max_ms = std.math.maxInt(u64), .ideal_ms = std.math.maxInt(u64) };
    }
    const our_time = if (side_to_move == .White) limits.wtime else limits.btime;
    const our_inc = if (side_to_move == .White) limits.winc else limits.binc;
    if (our_time) |time| {
        const safe_time = time -| overhead;
        const increment = our_inc orelse 0;
        const moves_remaining: u64 = if (limits.movestogo) |mtg| mtg else 25;
        const total_time = safe_time + (increment * (moves_remaining - 1));
        const base_time = total_time / moves_remaining;
        const ideal_ms = @min(base_time * 9 / 10, safe_time -| 50);
        const max_ms = @min(ideal_ms * 3, safe_time * 4 / 10);
        return .{
            .max_ms = @max(max_ms, 1),
            .ideal_ms = @max(ideal_ms, 1),
        };
    }
    return .{ .max_ms = 1000, .ideal_ms = 1000 };
}
