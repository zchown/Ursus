const std = @import("std");
const uci = @import("uci");
const perft = @import("perft");

pub fn main() !void {
    // try perft.runPerftTest();

    std.debug.print("Here we go!\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    std.debug.print("Initializing engine...\n", .{});
    var engine = try uci.UciProtocol.init(gpa.allocator());
    std.debug.print("Engine initialized.\n", .{});
    
    var stdin_buf: [4096 * 2]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const reader: *std.Io.Reader = &stdin_reader.interface;
    
    while (true) {
        std.debug.print(">> ", .{});
        const maybe_line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            error.StreamTooLong => {
                return err;
            },
            else => return err,
        };
    
        const trimmed = std.mem.trim(u8, maybe_line, " \r\n");
    
        if (std.mem.eql(u8, trimmed, "quit")) break;
    
        try engine.receiveCommand(trimmed);
    }
}

