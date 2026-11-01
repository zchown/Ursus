const std = @import("std");

pub const max_ply = 128;

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
    .{ .min = 0, .max = 0 },
}){ .values = .{ 96, 305, 359, 494, 996, 20000, 0 } };

pub var aspiration_window = Tunable(i32, .{ .min = 8, .max = 80 }){ .value = 15 };
pub var asp_score_div = Tunable(i32, .{ .min = 5000, .max = 40000 }){ .value = 13456 };
pub var asp_growth = Tunable(i32, .{ .min = 20, .max = 100 }){ .value = 48 };

pub var rfp_mul = Tunable(i32, .{ .min = 15, .max = 120 }){ .value = 47 };
pub var rfp_improve = Tunable(i32, .{ .min = 15, .max = 130 }){ .value = 55 };

pub var nmp_improve = Tunable(i32, .{ .min = 0, .max = 80 }){ .value = 15 };
pub var nmp_base = Tunable(usize, .{ .min = 2, .max = 5, .c_end = 0.5 }){ .value = 3 };
pub var nmp_depth_div = Tunable(usize, .{ .min = 2, .max = 8, .c_end = 0.5 }){ .value = 3 };
pub var nmp_beta_div = Tunable(usize, .{ .min = 50, .max = 300 }){ .value = 135 };

pub var razoring_base = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 282 };
pub var razoring_mul = Tunable(i32, .{ .min = 20, .max = 180 }){ .value = 62 };

pub var lmp_base = Tunable(usize, .{ .min = 100, .max = 800 }){ .value = 329 };
pub var lmp_mul = Tunable(usize, .{ .min = 30, .max = 200 }){ .value = 104 };

pub var futility_base = Tunable(i32, .{ .min = 0, .max = 300 }){ .value = 85 };
pub var futility_mul = Tunable(i32, .{ .min = 50, .max = 300 }){ .value = 114 };
pub var futility_hist_div = Tunable(i32, .{ .min = 32, .max = 512 }){ .value = 116 };

pub var see_quiet_mul = Tunable(i32, .{ .min = 5, .max = 60 }){ .value = 24 };

pub var q_see_min = Tunable(i32, .{ .min = -300, .max = 0 }){ .value = -28 };
pub var q_fut_margin = Tunable(i32, .{ .min = 10, .max = 600 }){ .value = 393 };
pub var q_delta_margin = Tunable(i32, .{ .min = 50, .max = 500 }){ .value = 204 };

pub var lmr_base = Tunable(i32, .{ .min = 40, .max = 180, .hook = .quiet_lmr }){ .value = 96 };
pub var lmr_div = Tunable(i32, .{ .min = 100, .max = 350, .hook = .quiet_lmr }){ .value = 195 };

pub var lmr_noisy_base = Tunable(i32, .{ .min = -100, .max = 80, .hook = .noisy_lmr }){ .value = -12 };
pub var lmr_noisy_div = Tunable(i32, .{ .min = 150, .max = 600, .hook = .noisy_lmr }){ .value = 345 };

pub var se_margin = Tunable(i32, .{ .min = 50, .max = 500 }){ .value = 104 };
pub var se_double_margin = Tunable(i32, .{ .min = 0, .max = 100 }){ .value = 45 };

pub var history_div = Tunable(i32, .{ .min = 2048, .max = 8192 }){ .value = 4534 };
pub var history_prune_mult = Tunable(i32, .{ .min = 512, .max = 8192 }){ .value = 2090 };

pub var stat_main_weight = Tunable(i32, .{ .min = 128, .max = 2048 }){ .value = 954 };
pub var stat_cont1_weight = Tunable(i32, .{ .min = 128, .max = 2048 }){ .value = 528 };
pub var stat_cont2_weight = Tunable(i32, .{ .min = 128, .max = 2048 }){ .value = 552 };
pub var stat_cont4_weight = Tunable(i32, .{ .min = 128, .max = 2048 }){ .value = 284 };

pub var corr_pawn_read_weight = Tunable(i32, .{ .min = 64, .max = 400 }){ .value = 177 };
pub var corr_np_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 135 };
pub var corr_major_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 112 };
pub var corr_minor_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 116 };
pub var corr_cont_read_weight = Tunable(i32, .{ .min = 0, .max = 320 }){ .value = 122 };

pub var corr_read_divisor = Tunable(i32, .{ .min = 1024, .max = 12288 }){ .value = 2677 };
pub var corr_limit = Tunable(i32, .{ .min = 128, .max = 4096 }){ .value = 752 };

pub var probcut_margin = Tunable(i32, .{ .min = 100, .max = 500 }){ .value = 253 };
pub var probcut_improve = Tunable(i32, .{ .min = 400, .max = 2000 }){ .value = 962 };
pub var probcut_min_see = Tunable(i32, .{ .min = 0, .max = 500 }){ .value = 230 };

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
}){ .values = .{ 162, 131, 108, 107, 90, 85, 85, 79, 73 } };

pub var tm_nodetm_min_depth = Tunable(usize, .{ .min = 3, .max = 10, .c_end = 0.5 }){ .value = 5 };
pub var tm_nodetm_base = Tunable(i32, .{ .min = 80, .max = 220 }){ .value = 144 };
pub var tm_nodetm_mul = Tunable(i32, .{ .min = 60, .max = 220 }){ .value = 132 };
pub var tm_horizon_div = Tunable(u64, .{ .min = 2, .max = 12, .c_end = 0.5 }){ .value = 4 };
pub var tm_horizon_min = Tunable(u64, .{ .min = 5, .max = 30, .c_end = 1.25 }){ .value = 13 };
pub var tm_score_rise = Tunable(i32, .{ .min = 70, .max = 140 }){ .value = 95 };
pub var tm_score_drop = Tunable(i32, .{ .min = 100, .max = 200 }){ .value = 156 };
pub var tm_next_iter_mul = Tunable(u64, .{ .min = 100, .max = 400 }){ .value = 168 };

pub var hist_bonus_mul = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 295 };
pub var hist_bonus_offset = Tunable(i32, .{ .min = 0, .max = 800 }){ .value = 288 };
pub var hist_bonus_max = Tunable(i32, .{ .min = 1000, .max = 4000 }){ .value = 2533 };

pub var hist_malus_mul = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 326 };
pub var hist_malus_offset = Tunable(i32, .{ .min = 0, .max = 800 }){ .value = 177 };
pub var hist_malus_max = Tunable(i32, .{ .min = 500, .max = 3000 }){ .value = 1148 };

pub var see_weight = Tunable(i32, .{ .min = 10, .max = 200 }){ .value = 104 };
pub var capthist_div = Tunable(i32, .{ .min = 10, .max = 100 }){ .value = 38 };

pub var scale_pawn = Tunable(i32, .{ .min = 20, .max = 200 }){ .value = 45 };
pub var scale_knight = Tunable(i32, .{ .min = 300, .max = 700 }){ .value = 433 };
pub var scale_bishop = Tunable(i32, .{ .min = 300, .max = 700 }){ .value = 489 };
pub var scale_rook = Tunable(i32, .{ .min = 400, .max = 1000 }){ .value = 645 };
pub var scale_queen = Tunable(i32, .{ .min = 800, .max = 1600 }){ .value = 1216 };

pub var material_scale_div = Tunable(i32, .{ .min = 10000, .max = 40000 }){ .value = 36098 };

pub var fifty_scale_base = Tunable(i32, .{ .min = 120, .max = 400 }){ .value = 185 };

pub var optimism_base = Tunable(i32, .{ .min = 0, .max = 12000 }){ .value = 2542 };
pub var optimism_mat_scale = Tunable(i32, .{ .min = 0, .max = 2048 }){ .value = 1202 };
pub var optimism_scale = Tunable(i32, .{ .min = 50, .max = 300 }){ .value = 155 };
pub var optimism_stretch = Tunable(i32, .{ .min = 50, .max = 200 }){ .value = 100 };

pub var see_capture_mul = Tunable(i32, .{ .min = 10, .max = 60 }){ .value = 27 };
pub var see_capthist_div = Tunable(i32, .{ .min = 8, .max = 64 }){ .value = 17 };

pub var hindsight_red_margin = Tunable(i32, .{ .min = 0, .max = 200 }){ .value = 56 };

pub var butterfly_weight = Tunable(i32, .{ .min = 0, .max = 1024 }){ .value = 514 };
pub var threat_hist_weight = Tunable(i32, .{ .min = 0, .max = 1024 }){ .value = 535 };

pub var lph_update_scale = Tunable(i32, .{ .min = 128, .max = 2048 }){ .value = 736 };
pub var lph_order_mul = Tunable(i32, .{ .min = 10, .max = 120 }){ .value = 40 };

pub var root_order_mul_quiet = Tunable(i32, .{ .min = 0, .max = 4000 }){ .value = 972 };
pub var root_order_mul_noisy = Tunable(i32, .{ .min = 0, .max = 4000 }){ .value = 1114 };

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
    else
        @compileError("tunable '" ++ name ++ "' must be i32, usize or u64, not " ++ @typeName(E));

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
