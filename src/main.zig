const std = @import("std");
const uci = @import("uci");
const perft = @import("perft");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const engine = try uci.UciProtocol.init(allocator);
    defer engine.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len >= 2) {
        const cmd = args[1];
        if (std.mem.eql(u8, cmd, "bench") or std.mem.eql(u8, cmd, "bench-expected")) {
            try engine.newGame();
            const cmd_line = try std.mem.join(allocator, " ", args[1..]);
            defer allocator.free(cmd_line);
            try engine.receiveCommand(cmd_line);
            return;
        }
    }

    var stdin_buf: [4096 * 2]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const reader: *std.Io.Reader = &stdin_reader.interface;

    while (true) {
        const maybe_line = reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        const trimmed = std.mem.trim(u8, maybe_line, " \r\n");

        if (std.mem.eql(u8, trimmed, "quit")) break;

        engine.receiveCommand(trimmed) catch |err| {
            std.debug.print("Command error: {} on: {s}\n", .{ err, trimmed });
        };
    }
}
