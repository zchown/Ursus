const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "my_chess_engine",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Add the engine module
    const engine_mod = b.addModule("engine", .{
        .root_source_file = b.path("src/engine/engine.zig"),
    });
    // Add the chess module
    const chess_mod = b.addModule("chess", .{
        .root_source_file = b.path("src/chess/chess.zig"),
    });
    // Link modules to the main executable
    exe.root_module.addImport("engine", engine_mod);
    exe.root_module.addImport("chess", chess_mod);
    b.installArtifact(exe);
    // Run command for the main executable
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    b.step("run", "Run the chess engine").dependOn(&run_cmd.step);
    // === Unit Testing ===
    const test_exe = b.addTest(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Link the modules to the test executable
    test_exe.root_module.addImport("engine", engine_mod);
    test_exe.root_module.addImport("chess", chess_mod);
    const test_step = b.step("test", "Run unit tests");
    const run_tests = b.addRunArtifact(test_exe);
    test_step.dependOn(&run_tests.step);
}
