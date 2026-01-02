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
    table: tt.TranspositionTable,
    move_gen: mvs.MoveGen,
    allocator: std.mem.Allocator,
    debug_mode: bool = false,
    should_quit: bool = false,
    is_searching: bool = false,
    hash_size_mb: u32 = 16,


    pub fn init(allocator: std.mem.Allocator) !UciProtocol {
        return UciProtocol{
            .table = try tt.TranspositionTable.init(allocator, 1 << 15, null),
            .board = brd.Board.init(),
            .move_gen = mvs.MoveGen.init(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UciProtocol) void {
        self.table.deinit(self.allocator);
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
        self.table.clear();
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

        // Calculate time to use based on limits
        var search_time: u64 = 2500; 
        if (limits.movetime) |mt| {
            search_time = mt;
        } else if (limits.wtime != null or limits.btime != null) {
            const our_time = if (self.board.game_state.side_to_move == .White) 
                limits.wtime orelse 0 
                else 
                    limits.btime orelse 0;
                const our_inc = if (self.board.game_state.side_to_move == .White)
                    limits.winc orelse 0
                    else
                        limits.binc orelse 0;

                    search_time = our_time / 30 + our_inc;
        }

        const result = srch.search(&self.board, &self.move_gen, &self.table, @as(isize, @intCast(search_time)));

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        const move_str = try result.search_result.bestMove.uciToString(self.allocator);
        defer self.allocator.free(move_str);

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
