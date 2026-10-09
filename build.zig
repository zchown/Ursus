const std = @import("std");

fn buildExe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "Ursus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .use_llvm = true,
    });

    const zon_file = @embedFile("build.zig.zon");
    const ver_tag = ".version = \"";
    const start_idx = std.mem.indexOf(u8, zon_file, ver_tag) orelse @panic("No version found in build.zig.zon");
    const after_tag = zon_file[start_idx + ver_tag.len ..];
    const end_idx = std.mem.indexOf(u8, after_tag, "\"") orelse @panic("Unclosed version quote");
    const base_version = after_tag[0..end_idx];

    var is_dev = true;
    if (std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "git", "describe", "--tags", "--exact-match" },
    })) |result| {
        if (result.term == .Exited and result.term.Exited == 0) {
            is_dev = false;
        }
    } else |_| {}

    var final_version: []const u8 = base_version;
    if (is_dev) {
        var commit_hash: []const u8 = "unknown";
        if (std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{ "git", "rev-parse", "--short", "HEAD" },
        })) |result| {
            if (result.term == .Exited and result.term.Exited == 0) {
                commit_hash = std.mem.trim(u8, result.stdout, " \r\n");
            }
        } else |_| {}
        final_version = b.fmt("{s}-dev-{s}", .{ base_version, commit_hash });
    }

    const exe_options = b.addOptions();
    exe_options.addOption([]const u8, "version", final_version);
    exe_options.addOption(bool, "is_dev", is_dev);
    exe.root_module.addOptions("build_options", exe_options);

    const fathom_dep = b.dependency("fathom", .{});

    const fathom = b.addLibrary(.{
        .name = "fathom",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    fathom.root_module.addCSourceFile(.{
        .file = fathom_dep.path("src/tbprobe.c"),
        .flags = &.{ "-std=c11", "-O3", "-DNDEBUG", "-fno-sanitize=undefined" },
    });
    fathom.root_module.addIncludePath(fathom_dep.path("src"));

    exe.root_module.addIncludePath(fathom_dep.path("src"));
    exe.root_module.linkLibrary(fathom);

    return exe;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = buildExe(b, target, optimize);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    addReleaseStep(b);
}

const ReleaseTarget = struct {
    name: []const u8,
    triple: []const u8,
    // CPU model + feature tweaks, e.g. "x86_64_v3", "znver3", "x86_64+cx16".
    cpu: []const u8 = "baseline",
};

// One binary per line. Naming: ursus-<os>-<arch>-<tier>.
// x86-64 tiers: sse2 = runs anywhere (+cx16 for 16-byte atomics);
// v2 = +popcnt/sse4.2 (Nehalem/Jaguar and newer, big for bitboard code);
// avx2 = x86-64-v3, the mainstream tier (also what the NNUE AVX2 path wants);
// avx512 = x86-64-v4, 512-bit NNUE vectors (Zen 4/5, Intel server).
// znverN = scheduling-tuned for specific Ryzens (znver1 = 1700X, znver3 = 5950X).
// Apple Silicon: apple_m1 is default
// apple_m4 adds M4 scheduling + ISA extensions.
const release_targets = [_]ReleaseTarget{
    // Linux x86-64
    .{ .name = "ursus-linux-x86_64-sse2", .triple = "x86_64-linux-gnu", .cpu = "x86_64+cx16" },
    .{ .name = "ursus-linux-x86_64-v2", .triple = "x86_64-linux-gnu", .cpu = "x86_64_v2" },
    .{ .name = "ursus-linux-x86_64-avx2", .triple = "x86_64-linux-gnu", .cpu = "x86_64_v3" },
    .{ .name = "ursus-linux-x86_64-avx512", .triple = "x86_64-linux-gnu", .cpu = "x86_64_v4" },
    .{ .name = "ursus-linux-x86_64-znver1", .triple = "x86_64-linux-gnu", .cpu = "znver1" },
    .{ .name = "ursus-linux-x86_64-znver3", .triple = "x86_64-linux-gnu", .cpu = "znver3" },
    .{ .name = "ursus-linux-x86_64-znver5", .triple = "x86_64-linux-gnu", .cpu = "znver5" },

    // Windows x86-64
    .{ .name = "ursus-windows-x86_64-sse2.exe", .triple = "x86_64-windows-gnu", .cpu = "x86_64+cx16" },
    .{ .name = "ursus-windows-x86_64-v2.exe", .triple = "x86_64-windows-gnu", .cpu = "x86_64_v2" },
    .{ .name = "ursus-windows-x86_64-avx2.exe", .triple = "x86_64-windows-gnu", .cpu = "x86_64_v3" },
    .{ .name = "ursus-windows-x86_64-avx512.exe", .triple = "x86_64-windows-gnu", .cpu = "x86_64_v4" },
    .{ .name = "ursus-windows-x86_64-znver1.exe", .triple = "x86_64-windows-gnu", .cpu = "znver1" },
    .{ .name = "ursus-windows-x86_64-znver3.exe", .triple = "x86_64-windows-gnu", .cpu = "znver3" },
    .{ .name = "ursus-windows-x86_64-znver5.exe", .triple = "x86_64-windows-gnu", .cpu = "znver5" },

    // macOS
    .{ .name = "ursus-macos-x86_64-avx2", .triple = "x86_64-macos", .cpu = "x86_64_v3" },
    .{ .name = "ursus-macos-aarch64-m1", .triple = "aarch64-macos", .cpu = "apple_m1" },
    .{ .name = "ursus-macos-aarch64-m4", .triple = "aarch64-macos", .cpu = "apple_m4" },

    // Linux aarch64
    .{ .name = "ursus-linux-aarch64", .triple = "aarch64-linux-gnu" },
    .{ .name = "ursus-linux-aarch64-neoverse", .triple = "aarch64-linux-gnu", .cpu = "neoverse_n1" },

    // Android: static musl, no Bionic or glibc
    .{ .name = "ursus-android-aarch64", .triple = "aarch64-linux-musl" },
    .{ .name = "ursus-android-aarch64-v8.2", .triple = "aarch64-linux-musl", .cpu = "cortex_a76" },
};

pub fn addReleaseStep(b: *std.Build) void {
    const release_step = b.step("release", "Build all release binaries into zig-out/release");

    for (release_targets) |rt| {
        const query = std.Target.Query.parse(.{
            .arch_os_abi = rt.triple,
            .cpu_features = rt.cpu,
        }) catch |err| std.debug.panic("bad release target '{s}': {}", .{ rt.name, err });
        const target = b.resolveTargetQuery(query);

        const exe = buildExe(b, target, .ReleaseFast);

        const install = b.addInstallArtifact(exe, .{
            .dest_dir = .{ .override = .{ .custom = "release" } },
            .dest_sub_path = rt.name,
            .pdb_dir = .disabled,
        });
        release_step.dependOn(&install.step);
    }
}
