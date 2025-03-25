const std = @import("std");
const brd = @import("../chess/board.zig");
const mvs = @import("../chess/moves.zig");
const fen = @import("../chess/fen.zig");
const srch = @import("../engine/search.zig");
const tt = @import("../engine/transposition.zig");

pub const UciProtocol = struct {
    board: brd.Board,
    table: tt.TranspositionTable,
    move_gen: mvs.MoveGenerator,
    allocator: std.mem.Allocator,

    pub fn init(self: UciProtocol, allocator: std.mem.Allocator) UciProtocol {
        var toReturn = UciProtocol{
            .table = self.table.init(allocator, 1 << 15, null),
            .board = self.board.init(),
            .move_gen = self.move_gen.init(),
            .allocator = allocator,
        };
        fen.setupStartingPosition(&toReturn.board);
        return toReturn;
    }

    pub fn receiveCommand(self: UciProtocol, command: []const u8) void {
        const commandStr = std.heap.dupStr(self.allocator, command);
        const parts = std.mem.splitScalar(commandStr, " ");

        const commandName = parts[0];

        if (std.mem.eql(u8, commandName, "uci")) {
            UciProtocol.respond("uciok");
        } else if (std.mem.eql(u8, commandName, "isready")) {
            UciProtocol.respond("readyok");
        } else if (std.mem.eql(u8, commandName, "ucinewgame")) {
            self.newGame();
        } else if (std.mem.eql(u8, commandName, "position")) {
            self.handlePosition(parts);
        } else if (std.mem.eql(u8, commandName, "go")) {
            self.handleGo(parts);
        } else if (std.mem.eql(u8, commandName, "stop")) {
            self.handleStop();
        } else if (std.mem.eql(u8, commandName, "quit")) {
            return;
        } else if (std.mem.eql(u8, commandName, "d")) {
            std.io.getStdOut().write(fen.printBoard(&self.board));
        } else {
            UciProtocol.respond("Unknown command");
        }
    } 

    fn respond(response: []const u8) void {
        std.io.getStdOut().write(response);
        std.io.getStdOut().write("\n");
    }

    fn newGame(self: UciProtocol) void {
        self.allocator.free(self.table);
        self.table = self.table.init(self.allocator, 1 << 15, null);
        self.board = self.board.init();
        fen.setupStartingPosition(&self.board);
    }

    fn handlePosition(self: UciProtocol, parts: [][]const u8) void {
        if (parts.len < 2) {
            UciProtocol.respond("Error: position command requires at least 2 arguments");
            return;
        }

        if (std.mem.eql(u8, parts[1], "startpos")) {
            fen.setupStartingPosition(&self.board);
            if (parts.len > 2 and std.mem.eql(u8, parts[2], "moves")) {
                for (3..parts.len) |i| {
                    const move = mvs.parseMove(&self.board, parts[i]);
                    if (move == null) {
                        UciProtocol.respond("Error: invalid move in position command");
                        return;
                    }
                    mvs.makeMove(&self.board, move);
                }
            }
        } else if (std.mem.eql(u8, parts[1], "fen")) {
            if (parts.len < 3) {
                UciProtocol.respond("Error: position fen command requires a fen string");
                return;
            }

            const fenStr = parts[2];
            if (!fen.parseFEN(&self.board, fenStr)) {
                UciProtocol.respond("Error: invalid fen string");
                return;
            }

            if (parts.len > 3 and std.mem.eql(u8, parts[3], "moves")) {
                for (4..parts.len) |i| {
                    const move = mvs.parseMove(&self.board, parts[i]);
                    if (move == null) {
                        UciProtocol.respond("Error: invalid move in position command");
                        return;
                    }
                    mvs.makeMove(&self.board, move);
                }
            }
        } else {
            UciProtocol.respond("Error: invalid position command");
            return;
        }
    }
};



