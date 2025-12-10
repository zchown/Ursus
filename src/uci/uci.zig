const std = @import("std");
const brd = @import("../chess/board.zig");
const mvs = @import("../chess/moves.zig");
const fen = @import("../chess/fen.zig");
const srch = @import("../engine/search.zig");
const tt = @import("../engine/transposition.zig");

pub const UciProtocol = struct {
    board: brd.Board,
    table: tt.TranspositionTable,
    move_gen: mvs.MoveGen,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !UciProtocol {
        return UciProtocol{
            .table = try tt.TranspositionTable.init(allocator, 1 << 15, null),
            .board = brd.Board.init(),
            .move_gen = mvs.MoveGen.init(),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UciProtocol) void {
        self.table.deinit();
    }

    pub fn receiveCommand(self: *UciProtocol, command: []const u8) !void {
        var tokenizer = std.mem.tokenizeScalar(u8, command, ' ');
        var parts = try std.ArrayList([]const u8).initCapacity(self.allocator, 8);
        defer parts.deinit(self.allocator);

        while (tokenizer.next()) |token| {
            try parts.append(self.allocator, token);
        }
        if (parts.items.len == 0) return;

        const commandName = parts.items[0];
        const args = parts.items[1..];

        if (std.mem.eql(u8, commandName, "uci")) {
            try respond("id name Ursus");
            try respond("id author Zander");
            try respond("uciok");
            try self.newGame();
        } else if (std.mem.eql(u8, commandName, "isready")) {
            try respond("readyok");
        } else if (std.mem.eql(u8, commandName, "ucinewgame")) {
            try self.newGame();
        } else if (std.mem.eql(u8, commandName, "position")) {
            try self.handlePosition(args);
        } else if (std.mem.eql(u8, commandName, "go")) {
            try self.handleGo(args);
        } else if (std.mem.eql(u8, commandName, "stop")) {
            // Handle stop command
        } else if (std.mem.eql(u8, commandName, "quit")) {
            // Handle quit command
        } else if (std.mem.eql(u8, commandName, "d")) {
            try self.printBoard();
        } else {
            try respond("Unknown command");
        }
    }

    fn respond(response: []const u8) !void {
        var stdout_buf: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
        const stdout = &stdout_writer.interface;

        try stdout.print("{s}\n", .{response});
        try stdout.flush();
    } 

    fn newGame(self: *UciProtocol) !void {
        self.table.deinit(self.allocator);
        self.table = try tt.TranspositionTable.init(self.allocator, 1 << 15, null);
        self.board = brd.Board.init();
        fen.setupStartingPosition(&self.board);
    }

    fn handlePosition(self: *UciProtocol, args: [][]const u8) !void {
        if (args.len == 0) {
            try respond("Error: position command requires arguments");
            return;
        }

        if (std.mem.eql(u8, args[0], "startpos")) {
            self.board = brd.Board.init();
            fen.setupStartingPosition(&self.board);
            var i: usize = 1;
            if (i < args.len and std.mem.eql(u8, args[i], "moves")) {
                std.debug.print("Parsing moves\n", .{});
                i += 1;
                for (args[i..]) |move_str| {
                    const move = mvs.parseMove(&self.board, move_str) orelse {
                        try respond("Error: invalid move");
                        return;
                    };
                    mvs.makeMove(&self.board, move);
                }
            }
        } else if (std.mem.eql(u8, args[0], "fen")) {
            var fen_parts = try std.ArrayList([]const u8).initCapacity(self.allocator, 8);
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
                        try respond("Error: invalid move");
                        return;
                    };
                    mvs.makeMove(&self.board, move);
                }
            }
        } else {
            try respond("Error: invalid position command");
        }
    }

    fn handleGo(self: *UciProtocol, args: [][]const u8) !void {
        _ = args; // TODO: Parse search parameters
        const result = srch.search(&self.board, &self.move_gen, &self.table, 2500);

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        try stdout.print("bestmove {s}\n", .{ try result.search_result.bestMove.uciToString(self.allocator) });
        try stdout.flush();

        mvs.makeMove(&self.board, result.search_result.bestMove);
    } 

    fn printBoard(self: *UciProtocol) !void {
        try fen.debugPrintBoard(&self.board);
    }
};
