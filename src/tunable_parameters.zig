const std = @import("std");

pub const max_ply = 128;
pub const max_game_ply = 1024;

// Just a convenient place to put this not a tunable
pub var tb_probe_depth: usize = 1;

// not SPSA tunable
pub const rfp_depth: i32 = 6;
pub const se_min_depth: usize = 7;
pub const lmr_pv_min = 3;
pub const lmr_non_pv_min = 1;
pub const hindsight_ext_min_red: i32 = 3;
pub const hindsight_red_min_red: i32 = 2;
pub const low_ply_size = 5;

pub const Hook = enum { none, quiet_lmr, noisy_lmr };

pub const Value = union(enum) {
    int: *i32,
    size: *usize,
    count: *u64,
};

pub inline fn pct(v: anytype) f32 {
    return @as(f32, @floatFromInt(v)) / 100.0;
}

pub const Spec = struct {
    min: f64,
    max: f64,
    c_end: ?f64 = null,
    r_end: f64 = 0.002,
    hook: Hook = .none,
};

pub fn Tunable(comptime T: type, comptime spec: Spec) type {
    return struct {
        value: T,
        pub const meta = spec;
    };
}

pub fn TunableArray(comptime T: type, comptime specs: []const Spec) type {
    return struct {
        values: [specs.len]T,
        pub const metas = specs;
    };
}

pub var see_values = TunableArray(i32, &.{
    .{ .min = 0, .max = 200 },
    .{ .min = 0, .max = 400 },
    .{ .min = 0, .max = 600 },
    .{ .min = 0, .max = 800 },
    .{ .min = 0, .max = 1000 },
    .{ .min = 20000, .max = 20000 },
    .{ .min = 0, .max = 0},
}){ .values = .{ 93, 308, 346, 521, 994, 20000, 0} };

pub var aspiration_window = Tunable(i32, .{ .min = 8, .max = 80 }){ .value = 32 };
pub var asp_score_div = Tunable(i32, .{ .min = 5000, .max = 40000 }){ .value = 13000 };
pub var asp_growth = Tunable(i32, .{ .min = 20, .max = 100 }){ .value = 50 };

pub var rfp_mul = Tunable(i32, .{ .min = 15, .max = 120 }){ .value = 45 };
pub var rfp_improve = Tunable(i32, .{ .min = 15, .max = 130 }){ .value = 52 };

pub var nmp_improve = Tunable(i32, .{ .min = 0, .max = 80 }){ .value = 19 };
pub var nmp_base = Tunable(usize, .{ .min = 2, .max = 5, .c_end = 0.5 }){ .value = 3 };
pub var nmp_depth_div = Tunable(usize, .{ .min = 2, .max = 8, .c_end = 0.5 }){ .value = 3 };
pub var nmp_beta_div = Tunable(usize, .{ .min = 50, .max = 300 }){ .value = 129 };

pub var razoring_base = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 282 };
pub var razoring_mul = Tunable(i32, .{ .min = 20, .max = 180 }){ .value = 61 };

pub var lmp_base = Tunable(usize, .{ .min = 100, .max = 800 }){ .value = 300 };
pub var lmp_mul = Tunable(usize, .{ .min = 30, .max = 200 }){ .value = 100 };

pub var futility_base = Tunable(i32, .{ .min = 0, .max = 300 }){ .value = 100 };
pub var futility_mul = Tunable(i32, .{ .min = 50, .max = 300 }){ .value = 120 };
pub var futility_hist_div = Tunable(i32, .{ .min = 32, .max = 512 }){ .value = 128 };

pub var see_quiet_mul = Tunable(i32, .{ .min = 5, .max = 60 }){ .value = 25 };

pub var q_see_min = Tunable(i32, .{ .min = -300, .max = 0 }){ .value = -25 };
pub var q_fut_margin = Tunable(i32, .{ .min = 10, .max = 600 }){ .value = 400 };
pub var q_delta_margin = Tunable(i32, .{ .min = 50, .max = 500 }){ .value = 213 };

pub var lmr_base = Tunable(i32, .{ .min = 40, .max = 180, .hook = .quiet_lmr }){ .value = 90 };
pub var lmr_div = Tunable(i32, .{ .min = 100, .max = 350, .hook = .quiet_lmr }){ .value = 176 };

pub var lmr_noisy_base = Tunable(i32, .{ .min = -100, .max = 80, .hook = .noisy_lmr }){ .value = -13 };
pub var lmr_noisy_div = Tunable(i32, .{ .min = 150, .max = 600, .hook = .noisy_lmr }){ .value = 332 };

pub var se_margin = Tunable(i32, .{ .min = 50, .max = 500}){ .value = 100 };
pub var se_double_margin = Tunable(i32, .{ .min = 0, .max = 100 }){ .value = 50 };

pub var history_div = Tunable(i32, .{ .min = 2048, .max = 8192 }){ .value = 4098 };
pub var history_prune_mult = Tunable(i32, .{ .min = 512, .max = 8192 }){ .value = 1536 };

pub var stat_main_weight = Tunable(i32, .{ .min = 128, .max = 2048}){ .value = 1024};
pub var stat_cont1_weight = Tunable(i32, .{ .min = 128, .max = 2048}){ .value = 512};
pub var stat_cont2_weight = Tunable(i32, .{ .min = 128, .max = 2048}){ .value = 512};
pub var stat_cont4_weight = Tunable(i32, .{ .min = 128, .max = 2048}){ .value = 256};

pub var corr_div_bm = Tunable(i32, .{ .min = 4, .max = 24, .c_end = 1.0 }){ .value = 10 };
pub var corr_div_nobm = Tunable(i32, .{ .min = 4, .max = 24, .c_end = 1.0 }){ .value = 9 };
pub var corr_np_update_weight = Tunable(i32, .{ .min = 64, .max = 384 }){ .value = 181 };

pub var corr_pawn_read_weight = Tunable(i32, .{ .min = 64, .max = 400 }){ .value = 201 };
pub var corr_np_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 125 };
pub var corr_major_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 119 };
pub var corr_minor_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 117 };
pub var corr_cont_read_weight = Tunable(i32, .{ .min = 0, .max = 320 }){ .value = 120 };

pub var corr_read_divisor = Tunable(i32, .{ .min = 1024, .max = 12288 }){ .value = 3072 };
pub var corr_limit = Tunable(i32, .{ .min = 128, .max = 4096 }){ .value = 1024 };

pub var probcut_margin = Tunable(i32, .{ .min = 100, .max = 500 }){ .value = 259 };
pub var probcut_improve = Tunable(i32, .{ .min = 400, .max = 2000 }){ .value = 1046 };
pub var probcut_min_see = Tunable(i32, .{ .min = 0, .max = 500 }){ .value = 206 };

pub var tm_stability_scale = TunableArray(i32, &.{
    .{ .min = 100, .max = 250 },
    .{ .min = 90, .max = 200 },
    .{ .min = 80, .max = 180 },
    .{ .min = 70, .max = 160 },
    .{ .min = 60, .max = 150 },
    .{ .min = 55, .max = 140 },
    .{ .min = 50, .max = 135 },
    .{ .min = 45, .max = 130 },
    .{ .min = 40, .max = 125 },
}){ .values = .{ 160, 125, 110, 100, 94, 88, 83, 78, 75 } };

pub var tm_nodetm_min_depth = Tunable(usize, .{ .min = 3, .max = 10, .c_end = 0.5 }){ .value = 5 };
pub var tm_nodetm_base = Tunable(i32, .{ .min = 80, .max = 220 }){ .value = 140 };
pub var tm_nodetm_mul = Tunable(i32, .{ .min = 60, .max = 220 }){ .value = 133 };
pub var tm_horizon_div = Tunable(u64, .{ .min = 2, .max = 12, .c_end = 0.5 }){ .value = 5 };
pub var tm_horizon_min = Tunable(u64, .{ .min = 5, .max = 30, .c_end = 1.25 }){ .value = 14 };
pub var tm_score_rise = Tunable(i32, .{ .min = 70, .max = 140 }){ .value = 90 };
pub var tm_score_drop = Tunable(i32, .{ .min = 100, .max = 200 }){ .value = 150 };
pub var tm_next_iter_mul = Tunable(u64, .{ .min = 100, .max = 400 }){ .value = 200 };

pub var hist_bonus_mul = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 300 };
pub var hist_bonus_offset = Tunable(i32, .{ .min = 0, .max = 800 }){ .value = 300 };
pub var hist_bonus_max = Tunable(i32, .{ .min = 1000, .max = 4000 }){ .value = 2500 };

pub var hist_malus_mul = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 250 };
pub var hist_malus_offset = Tunable(i32, .{ .min = 0, .max = 800 }){ .value = 250 };
pub var hist_malus_max = Tunable(i32, .{ .min = 500, .max = 3000 }){ .value = 1200 };

pub var see_weight = Tunable(i32, .{ .min = 10, .max = 200 }){ .value = 100 };
pub var capthist_div = Tunable(i32, .{ .min = 10, .max = 100 }){ .value = 39 };

pub var scale_pawn = Tunable(i32, .{ .min = 20, .max = 200}){ .value = 48 };
pub var scale_knight = Tunable(i32, .{ .min = 300, .max = 700}){ .value = 442};
pub var scale_bishop = Tunable(i32, .{ .min = 300, .max = 700}){ .value = 461};
pub var scale_rook = Tunable(i32, .{ .min = 400, .max = 1000}){ .value = 637};
pub var scale_queen = Tunable(i32, .{ .min = 800, .max = 1600}){ .value = 1223};

pub var material_scale_base = Tunable(i32, .{ .min = 10000, .max = 40000}){ .value = 35374};
pub var material_scale_div = Tunable(i32, .{ .min = 10000, .max = 40000}){ .value = 35374};

pub var fifty_scale_base = Tunable(i32, .{ .min = 120, .max = 400}){ .value = 200};

pub var optimism_base = Tunable(i32, .{ .min = 0, .max = 12000}){ .value = 2024};
pub var optimism_mat_scale = Tunable(i32, .{ .min = 0, .max = 2048}){ .value = 1005};
pub var optimism_scale = Tunable(i32, .{ .min = 50, .max = 300}){ .value = 147};
pub var optimism_stretch = Tunable(i32, .{ .min = 50, .max = 200}){ .value = 101};

pub var see_capture_mul = Tunable(i32, .{ .min = 10, .max = 60 }){ .value = 30 };
pub var see_capthist_div = Tunable(i32, .{ .min = 8, .max = 64 }){ .value = 16 };

pub var hindsight_red_margin = Tunable(i32, .{ .min = 0, .max = 200 }){ .value = 60 };

pub var butterfly_weight = Tunable(i32, .{ .min = 0, .max = 1024 }){ .value = 512 };
pub var threat_hist_weight = Tunable(i32, .{ .min = 0, .max = 1024 }){ .value = 512 };

pub var lph_update_scale = Tunable(i32, .{ .min = 128, .max = 2048 }){ .value = 768 };
pub var lph_order_mul = Tunable(i32, .{ .min = 10, .max = 120 }){ .value = 40};

pub var root_order_mul_quiet = Tunable(i32, .{ .min = 0, .max = 4000 }){ .value = 1000 };
pub var root_order_mul_noisy = Tunable(i32, .{ .min = 0, .max = 4000 }){ .value = 1000 };

pub const TunableRef = struct {
    name: []const u8,
    ptr: Value,
    min: f64,
    max: f64,
    c_end: ?f64 = null,
    r_end: f64 = 0.002,
    hook: Hook = .none,

    pub fn get(self: TunableRef) i64 {
        return switch (self.ptr) {
            inline else => |p| @intCast(p.*),
        };
    }

    pub fn set(self: TunableRef, raw: f64) void {
        const v = @round(std.math.clamp(raw, self.min, self.max));
        switch (self.ptr) {
            inline else => |p| {
                const T = @TypeOf(p.*);
                const lo: f64 = @floatFromInt(std.math.minInt(T));
                const hi: f64 = @floatFromInt(std.math.maxInt(T));
                p.* = @intFromFloat(std.math.clamp(v, lo, hi));
            },
        }
    }

    pub fn cEnd(self: TunableRef) f64 {
        if (self.c_end) |c| return c;
        return @max((self.max - self.min) / 20.0, 0.5);
    }
};

fn isTunable(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "meta") and @hasField(T, "value"),
        else => false,
    };
}

fn isTunableArray(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "metas") and @hasField(T, "values"),
        else => false,
    };
}

fn refTo(comptime name: []const u8, comptime spec: Spec, comptime val_ptr: anytype) TunableRef {
    const E = @TypeOf(val_ptr.*);
    const ptr_union = if (E == i32)
        Value{ .int = val_ptr }
    else if (E == usize)
        Value{ .size = val_ptr }
    else if (E == u64)
        Value{ .count = val_ptr }
    else if (@typeInfo(E) == .float)
        @compileError("tunable '" ++ name ++ "' is a float; store it as an integer scaled by 100 and read it with pct()")
    else
        @compileError("unsupported tunable type: " ++ @typeName(E));

    if (spec.min > spec.max) @compileError("tunable '" ++ name ++ "' has min > max");

    return TunableRef{
        .name = name,
        .ptr = ptr_union,
        .min = spec.min,
        .max = spec.max,
        .c_end = spec.c_end,
        .r_end = spec.r_end,
        .hook = spec.hook,
    };
}

pub const tunables = generated;

fn isFixed(comptime spec: Spec) bool {
    return spec.min == spec.max;
}

const generated = blk: {
    const decls = @typeInfo(@This()).@"struct".decls;

    var count: usize = 0;
    for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, "tunables")) continue;
        const T = @TypeOf(@field(@This(), decl.name));
        if (T == type) continue;
        if (isTunable(T)) {
            if (!isFixed(T.meta)) count += 1;
        } else if (isTunableArray(T)) {
            for (T.metas) |spec| {
                if (!isFixed(spec)) count += 1;
            }
        }
    }

    var arr: [count]TunableRef = undefined;
    var i: usize = 0;
    for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, "tunables")) continue;
        const T = @TypeOf(@field(@This(), decl.name));
        if (T == type) continue;

        if (isTunable(T)) {
            if (isFixed(T.meta)) continue;
            arr[i] = refTo(decl.name, T.meta, &@field(@This(), decl.name).value);
            i += 1;
        } else if (isTunableArray(T)) {
            for (T.metas, 0..) |spec, idx| {
                if (isFixed(spec)) continue;
                const name = decl.name ++ "_" ++ std.fmt.comptimePrint("{d}", .{idx});
                arr[i] = refTo(name, spec, &@field(@This(), decl.name).values[idx]);
                i += 1;
            }
        }
    }

    break :blk arr;
};

test "tunable defaults lie within their bounds" {
    for (tunables) |t| {
        const v: f64 = @floatFromInt(t.get());
        if (v < t.min or v > t.max) {
            std.debug.print("{s} = {d} outside [{d}, {d}]\n", .{ t.name, v, t.min, t.max });
            return error.TunableOutOfRange;
        }
    }
}

pub fn find(name: []const u8) ?TunableRef {
    for (tunables) |t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}
