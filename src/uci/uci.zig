const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const fen = @import("fen");
const srch = @import("search");
const tt = @import("transposition");

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

        // tt.global_tt = try tt.TranspositionTable.init(@as(usize, 16));
        // try tt.global_tt.initInPlace(@as(usize, 16));
        // try tt.TranspositionTable.initGlobal(@as(usize, 16));

        // std.debug.print("global_tt initialized with {} entries\n", .{tt.global_tt.items.items.len});

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

        try respond("uciok");
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

        const result = try self.searcher.iterative_deepening(&self.board, null);
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
    if (limits.movetime) |mt| {
        const mt_f : f32 = @as(f32, @floatFromInt(mt));
        const max_ms = @max(@as(u64, @intFromFloat(mt_f * 0.9)), 1);
        const ideal_ms = @max(@as(u64, @intFromFloat(mt_f * 0.8)), 1);
        return .{ .max_ms = max_ms, .ideal_ms = ideal_ms };
    }

    if (limits.infinite or limits.ponder) {
        return .{ .max_ms = std.math.maxInt(u64), .ideal_ms = std.math.maxInt(u64) };
    }

    const our_time = if (side_to_move == .White) limits.wtime else limits.btime;
    const our_inc = if (side_to_move == .White) limits.winc else limits.binc;

    if (our_time) |time| {
        const increment = our_inc orelse 0;

        const moves_remaining: u64 = if (limits.movestogo) |mtg| mtg else 40;

        // base_time = (time + increment * (moves_remaining - 1)) / moves_remaining
        const total_time = time + (increment * (moves_remaining - 1));
        const base_time = total_time / moves_remaining;

        // Calculate ideal time (what we aim to use)
        // Use slightly less than base to have a buffer
        const ideal_ms = @min(base_time * 7 / 10, time - 100); // Use 70% of base, leave 100ms buffer

        // Calculate max time (hard limit)
        // Allow using up to 3x ideal in critical positions, but never more than 40% of remaining time
        const max_ms = @min(ideal_ms * 3, time * 4 / 10);

        return .{
            .max_ms = @max(max_ms, 1), 
            .ideal_ms = @max(ideal_ms, 1),
        };
    }

    // Fallback if no time controls specified
    return .{ .max_ms = 1000, .ideal_ms = 1000 };
}
