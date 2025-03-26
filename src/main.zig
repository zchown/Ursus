const std = @import("std");
const uci = @import("uci/uci.zig");
const prft = @import("chess/perft.zig");

pub fn main() !void {
    // try prft.runPerftTest();
    std.debug.print("Here we go!\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var engine = try uci.UciProtocol.init(gpa.allocator());

    const stdin = std.io.getStdIn().reader();
    var buffer = std.ArrayList(u8).init(gpa.allocator());
    defer buffer.deinit();

    while (true) {
        buffer.clearRetainingCapacity();

        // Use readUntilDelimiterArrayList instead
        try stdin.readUntilDelimiterArrayList(&buffer, '\n', 4096 // Maximum chunk size to read at once
        );

        const trimmed = std.mem.trim(u8, buffer.items, " \r\n");
        if (std.mem.eql(u8, trimmed, "quit")) break;

        try engine.receiveCommand(trimmed);
    }
}
