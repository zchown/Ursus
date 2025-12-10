const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "Ursus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);
    // Run command for the main executable
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    b.step("run", "Run the chess engine").dependOn(&run_cmd.step);
    // === Unit Testing ===
    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // Link the modules to the test executable
    const test_step = b.step("test", "Run unit tests");
    const run_tests = b.addRunArtifact(test_exe);
    test_step.dependOn(&run_tests.step);
}
