const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tracy = b.option([]const u8, "tracy", "Enable Tracy integration. Supply path to Tracy source");
    const tracy_callstack = b.option(bool, "tracy-callstack", "Include callstack information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy != null);
    const tracy_allocation = b.option(bool, "tracy-allocation", "Include allocation information with Tracy data. Does nothing if -Dtracy is not provided") orelse (tracy != null);
    const tracy_callstack_depth: u32 = b.option(u32, "tracy-callstack-depth", "Declare callstack depth for Tracy data. Does nothing if -Dtracy-callstack is not provided") orelse 10;

    const tracy_module = b.createModule(.{
        .root_source_file = b.path("Tracy/tracy.zig"),
        .target = target,
        .optimize = optimize,
    });

    const board_module = b.createModule(.{
        .root_source_file = b.path("src/chess/board.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zobrist_module = b.createModule(.{
        .root_source_file = b.path("src/chess/zobrist.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fen_module = b.createModule(.{
        .root_source_file = b.path("src/chess/fen.zig"),
        .target = target,
        .optimize = optimize,
    });

    const magic_module = b.createModule(.{
        .root_source_file = b.path("src/chess/magics.zig"),
        .target = target,
        .optimize = optimize,
    });

    const radagast_module = b.createModule(.{
        .root_source_file = b.path("src/chess/radagast.zig"),
        .target = target,
        .optimize = optimize,
    });

    const moves_module = b.createModule(.{
        .root_source_file = b.path("src/chess/moves.zig"),
        .target = target,
        .optimize = optimize,
    });

    const uci_module = b.createModule(.{
        .root_source_file = b.path("src/uci/uci.zig"),
        .target = target,
        .optimize = optimize,
    });

    const perft_module = b.createModule(.{
        .root_source_file = b.path("src/chess/perft.zig"),
        .target = target,
        .optimize = optimize,
    });

    const transposition_module = b.createModule(.{
        .root_source_file = b.path("src/engine/transposition.zig"),
        .target = target,
        .optimize = optimize,
    });

    const eval_module = b.createModule(.{
        .root_source_file = b.path("src/engine/eval.zig"),
        .target = target,
        .optimize = optimize,
    });

    const search_module = b.createModule(.{
        .root_source_file = b.path("src/engine/search.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "Ursus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = true,
    });

    board_module.addImport("zobrist", zobrist_module);
    board_module.addImport("moves", moves_module);

    perft_module.addImport("board", board_module);
    perft_module.addImport("moves", moves_module);
    perft_module.addImport("fen", fen_module);

    fen_module.addImport("board", board_module);
    fen_module.addImport("zobrist", zobrist_module);

    moves_module.addImport("board", board_module);
    moves_module.addImport("magic", magic_module);
    moves_module.addImport("radagast", radagast_module);

    zobrist_module.addImport("board", board_module);

    radagast_module.addImport("board", board_module);

    search_module.addImport("board", board_module);
    search_module.addImport("moves", moves_module);
    search_module.addImport("eval", eval_module);
    search_module.addImport("transposition", transposition_module);

    transposition_module.addImport("board", board_module);
    transposition_module.addImport("zobrist", zobrist_module);
    transposition_module.addImport("moves", moves_module);

    uci_module.addImport("board", board_module);
    uci_module.addImport("search", search_module);
    uci_module.addImport("fen", fen_module);
    uci_module.addImport("transposition", transposition_module);
    uci_module.addImport("moves", moves_module);

    eval_module.addImport("board", board_module);
    eval_module.addImport("moves", moves_module);

    exe.root_module.addImport("uci", uci_module);
    exe.root_module.addImport("perft", perft_module);

    b.installArtifact(exe);

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
    tracy_module.addOptions("build_options", exe_options);

    exe_options.addOption(bool, "enable_tracy", tracy != null);
    exe_options.addOption(bool, "enable_tracy_callstack", tracy_callstack);
    exe_options.addOption(bool, "enable_tracy_allocation", tracy_allocation);
    exe_options.addOption(u32, "tracy_callstack_depth", tracy_callstack_depth);

    if (tracy) |tracy_path| {
        const client_cpp = b.pathJoin(&[_][]const u8{ tracy_path, "public", "TracyClient.cpp" });
        const tracy_c_flags: []const []const u8 = &.{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

        exe.root_module.addIncludePath(.{ .cwd_relative = tracy_path });
        exe.root_module.addCSourceFile(.{ .file = .{ .cwd_relative = client_cpp }, .flags = tracy_c_flags });
        exe.root_module.linkSystemLibrary("c++", .{ .use_pkg_config = .no });
        exe.root_module.link_libc = true;
    }

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
