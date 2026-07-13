const std = @import("std");

fn buildExe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
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

    const see_module = b.createModule(.{
        .root_source_file = b.path("src/engine/see.zig"),
        .target = target,
        .optimize = optimize,
    });

    const pawn_tt_module = b.createModule(.{
        .root_source_file = b.path("src/engine/pawn_tt.zig"),
        .target = target,
        .optimize = optimize,
    });

    const datagen_module = b.createModule(.{
        .root_source_file = b.path("src/nnue/datagen.zig"),
        .target = target,
        .optimize = optimize,
    });

    const nnue_module = b.createModule(.{
        .root_source_file = b.path("src/nnue/nnue.zig"),
        .target = target,
        .optimize = optimize,
    });

    const move_picker = b.createModule(.{
        .root_source_file = b.path("src/engine/move_picker.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tunable_parameters_module = b.createModule(.{
        .root_source_file = b.path("src/engine/tunable_parameters.zig"),
        .target = target,
        .optimize = optimize,
    });

    const history_module = b.createModule(.{
        .root_source_file = b.path("src/engine/history.zig"),
        .target = target,
        .optimize = optimize,
    });

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
    // exe.root_module.omit_frame_pointer = false;
    // exe.root_module.strip = false;

    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);

    board_module.addImport("zobrist", zobrist_module);
    board_module.addImport("moves", moves_module);
    board_module.addImport("nnue", nnue_module);

    perft_module.addImport("board", board_module);
    perft_module.addImport("moves", moves_module);
    perft_module.addImport("fen", fen_module);

    fen_module.addImport("board", board_module);
    fen_module.addImport("zobrist", zobrist_module);

    moves_module.addImport("board", board_module);
    moves_module.addImport("magic", magic_module);
    moves_module.addImport("radagast", radagast_module);
    moves_module.addImport("nnue", nnue_module);

    zobrist_module.addImport("board", board_module);

    radagast_module.addImport("board", board_module);

    search_module.addImport("board", board_module);
    search_module.addImport("moves", moves_module);
    search_module.addImport("eval", eval_module);
    search_module.addImport("transposition", transposition_module);
    search_module.addImport("see", see_module);
    search_module.addImport("pawn_tt", pawn_tt_module);
    search_module.addImport("move_picker", move_picker);
    search_module.addImport("tunable_parameters", tunable_parameters_module);
    search_module.addImport("history", history_module);

    history_module.addImport("board", board_module);
    history_module.addImport("moves", moves_module);
    history_module.addImport("eval", eval_module);
    history_module.addImport("search", search_module);
    history_module.addImport("tunable_parameters", tunable_parameters_module);

    move_picker.addImport("board", board_module);
    move_picker.addImport("moves", moves_module);
    move_picker.addImport("see", see_module);
    move_picker.addImport("search", search_module);

    transposition_module.addImport("board", board_module);
    transposition_module.addImport("zobrist", zobrist_module);
    transposition_module.addImport("moves", moves_module);

    pawn_tt_module.addImport("zobrist", zobrist_module);

    uci_module.addImport("board", board_module);
    uci_module.addImport("search", search_module);
    uci_module.addImport("fen", fen_module);
    uci_module.addImport("transposition", transposition_module);
    uci_module.addImport("moves", moves_module);
    uci_module.addImport("eval", eval_module);
    uci_module.addImport("pawn_tt", pawn_tt_module);
    uci_module.addImport("datagen", datagen_module);
    uci_module.addImport("nnue", nnue_module);
    uci_module.addImport("tunable_parameters", tunable_parameters_module);
    uci_module.addImport("perft", perft_module);

    eval_module.addImport("board", board_module);
    eval_module.addImport("moves", moves_module);
    eval_module.addImport("pawn_tt", pawn_tt_module);
    eval_module.addImport("zobrist", zobrist_module);

    see_module.addImport("board", board_module);
    see_module.addImport("moves", moves_module);

    datagen_module.addImport("board", board_module);
    datagen_module.addImport("moves", moves_module);
    datagen_module.addImport("fen", fen_module);
    datagen_module.addImport("search", search_module);
    datagen_module.addImport("eval", eval_module);
    datagen_module.addImport("pawn_tt", pawn_tt_module);
    datagen_module.addImport("transposition", transposition_module);
    datagen_module.addImport("history", history_module);

    nnue_module.addImport("board", board_module);
    nnue_module.addImport("moves", moves_module);

    exe.root_module.addImport("uci", uci_module);
    exe.root_module.addImport("perft", perft_module);
    exe.root_module.addImport("datagen", datagen_module);

    const fathom_dep = b.dependency("fathom", .{});

    const fathom_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    fathom_mod.addCSourceFile(.{
        .file = fathom_dep.path("src/tbprobe.c"),
        .flags = &.{ "-std=c11", "-O3", "-DNDEBUG" },
    });
    fathom_mod.addIncludePath(fathom_dep.path("src"));

    const fathom = b.addLibrary(.{
        .name = "fathom",
        .linkage = .static,
        .root_module = fathom_mod,
    });

    const tb_mod = b.createModule(.{
        .root_source_file = b.path("src/engine/tb.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tb_mod.addIncludePath(fathom_dep.path("src"));
    tb_mod.linkLibrary(fathom);
    tb_mod.addImport("board", board_module);
    tb_mod.addImport("moves", moves_module);

    search_module.addImport("tb", tb_mod);
    uci_module.addImport("tb", tb_mod);

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
