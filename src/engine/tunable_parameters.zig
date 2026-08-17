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


pub const Hook = enum { none, quiet_lmr, noisy_lmr };

pub const Value = union(enum) {
    int: *i32,
    size: *usize,
    count: *u64,
    float: *f32,
};

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

pub var aspiration_window = Tunable(i32, .{ .min = 8, .max = 80 }){ .value = 31 };

pub var rfp_mul = Tunable(i32, .{ .min = 15, .max = 120 }){ .value = 45 };
pub var rfp_improve = Tunable(i32, .{ .min = 15, .max = 130 }){ .value = 52 };

pub var nmp_improve = Tunable(i32, .{ .min = 0, .max = 80 }){ .value = 19 };
pub var nmp_base = Tunable(usize, .{ .min = 2, .max = 5, .c_end = 0.10, .r_end = 0.01 }){ .value = 3 };
pub var nmp_depth_div = Tunable(usize, .{ .min = 2, .max = 8, .c_end = 0.10, .r_end = 0.01 }){ .value = 3 };
pub var nmp_beta_div = Tunable(usize, .{ .min = 50, .max = 300 }){ .value = 129 };

pub var razoring_base = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 282 };
pub var razoring_mul = Tunable(i32, .{ .min = 20, .max = 180 }){ .value = 61 };

pub var lmp_improve = Tunable(usize, .{ .min = 100, .max = 500 }){ .value = 223 };
pub var lmp_base = Tunable(usize, .{ .min = 150, .max = 900 }){ .value = 426 };
pub var lmp_mul = Tunable(usize, .{ .min = 100, .max = 500 }){ .value = 229 };

pub var futility_mul = Tunable(i32, .{ .min = 60, .max = 350 }){ .value = 170 };

pub var q_see_min = Tunable(i32, .{ .min = -300, .max = 0 }){ .value = -25 };
pub var q_see_margin = Tunable(i32, .{ .min = -200, .max = 0 }){ .value = -45 };
pub var q_delta_margin = Tunable(i32, .{ .min = 50, .max = 500 }){ .value = 213 };

pub var lmr_base = Tunable(i32, .{ .min = 40, .max = 180, .hook = .quiet_lmr }){ .value = 90 };
pub var lmr_div = Tunable(i32, .{ .min = 100, .max = 350, .hook = .quiet_lmr }){ .value = 176 };

pub var lmr_noisy_base = Tunable(i32, .{ .min = -100, .max = 80, .hook = .noisy_lmr }){ .value = -13 };
pub var lmr_noisy_div = Tunable(i32, .{ .min = 150, .max = 600, .hook = .noisy_lmr }){ .value = 332 };

pub var se_margin = Tunable(i32, .{ .min = 50, .max = 500}){ .value = 300};

pub var history_div = Tunable(i32, .{ .min = 2048, .max = 8192 }){ .value = 4107 };

pub var corr_div_bm = Tunable(i32, .{ .min = 4, .max = 24, .c_end = 0.10, .r_end = 0.01 }){ .value = 10 };
pub var corr_div_nobm = Tunable(i32, .{ .min = 4, .max = 24, .c_end = 0.10, .r_end = 0.01 }){ .value = 9 };
pub var corr_np_update_weight = Tunable(i32, .{ .min = 64, .max = 384 }){ .value = 181 };

pub var corr_pawn_read_weight = Tunable(i32, .{ .min = 64, .max = 400 }){ .value = 201 };
pub var corr_np_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 125 };
pub var corr_major_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 119 };
pub var corr_minor_read_weight = Tunable(i32, .{ .min = 32, .max = 320 }){ .value = 117 };

pub var corr_read_divisor = Tunable(i32, .{ .min = 65536, .max = 327680 }){ .value = 156991 };

pub var probcut_margin = Tunable(i32, .{ .min = 100, .max = 500 }){ .value = 259 };
pub var probcut_improve = Tunable(i32, .{ .min = 400, .max = 2000 }){ .value = 1046 };
pub var probcut_min_see = Tunable(i32, .{ .min = 0, .max = 500 }){ .value = 206 };

pub var tm_stability_scale = TunableArray(f32, &.{
    .{ .min = 1.00, .max = 2.50 },
    .{ .min = 0.90, .max = 2.00 },
    .{ .min = 0.80, .max = 1.80 },
    .{ .min = 0.70, .max = 1.60 },
    .{ .min = 0.60, .max = 1.50 },
    .{ .min = 0.55, .max = 1.40 },
    .{ .min = 0.50, .max = 1.35 },
    .{ .min = 0.45, .max = 1.30 },
    .{ .min = 0.40, .max = 1.25 },
}){ .values = .{ 1.60, 1.25, 1.10, 1.00, 0.94, 0.88, 0.83, 0.78, 0.75 } };

pub var tm_nodetm_min_depth = Tunable(usize, .{ .min = 3, .max = 10, .c_end = 0.10, .r_end = 0.01 }){ .value = 5 };
pub var tm_nodetm_base = Tunable(f32, .{ .min = 0.80, .max = 2.20 }){ .value = 1.40 };
pub var tm_nodetm_mul = Tunable(f32, .{ .min = 0.60, .max = 2.20 }){ .value = 1.33 };
pub var tm_horizon_div = Tunable(u64, .{ .min = 2, .max = 12, .c_end = 0.10, .r_end = 0.01 }){ .value = 5 };
pub var tm_horizon_min = Tunable(u64, .{ .min = 5, .max = 30, .c_end = 0.50, .r_end = 0.004 }){ .value = 14 };

pub var hist_bonus_mul = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 300 };
pub var hist_bonus_offset = Tunable(i32, .{ .min = 0, .max = 800 }){ .value = 300 };
pub var hist_bonus_max = Tunable(i32, .{ .min = 1000, .max = 4000 }){ .value = 2500 };

pub var hist_malus_mul = Tunable(i32, .{ .min = 100, .max = 600 }){ .value = 250 };
pub var hist_malus_offset = Tunable(i32, .{ .min = 0, .max = 800 }){ .value = 250 };
pub var hist_malus_max = Tunable(i32, .{ .min = 500, .max = 3000 }){ .value = 1200 };

pub var see_weight = Tunable(i32, .{ .min = 10, .max = 200 }){ .value = 100 };
pub var capthist_div = Tunable(i32, .{ .min = 10, .max = 100 }){ .value = 39 };

pub var fifty_scale_base = Tunable(i32, .{ .min = 120, .max = 400}){ .value = 200};

pub const TunableRef = struct {
    name: []const u8,
    ptr: Value,
    min: f64,
    max: f64,
    c_end: ?f64 = null,
    r_end: f64 = 0.002,
    hook: Hook = .none,

    pub fn isFloat(self: TunableRef) bool {
        return switch (self.ptr) {
            .float => true,
            else => false,
        };
    }

    pub fn get(self: TunableRef) f64 {
        return switch (self.ptr) {
            inline else => |p| switch (@typeInfo(@TypeOf(p.*))) {
                .float => @floatCast(p.*),
                .int => @floatFromInt(p.*),
                else => unreachable,
            },
        };
    }

    pub fn set(self: TunableRef, raw: f64) void {
        const v = std.math.clamp(raw, self.min, self.max);
        switch (self.ptr) {
            inline else => |p| {
                const T = @TypeOf(p.*);
                switch (@typeInfo(T)) {
                    .float => p.* = @floatCast(v),
                    .int => {
                        const lo: f64 = @floatFromInt(std.math.minInt(T));
                        const hi: f64 = @floatFromInt(std.math.maxInt(T));
                        p.* = @intFromFloat(std.math.clamp(@round(v), lo, hi));
                    },
                    else => unreachable,
                }
            },
        }
    }

    pub fn cEnd(self: TunableRef) f64 {
        if (self.c_end) |c| return c;
        const step = (self.max - self.min) / 20.0;
        return if (self.isFloat()) step else @max(step, 0.5);
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
    else if (E == f32)
        Value{ .float = val_ptr }
    else
        @compileError("unsupported tunable type: " ++ @typeName(E));

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

const generated = blk: {
    const decls = @typeInfo(@This()).@"struct".decls;

    var count: usize = 0;
    for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, "tunables")) continue;
        const T = @TypeOf(@field(@This(), decl.name));
        if (T == type) continue;
        if (isTunable(T)) {
            count += 1;
        } else if (isTunableArray(T)) {
            count += T.metas.len;
        }
    }

    var arr: [count]TunableRef = undefined;
    var i: usize = 0;
    for (decls) |decl| {
        if (std.mem.eql(u8, decl.name, "tunables")) continue;
        const T = @TypeOf(@field(@This(), decl.name));
        if (T == type) continue;

        if (isTunable(T)) {
            arr[i] = refTo(decl.name, T.meta, &@field(@This(), decl.name).value);
            i += 1;
        } else if (isTunableArray(T)) {
            for (T.metas, 0..) |spec, idx| {
                const name = decl.name ++ "_" ++ std.fmt.comptimePrint("{d}", .{idx});
                arr[i] = refTo(name, spec, &@field(@This(), decl.name).values[idx]);
                i += 1;
            }
        }
    }

    break :blk arr;
};

pub fn find(name: []const u8) ?TunableRef {
    for (tunables) |t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}
