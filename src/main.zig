const std = @import("std");
const uci = @import("uci/uci.zig");
const prft = @import("chess/perft.zig");

pub fn main() !void {
    // try prft.runPerftTest();
    std.debug.print("Here we go!\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var engine = try uci.UciProtocol.init(gpa.allocator());

    var stdin_buf: [2048]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const reader: *std.Io.Reader = &stdin_reader.interface;

    while (true) {
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

