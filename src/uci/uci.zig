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
};
