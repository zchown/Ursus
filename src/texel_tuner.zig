const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const fen_mod = @import("fen");
const eval = @import("eval");

// Already calibrated do not overwrite
const K: f64 = 1.0819; // Scaling constant. Calibrate first with findK().
const NUM_THREADS: usize = 0; // 0 = auto-detect CPU count
const CHUNK_SIZE: usize = 500_000;
const BATCH_SIZE: usize = 32768;
const LEARNING_RATE: f64 = 0.01;
const BETA1: f64 = 0.9;
const BETA2: f64 = 0.9;
const EPSILON: f64 = 1e-8;
const L2_LAMBDA: f64 = 0.0;
const GRAD_CLIP: f64 = 1.0;
const MAX_EPOCHS: usize = 25;
const PRINT_EVERY: usize = 1;
const CHECKPOINT_EVERY: usize = 5;

const Position = struct {
    board: brd.Board,
    result: f64, // 1.0 / 0.5 / 0.0 from white's perspective
};

/// Parse a result string — supports numeric (0.0, 0.5, 1.0) and PGN-style
/// (1-0, 0-1, 1/2-1/2) formats.
fn parseResult(s: []const u8) ?f64 {
    if (std.mem.eql(u8, s, "1-0")) return 1.0;
    if (std.mem.eql(u8, s, "0-1")) return 0.0;
    if (std.mem.eql(u8, s, "1/2-1/2")) return 0.5;
    if (std.mem.eql(u8, s, "*")) return null;
    return std.fmt.parseFloat(f64, s) catch null;
}

fn parseLine(trimmed: []const u8, skip_count: *usize) ?Position {
    if (trimmed.len == 0 or trimmed[0] == '#') return null;

    const result: f64 = blk: {
        // CHANGED: Use lastIndexOf to skip any middle elements (like eval scores)
        if (std.mem.lastIndexOf(u8, trimmed, " | ")) |sep| {
            const result_str = std.mem.trim(u8, trimmed[sep + 3 ..], " ;");
            break :blk parseResult(result_str) orelse {
                skip_count.* += 1;
                return null;
            };
        } else if (std.mem.indexOf(u8, trimmed, "[")) |lb| {
            const rb = std.mem.indexOf(u8, trimmed[lb..], "]") orelse {
                skip_count.* += 1;
                return null;
            };
            const result_str = std.mem.trim(u8, trimmed[lb + 1 .. lb + rb], " ");
            break :blk parseResult(result_str) orelse {
                skip_count.* += 1;
                return null;
            };
        } else {
            skip_count.* += 1;
            return null;
        }
    };

    const fen_end = if (std.mem.indexOf(u8, trimmed, " [")) |i|
        i
    // Keeps indexOf to grab the FEN up to the FIRST pipe
    else if (std.mem.indexOf(u8, trimmed, " | ")) |i|
        i
    else {
        skip_count.* += 1;
        return null;
    };

    const fen_str = std.mem.trim(u8, trimmed[0..fen_end], " ");

    var board = brd.Board.init();
    fen_mod.parseFEN(&board, fen_str) catch {
        skip_count.* += 1;
        return null;
    };

    return Position{ .board = board, .result = result };
}

fn readLine(reader: *std.Io.Reader, buf: []u8) error{ EndOfStream, StreamTooLong, ReadFailed }![]u8 {
    var i: usize = 0;
    while (true) {
        const slice = reader.take(1) catch |err| switch (err) {
            error.EndOfStream => {
                if (i == 0) return error.EndOfStream;
                return buf[0..i];
            },
            else => return error.ReadFailed,
        };
        const byte = slice[0];
        if (byte == '\n') return buf[0..i];
        if (i >= buf.len) return error.StreamTooLong;
        buf[i] = byte;
        i += 1;
    }
}

fn loadChunk(
    reader: *std.Io.Reader,
    line_buf: []u8,
    allocator: std.mem.Allocator,
    skip_count: *usize,
    eof_out: *bool,
) ![]Position {
    var positions = try std.ArrayList(Position).initCapacity(allocator, CHUNK_SIZE);
    errdefer positions.deinit(allocator);

    while (positions.items.len < CHUNK_SIZE) {
        const raw = readLine(reader, line_buf) catch |err| switch (err) {
            error.EndOfStream => {
                eof_out.* = true;
                break;
            },
            error.StreamTooLong => {
                skip_count.* += 1;
                continue;
            },
            error.ReadFailed => return error.Unexpected,
        };
        const trimmed = std.mem.trim(u8, raw, " \r\n");
        if (parseLine(trimmed, skip_count)) |pos| {
            try positions.append(allocator, pos);
        }
    }

    return positions.toOwnedSlice(allocator);
}

inline fn sigmoid(score: f64) f64 {
    return 1.0 / (1.0 + std.math.pow(f64, 10.0, -K * score / 400.0));
}

fn computeMSE(positions: []const Position, move_gen: *mvs.MoveGen) f64 {
    var total_error: f64 = 0.0;
    for (positions) |pos| {
        var board_copy = pos.board;
        const score: f64 = @floatFromInt(eval.evalTuner(&board_copy, move_gen));
        const predicted = sigmoid(score);
        const diff = pos.result - predicted;
        total_error += diff * diff;
    }
    return total_error / @as(f64, @floatFromInt(positions.len));
}

const GradientWork = struct {
    positions: []const Position,
    int_params_base: []const i32,
    partial_gradient: []f64,
    n_total: f64,
};

fn gradientWorker(work: *const GradientWork) void {
    var local_buf: [eval.NUM_PARAMS]i32 = undefined;
    @memcpy(&local_buf, work.int_params_base);
    eval.importParams(&local_buf);

    const ln10: f64 = @log(10.0);

    var allocator = std.heap.page_allocator;
    const mg = allocator.create(mvs.MoveGen) catch unreachable;
    mg.init();
    defer allocator.destroy(mg);


    @memset(work.partial_gradient, 0.0);

    for (work.positions) |pos| {
        // 1. Evaluate to get the score for the sigmoid
        var board_copy = pos.board;
        const score: f64 = @floatFromInt(eval.evalTuner(&board_copy, mg));
        const sig = sigmoid(score);
        const err: f64 = pos.result - sig;
        const common: f64 = (-2.0 / work.n_total) * err * sig * (1.0 - sig) * K * ln10 / 400.0;

        if (@abs(common) < 1e-12) continue;

        // 2. Extract coefficient vector (analytical d(eval)/d(param[i]))
        board_copy = pos.board;
        const coeffs = eval.computeCoefficients(&board_copy, mg);

        // 3. Accumulate gradient
        for (0..eval.NUM_PARAMS) |i| {
            work.partial_gradient[i] += common * coeffs[i];
        }
    }
}

fn findK(positions: []const Position, move_gen: *mvs.MoveGen) f64 {
    var stderr_buf: [512]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

    _ = stderr.print("Calibrating K...\n", .{}) catch {};

    var lo: f64 = 0.01;
    var hi: f64 = 3.0;

    for (0..100) |_| {
        const m1 = lo + (hi - lo) / 3.0;
        const m2 = hi - (hi - lo) / 3.0;

        K = m1;
        const mse1 = computeMSE(positions, move_gen);
        K = m2;
        const mse2 = computeMSE(positions, move_gen);

        if (mse1 < mse2) {
            hi = m2;
        } else {
            lo = m1;
        }
    }

    const best_k = (lo + hi) / 2.0;
    K = best_k;

    _ = stderr.print("Optimal K found: {d:.4}\n", .{best_k}) catch {};
    stderr.flush() catch {};
    return best_k;
}

fn computeGradientBatch(
    positions: []const Position,
    int_params: []i32,
    gradient: []f64,
    allocator: std.mem.Allocator,
) !void {
    const n_threads: usize = if (NUM_THREADS > 0)
        NUM_THREADS
    else
        std.Thread.getCpuCount() catch 4;

    const actual_threads = @min(n_threads, positions.len);

    const partial_grads = try allocator.alloc([]f64, actual_threads);
    defer allocator.free(partial_grads);
    for (partial_grads) |*pg| {
        pg.* = try allocator.alloc(f64, eval.NUM_PARAMS);
    }
    defer for (partial_grads) |pg| allocator.free(pg);

    // Build work items
    const work_items = try allocator.alloc(GradientWork, actual_threads);
    defer allocator.free(work_items);

    const chunk = positions.len / actual_threads;
    const n_total: f64 = @floatFromInt(positions.len);
    for (0..actual_threads) |t| {
        const start = t * chunk;
        const end = if (t == actual_threads - 1) positions.len else start + chunk;
        work_items[t] = .{
            .positions = positions[start..end],
            .int_params_base = int_params,
            .partial_gradient = partial_grads[t],
            .n_total = n_total,
        };
    }

    // Spawn threads
    const threads = try allocator.alloc(std.Thread, actual_threads - 1);
    defer allocator.free(threads);

    for (0..actual_threads - 1) |t| {
        threads[t] = try std.Thread.spawn(.{}, gradientWorker, .{&work_items[t]});
    }
    gradientWorker(&work_items[actual_threads - 1]);

    for (threads) |th| th.join();

    // Reduce partial gradients
    @memset(gradient, 0.0);
    for (partial_grads) |pg| {
        for (0..eval.NUM_PARAMS) |i| gradient[i] += pg[i];
    }

    // Restore the main thread's eval globals
    eval.importParams(int_params);
}

const Adam = struct {
    m: []f64,
    v: []f64,
    t: u64 = 0,

    fn init(allocator: std.mem.Allocator) !Adam {
        const m = try allocator.alloc(f64, eval.NUM_PARAMS);
        const v = try allocator.alloc(f64, eval.NUM_PARAMS);
        @memset(m, 0.0);
        @memset(v, 0.0);
        return Adam{ .m = m, .v = v };
    }

    fn deinit(self: *Adam, allocator: std.mem.Allocator) void {
        allocator.free(self.m);
        allocator.free(self.v);
    }

    fn step(self: *Adam, params: []f64, gradient: []const f64) void {
        self.t += 1;
        const t: f64 = @floatFromInt(self.t);
        const lr_t = LEARNING_RATE * @sqrt(1.0 - std.math.pow(f64, BETA2, t)) /
            (1.0 - std.math.pow(f64, BETA1, t));

        for (0..eval.NUM_PARAMS) |i| {
            // L2 regularization: add lambda * param to gradient
            var g = gradient[i] + L2_LAMBDA * params[i];
            // Gradient clipping
            g = std.math.clamp(g, -GRAD_CLIP, GRAD_CLIP);

            self.m[i] = BETA1 * self.m[i] + (1.0 - BETA1) * g;
            self.v[i] = BETA2 * self.v[i] + (1.0 - BETA2) * g * g;
            params[i] -= lr_t * self.m[i] / (@sqrt(self.v[i]) + EPSILON);
        }

        // Enforce mobility monotonicity: mobility[i] <= mobility[i+1]
        enforceMobilityMonotonicity(params);
    }
};

/// Enforce monotonicity on mobility tables: each entry must be >= the previous.
/// This prevents non-monotonic mobility curves from overfitting rare positions.
fn enforceMobilityMonotonicity(params: []f64) void {
    const tables = [_]struct { off: usize, len: usize }{
        .{ .off = eval.P_MG_KNIGHT_MOB, .len = 9 },
        .{ .off = eval.P_MG_BISHOP_MOB, .len = 14 },
        .{ .off = eval.P_MG_ROOK_MOB, .len = 15 },
        .{ .off = eval.P_MG_QUEEN_MOB, .len = 28 },
        .{ .off = eval.P_EG_KNIGHT_MOB, .len = 9 },
        .{ .off = eval.P_EG_BISHOP_MOB, .len = 14 },
        .{ .off = eval.P_EG_ROOK_MOB, .len = 15 },
        .{ .off = eval.P_EG_QUEEN_MOB, .len = 28 },
    };
    for (tables) |tbl| {
        var i: usize = 1;
        while (i < tbl.len) : (i += 1) {
            if (params[tbl.off + i] < params[tbl.off + i - 1]) {
                // Average the two to maintain smoothness
                const avg = (params[tbl.off + i] + params[tbl.off + i - 1]) / 2.0;
                params[tbl.off + i] = avg;
                params[tbl.off + i - 1] = avg;
            }
        }
    }
}

fn printParams(int_params: []const i32, writer: anytype) !void {
    try writer.print("\n// ===== Tuned parameters — paste into eval.zig =====\n", .{});

    // Piece values
    try writer.print("pub var mg_pawn: i32 = {};\n", .{int_params[eval.P_MG_PAWN]});
    try writer.print("pub var eg_pawn: i32 = {};\n", .{int_params[eval.P_EG_PAWN]});
    try writer.print("pub var mg_knight: i32 = {};\n", .{int_params[eval.P_MG_KNIGHT]});
    try writer.print("pub var eg_knight: i32 = {};\n", .{int_params[eval.P_EG_KNIGHT]});
    try writer.print("pub var mg_bishop: i32 = {};\n", .{int_params[eval.P_MG_BISHOP]});
    try writer.print("pub var eg_bishop: i32 = {};\n", .{int_params[eval.P_EG_BISHOP]});
    try writer.print("pub var mg_rook: i32 = {};\n", .{int_params[eval.P_MG_ROOK]});
    try writer.print("pub var eg_rook: i32 = {};\n", .{int_params[eval.P_EG_ROOK]});
    try writer.print("pub var mg_queen: i32 = {};\n", .{int_params[eval.P_MG_QUEEN]});
    try writer.print("pub var eg_queen: i32 = {};\n", .{int_params[eval.P_EG_QUEEN]});
    try writer.print("pub var mg_king: i32 = {};\n", .{int_params[eval.P_MG_KING]});
    try writer.print("pub var eg_king: i32 = {};\n", .{int_params[eval.P_EG_KING]});

    // PST tables
    const pst_names = [12][]const u8{
        "mg_pawn_table",   "eg_pawn_table",
        "mg_knight_table", "eg_knight_table",
        "mg_bishop_table", "eg_bishop_table",
        "mg_rook_table",   "eg_rook_table",
        "mg_queen_table",  "eg_queen_table",
        "mg_king_table",   "eg_king_table",
    };
    const pst_offsets = [12]usize{
        eval.P_MG_PAWN_TABLE,   eval.P_EG_PAWN_TABLE,
        eval.P_MG_KNIGHT_TABLE, eval.P_EG_KNIGHT_TABLE,
        eval.P_MG_BISHOP_TABLE, eval.P_EG_BISHOP_TABLE,
        eval.P_MG_ROOK_TABLE,   eval.P_EG_ROOK_TABLE,
        eval.P_MG_QUEEN_TABLE,  eval.P_EG_QUEEN_TABLE,
        eval.P_MG_KING_TABLE,   eval.P_EG_KING_TABLE,
    };
    for (pst_names, pst_offsets) |name, off| {
        try writer.print("pub var {s} = [64]i32{{\n", .{name});
        for (0..8) |rank| {
            try writer.print("    ", .{});
            for (0..8) |file| {
                try writer.print("{:5},", .{int_params[off + rank * 8 + file]});
            }
            try writer.print("\n", .{});
        }
        try writer.print("}};\n", .{});
    }

    // Mobility tables — mg/eg split
    const mob_names = [_][]const u8{
        "mg_knight_mobility", "mg_bishop_mobility", "mg_rook_mobility", "mg_queen_mobility",
        "eg_knight_mobility", "eg_bishop_mobility", "eg_rook_mobility", "eg_queen_mobility",
    };
    const mob_offsets = [_]usize{
        eval.P_MG_KNIGHT_MOB, eval.P_MG_BISHOP_MOB, eval.P_MG_ROOK_MOB, eval.P_MG_QUEEN_MOB,
        eval.P_EG_KNIGHT_MOB, eval.P_EG_BISHOP_MOB, eval.P_EG_ROOK_MOB, eval.P_EG_QUEEN_MOB,
    };
    const mob_sizes = [_]usize{ 9, 14, 15, 28, 9, 14, 15, 28 };
    for (mob_names, mob_offsets, mob_sizes) |name, off, sz| {
        try writer.print("pub var {s} = [{}]i32{{", .{ name, sz });
        for (0..sz) |i| try writer.print(" {},", .{int_params[off + i]});
        try writer.print(" }};\n", .{});
    }

    // Passed pawn tables
    try writer.print("pub var mg_passed_bonus = [8]i32{{", .{});
    for (0..8) |i| try writer.print(" {},", .{int_params[eval.P_MG_PASSED + i]});
    try writer.print(" }};\n", .{});

    try writer.print("pub var passed_pawn_bonus = [8]i32{{", .{});
    for (0..8) |i| try writer.print(" {},", .{int_params[eval.P_EG_PASSED + i]});
    try writer.print(" }};\n", .{});

    // King safety — quadratic model
    try writer.print("pub var safety_quadratic_a: i32 = {};\n", .{int_params[eval.P_SAFETY_QUAD_A]});
    try writer.print("pub var safety_quadratic_b: i32 = {};\n", .{int_params[eval.P_SAFETY_QUAD_B]});

    // Per-piece king zone attack weights (mg-only)
    const king_atk_names = [_][]const u8{
        "mg_knight_king_atk",
        "mg_bishop_king_atk",
        "mg_rook_king_atk",
        "mg_queen_king_atk",
    };
    const king_atk_offsets = [_]usize{
        eval.P_MG_KNIGHT_KING_ATK,
        eval.P_MG_BISHOP_KING_ATK,
        eval.P_MG_ROOK_KING_ATK,
        eval.P_MG_QUEEN_KING_ATK,
    };
    for (king_atk_names, king_atk_offsets) |name, off| {
        try writer.print("pub var {s}: i32 = {};\n", .{ name, int_params[off] });
    }

    // King safety scalars (mg-only)
    try writer.print("pub var castled_bonus: i32 = {};\n", .{int_params[eval.P_CASTLED_BONUS]});
    try writer.print("pub var pawn_shield_bonus: i32 = {};\n", .{int_params[eval.P_PAWN_SHIELD_BONUS]});
    try writer.print("pub var open_file_penalty: i32 = {};\n", .{int_params[eval.P_OPEN_FILE_PENALTY]});
    try writer.print("pub var semi_open_penalty: i32 = {};\n", .{int_params[eval.P_SEMI_OPEN_PENALTY]});

    // Split scalar bonuses — mg/eg pairs
    const split_names = [_][]const u8{
        "mg_protected_pawn",     "eg_protected_pawn",
        "mg_doubled_pawn",       "eg_doubled_pawn",
        "mg_isolated_pawn",      "eg_isolated_pawn",
        "mg_rook_open_file",     "eg_rook_open_file",
        "mg_rook_semi_open",     "eg_rook_semi_open",
        "mg_minor_threat",       "eg_minor_threat",
        "mg_rook_threat",        "eg_rook_threat",
        "mg_queen_threat",       "eg_queen_threat",
        "mg_rook_on_queen",      "eg_rook_on_queen",
        "mg_rook_on_king",       "eg_rook_on_king",
        "mg_queen_on_king",      "eg_queen_on_king",
        "mg_bad_bishop",         "eg_bad_bishop",
        "mg_bishop_on_queen",    "eg_bishop_on_queen",
        "mg_bishop_on_king",     "eg_bishop_on_king",
        "mg_hanging_piece",      "eg_hanging_piece",
        "mg_atk_by_pawn",        "eg_atk_by_pawn",
        "mg_atk_by_minor",       "eg_atk_by_minor",
        "mg_atk_by_rook",        "eg_atk_by_rook",
        "mg_defended_by_pawn",   "eg_defended_by_pawn",
        "mg_knight_outpost",     "eg_knight_outpost",
        "mg_bishop_pair",        "eg_bishop_pair",
        "mg_space_per_sq",       "eg_space_per_sq",
        "mg_center_ctrl",        "eg_center_ctrl",
        "mg_extended_center",    "eg_extended_center",
        "mg_exchange_avoidance", "eg_exchange_avoidance",
    };
    const split_offsets = [_]usize{
        eval.P_MG_PROTECTED_PAWN,     eval.P_EG_PROTECTED_PAWN,
        eval.P_MG_DOUBLED_PAWN,       eval.P_EG_DOUBLED_PAWN,
        eval.P_MG_ISOLATED_PAWN,      eval.P_EG_ISOLATED_PAWN,
        eval.P_MG_ROOK_OPEN_FILE,     eval.P_EG_ROOK_OPEN_FILE,
        eval.P_MG_ROOK_SEMI_OPEN,     eval.P_EG_ROOK_SEMI_OPEN,
        eval.P_MG_MINOR_THREAT,       eval.P_EG_MINOR_THREAT,
        eval.P_MG_ROOK_THREAT,        eval.P_EG_ROOK_THREAT,
        eval.P_MG_QUEEN_THREAT,       eval.P_EG_QUEEN_THREAT,
        eval.P_MG_ROOK_ON_QUEEN,      eval.P_EG_ROOK_ON_QUEEN,
        eval.P_MG_ROOK_ON_KING,       eval.P_EG_ROOK_ON_KING,
        eval.P_MG_QUEEN_ON_KING,      eval.P_EG_QUEEN_ON_KING,
        eval.P_MG_BAD_BISHOP,         eval.P_EG_BAD_BISHOP,
        eval.P_MG_BISHOP_ON_QUEEN,    eval.P_EG_BISHOP_ON_QUEEN,
        eval.P_MG_BISHOP_ON_KING,     eval.P_EG_BISHOP_ON_KING,
        eval.P_MG_HANGING_PIECE,      eval.P_EG_HANGING_PIECE,
        eval.P_MG_ATK_BY_PAWN,        eval.P_EG_ATK_BY_PAWN,
        eval.P_MG_ATK_BY_MINOR,       eval.P_EG_ATK_BY_MINOR,
        eval.P_MG_ATK_BY_ROOK,        eval.P_EG_ATK_BY_ROOK,
        eval.P_MG_DEFENDED_BY_PAWN,   eval.P_EG_DEFENDED_BY_PAWN,
        eval.P_MG_KNIGHT_OUTPOST,     eval.P_EG_KNIGHT_OUTPOST,
        eval.P_MG_BISHOP_PAIR,        eval.P_EG_BISHOP_PAIR,
        eval.P_MG_SPACE_PER_SQ,       eval.P_EG_SPACE_PER_SQ,
        eval.P_MG_CENTER_CTRL,        eval.P_EG_CENTER_CTRL,
        eval.P_MG_EXTENDED_CENTER,    eval.P_EG_EXTENDED_CENTER,
        eval.P_MG_EXCHANGE_AVOIDANCE, eval.P_EG_EXCHANGE_AVOIDANCE,
    };
    for (split_names, split_offsets) |name, off| {
        try writer.print("pub var {s}: i32 = {};\n", .{ name, int_params[off] });
    }

    // Per-piece-type trapped piece penalties (mg/eg)
    const trapped_names = [_][]const u8{
        "mg_trapped_knight", "eg_trapped_knight",
        "mg_trapped_bishop", "eg_trapped_bishop",
        "mg_trapped_rook",   "eg_trapped_rook",
    };
    const trapped_offsets = [_]usize{
        eval.P_MG_TRAPPED_KNIGHT, eval.P_EG_TRAPPED_KNIGHT,
        eval.P_MG_TRAPPED_BISHOP, eval.P_EG_TRAPPED_BISHOP,
        eval.P_MG_TRAPPED_ROOK,   eval.P_EG_TRAPPED_ROOK,
    };
    for (trapped_names, trapped_offsets) |name, off| {
        try writer.print("pub var {s}: i32 = {};\n", .{ name, int_params[off] });
    }

    // Remaining single-phase params
    const remaining_names = [_][]const u8{
        "rook_on_7th_bonus",          "rook_behind_passer_bonus",
        "king_pawn_proximity",        "king_far_pawn_penalty",
        "king_centralization_weight", "mopup_edge_weight",
        "mopup_proximity_weight",     "rule_of_square_bonus",
        "pawn_storm_weight",          "king_zone_attack_weight",
        "king_defender_bonus",        "tempo_bonus",
        "mg_pawn_advance_space",      "eg_pawn_advance_space",
    };
    const remaining_offsets = [_]usize{
        eval.P_ROOK_7TH_BONUS,        eval.P_ROOK_PASSER_BONUS,
        eval.P_KING_PAWN_PROXIMITY,   eval.P_KING_FAR_PAWN,
        eval.P_KING_CENTRALIZATION,   eval.P_MOPUP_EDGE,
        eval.P_MOPUP_PROXIMITY,       eval.P_RULE_OF_SQUARE,
        eval.P_PAWN_STORM,            eval.P_KING_ZONE_ATTACK,
        eval.P_KING_DEFENDER,         eval.P_TEMPO_BONUS,
        eval.P_MG_PAWN_ADVANCE_SPACE, eval.P_EG_PAWN_ADVANCE_SPACE,
    };
    for (remaining_names, remaining_offsets) |name, off| {
        try writer.print("pub var {s}: i32 = {};\n", .{ name, int_params[off] });
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        var usage_buf: [512]u8 = undefined;
        var usage_writer = std.fs.File.stderr().writer(&usage_buf);
        const usage_err = &usage_writer.interface;
        try usage_err.print(
            \\Usage: texel_tuner <positions_file> [checkpoints/checkpoint.bin]
            \\
            \\Position file format (one per line):
            \\  <FEN> | <r>
            \\  e.g. rnbqkbnr/pppppppp/... b KQkq - 0 1 | 0.5
            \\
            \\result: 1.0=white win, 0.5=draw, 0.0=black win
            \\
        , .{});
        try usage_err.flush();
        return;
    }

    const move_gen = try allocator.create(mvs.MoveGen);
    move_gen.init();
    defer allocator.destroy(move_gen);


    var stderr_buf: [512]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

    var int_params = try allocator.alloc(i32, eval.NUM_PARAMS);
    defer allocator.free(int_params);
    eval.exportParams(int_params);

    var float_params = try allocator.alloc(f64, eval.NUM_PARAMS);
    defer allocator.free(float_params);
    for (0..eval.NUM_PARAMS) |i| float_params[i] = @floatFromInt(int_params[i]);

    if (args.len >= 3) {
        try stderr.print("Loading checkpoint from '{s}'...\n", .{args[2]});
        try stderr.flush();
        const checkpoint = try std.fs.cwd().openFile(args[2], .{});
        defer checkpoint.close();
        _ = try checkpoint.readAll(std.mem.sliceAsBytes(int_params));
        eval.importParams(int_params);
        for (0..eval.NUM_PARAMS) |i| float_params[i] = @floatFromInt(int_params[i]);
        try stderr.print("Checkpoint loaded.\n", .{});
        try stderr.flush();
    }

    var adam = try Adam.init(allocator);
    defer adam.deinit(allocator);

    const gradient = try allocator.alloc(f64, eval.NUM_PARAMS);
    defer allocator.free(gradient);

    var line_buf: [1024]u8 = undefined;

    // Calibrate K on first chunk
    // {
    //     try stderr.print("Running initial calibration...\n", .{});
    //     try stderr.flush();
    //
    //     const calib_file = try std.fs.cwd().openFile(args[1], .{});
    //     defer calib_file.close();
    //
    //     var calib_read_buf: [65536]u8 = undefined;
    //     var calib_file_reader = calib_file.reader(&calib_read_buf);
    //     const calib_reader: *std.Io.Reader = &calib_file_reader.interface;
    //
    //     var calib_eof = false;
    //     var calib_skip: usize = 0;
    //     const calib_chunk = try loadChunk(calib_reader, &line_buf, allocator, &calib_skip, &calib_eof);
    //     defer allocator.free(calib_chunk);
    //
    //     if (calib_chunk.len > 0) {
    //         _ = findK(calib_chunk, &move_gen);
    //     }
    // }

    var rng = std.Random.DefaultPrng.init(42);
    const rand = rng.random();

    std.fs.cwd().makeDir("checkpoints") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    try stderr.print("Starting Adam tuning: {} params, CHUNK_SIZE={}, lr={d}\n", .{
        eval.NUM_PARAMS, CHUNK_SIZE, LEARNING_RATE,
    });
    try stderr.flush();

    var epoch: usize = 0;
    while (epoch < MAX_EPOCHS) : (epoch += 1) {
        const file = try std.fs.cwd().openFile(args[1], .{});
        defer file.close();
        var read_buf: [65536]u8 = undefined;
        var file_reader = file.reader(&read_buf);
        const reader: *std.Io.Reader = &file_reader.interface;

        var skip_count: usize = 0;
        var total_loaded: usize = 0;
        var chunk_index: usize = 0;
        var epoch_mse_sum: f64 = 0.0;
        var epoch_mse_count: usize = 0;

        while (true) {
            var eof = false;
            const chunk = try loadChunk(reader, &line_buf, allocator, &skip_count, &eof);
            defer allocator.free(chunk);

            if (chunk.len == 0) {
                break;
            }

            total_loaded += chunk.len;
            chunk_index += 1;

            try stderr.print("  Epoch {} chunk {}: {} positions ({} total)\n", .{
                epoch + 1, chunk_index, chunk.len, total_loaded,
            });
            try stderr.flush();

            for (0..chunk.len) |i| {
                const j = rand.intRangeAtMost(usize, i, chunk.len - 1);
                const tmp = chunk[i];
                chunk[i] = chunk[j];
                chunk[j] = tmp;
            }

            var batch_start: usize = 0;
            while (batch_start < chunk.len) : (batch_start += BATCH_SIZE) {
                const batch_end = @min(batch_start + BATCH_SIZE, chunk.len);
                const batch = chunk[batch_start..batch_end];

                for (0..eval.NUM_PARAMS) |i| {
                    const v = @round(float_params[i]);
                    int_params[i] = if (std.math.isFinite(v)) @intFromFloat(v) else 0;
                }
                eval.importParams(int_params);

                try computeGradientBatch(batch, int_params, gradient, allocator);
                adam.step(float_params, gradient);
            }

            if ((epoch + 1) % PRINT_EVERY == 0) {
                for (0..eval.NUM_PARAMS) |i| {
                    const v = @round(float_params[i]);
                    int_params[i] = if (std.math.isFinite(v)) @intFromFloat(v) else 0;
                }
                eval.importParams(int_params);
                epoch_mse_sum += computeMSE(chunk, move_gen) * @as(f64, @floatFromInt(chunk.len));
                epoch_mse_count += chunk.len;
            }

            if (eof) break;
        }

        if ((epoch + 1) % PRINT_EVERY == 0 and epoch_mse_count > 0) {
            const mse = epoch_mse_sum / @as(f64, @floatFromInt(epoch_mse_count));
            try stderr.print("Epoch {}: MSE = {d:.6} ({} positions, {} skipped)\n", .{
                epoch + 1, mse, total_loaded, skip_count,
            });
            try stderr.flush();
        }

        if ((epoch + 1) % CHECKPOINT_EVERY == 0) {
            for (0..eval.NUM_PARAMS) |i| {
                const v = @round(float_params[i]);
                int_params[i] = if (std.math.isFinite(v)) @intFromFloat(v) else 0;
            }

            var fname_buf: [64]u8 = undefined;
            const fname = try std.fmt.bufPrint(&fname_buf, "checkpoints/checkpoint_{}.bin", .{epoch + 1});
            const f = try std.fs.cwd().createFile(fname, .{});
            defer f.close();
            try f.writeAll(std.mem.sliceAsBytes(int_params));
            try stderr.print("  Saved checkpoint: {s}\n", .{fname});
            try stderr.flush();
        }

        try stderr.print("  Shuffling input file in place...\n", .{});
        try stderr.flush();

        const shuf_args = &[_][]const u8{ "shuf", "-o", args[1], args[1] };
        const shuf_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = shuf_args,
        });

        allocator.free(shuf_result.stdout);
        allocator.free(shuf_result.stderr);

        try stderr.print("  Shuffle complete.\n", .{});
        try stderr.flush();
    }

    for (0..eval.NUM_PARAMS) |i| {
        const v = @round(float_params[i]);
        int_params[i] = if (std.math.isFinite(v)) @intFromFloat(v) else 0;
    }
    eval.importParams(int_params);

    try stderr.print("\nTuning complete. Printing Zig declarations to stdout...\n", .{});
    try stderr.flush();

    var stdout_buf: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    try printParams(int_params, stdout);
    try stdout.flush();
}

