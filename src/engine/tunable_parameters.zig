const std = @import("std");

pub const max_ply = 128;
pub const max_game_ply = 1024;

pub var aspiration_window: i32 = 31;

pub var rfp_depth: i32 = 6;
pub var rfp_mul: i32 = 45;
pub var rfp_improve: i32 = 52;

pub var nmp_improve: i32 = 19;
pub var nmp_base: usize = 3;
pub var nmp_depth_div: usize = 3;
pub var nmp_beta_div: usize = 129;

pub var razoring_base: i32 = 282;
pub var razoring_mul: i32 = 61;

pub var lmp_improve: usize = 223;
pub var lmp_base: usize = 426;
pub var lmp_mul: usize = 229;

pub var futility_mul: i32 = 170;

pub var q_see_min: i32 = -25;
pub var q_see_margin: i32 = -45;
pub var q_delta_margin: i32 = 213;

pub var lmr_base: i32 = 90;
pub var lmr_div: i32 = 176;

pub var lmr_noisy_base: i32 = -13;
pub var lmr_noisy_div: i32 = 332;

pub var lmr_pv_min: usize = 3;
pub var lmr_non_pv_min: usize = 1;

pub var se_min_depth: usize = 7;
pub var se_margin: i32 = 300;

pub var history_div: i32 = 4107;

pub var corr_div_bm: i32 = 10;
pub var corr_div_nobm: i32 = 9;
pub var corr_np_update_weight: i32 = 181;

pub var corr_pawn_read_weight: i32 = 201;
pub var corr_np_read_weight: i32 = 125;
pub var corr_major_read_weight: i32 = 119;
pub var corr_minor_read_weight: i32 = 117;

pub var corr_read_divisor: i32 = 156991;

pub var tb_probe_depth: usize = 1;

pub var probcut_margin: i32 = 259;
pub var probcut_improve: i32 = 1046;
pub var probcut_min_see: i32 = 206;

pub var tm_stability_scale = [_]f32{ 1.60, 1.25, 1.10, 1.00, 0.94, 0.88, 0.83, 0.78, 0.75 };
pub var tm_nodetm_min_depth: usize = 5;
pub var tm_nodetm_base: f32 = 1.40;
pub var tm_nodetm_mul: f32 = 1.33;
pub var tm_horizon_div: u64 = 5;
pub var tm_horizon_min: u64 = 14;

pub var hist_bonus_mul: i32 = 300;
pub var hist_bonus_offset: i32 = 300;
pub var hist_bonus_max: i32 = 2500;

pub var hist_malus_mul: i32 = 250;
pub var hist_malus_offset: i32 = 250;
pub var hist_malus_max: i32 = 1200;

pub var see_weight: i32 = 500;
pub var capthist_div: i32 = 400;

pub const Hook = enum { none, quiet_lmr, noisy_lmr };

pub const Value = union(enum) {
    int: *i32,
    size: *usize,
    count: *u64,
    float: *f32,
};

pub const Tunable = struct {
    name: []const u8,
    ptr: Value,
    min: f64,
    max: f64,
    c_end: ?f64 = null,
    r_end: f64 = 0.002,
    hook: Hook = .none,

    pub fn isFloat(self: Tunable) bool {
        return switch (self.ptr) {
            .float => true,
            else => false,
        };
    }

    pub fn get(self: Tunable) f64 {
        return switch (self.ptr) {
            inline else => |p| switch (@typeInfo(@TypeOf(p.*))) {
                .float => @floatCast(p.*),
                .int => @floatFromInt(p.*),
                else => unreachable,
            },
        };
    }

    pub fn set(self: Tunable, raw: f64) void {
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

    pub fn cEnd(self: Tunable) f64 {
        if (self.c_end) |c| return c;
        const step = (self.max - self.min) / 20.0;
        return if (self.isFloat()) step else @max(step, 0.5);
    }
};

pub const tunables = [_]Tunable{
    .{ .name = "aspiration_window", .ptr = .{ .int = &aspiration_window }, .min = 8, .max = 80 },

    .{ .name = "rfp_depth", .ptr = .{ .int = &rfp_depth }, .min = 3, .max = 12, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "rfp_mul", .ptr = .{ .int = &rfp_mul }, .min = 15, .max = 120 },
    .{ .name = "rfp_improve", .ptr = .{ .int = &rfp_improve }, .min = 15, .max = 130 },

    .{ .name = "nmp_improve", .ptr = .{ .int = &nmp_improve }, .min = 0, .max = 80 },
    .{ .name = "nmp_base", .ptr = .{ .size = &nmp_base }, .min = 2, .max = 5, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "nmp_depth_div", .ptr = .{ .size = &nmp_depth_div }, .min = 2, .max = 8, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "nmp_beta_div", .ptr = .{ .size = &nmp_beta_div }, .min = 50, .max = 300 },

    .{ .name = "razoring_base", .ptr = .{ .int = &razoring_base }, .min = 100, .max = 600 },
    .{ .name = "razoring_mul", .ptr = .{ .int = &razoring_mul }, .min = 20, .max = 180 },

    .{ .name = "lmp_improve", .ptr = .{ .size = &lmp_improve }, .min = 100, .max = 500 },
    .{ .name = "lmp_base", .ptr = .{ .size = &lmp_base }, .min = 150, .max = 900 },
    .{ .name = "lmp_mul", .ptr = .{ .size = &lmp_mul }, .min = 100, .max = 500 },

    .{ .name = "futility_mul", .ptr = .{ .int = &futility_mul }, .min = 60, .max = 350 },

    .{ .name = "q_see_min", .ptr = .{ .int = &q_see_min }, .min = -200, .max = 0 },
    .{ .name = "q_see_margin", .ptr = .{ .int = &q_see_margin }, .min = -200, .max = 0 },
    .{ .name = "q_delta_margin", .ptr = .{ .int = &q_delta_margin }, .min = 50, .max = 500 },

    .{ .name = "lmr_base", .ptr = .{ .int = &lmr_base }, .min = 40, .max = 180, .hook = .quiet_lmr },
    .{ .name = "lmr_div", .ptr = .{ .int = &lmr_div }, .min = 100, .max = 350, .hook = .quiet_lmr },
    .{ .name = "lmr_noisy_base", .ptr = .{ .int = &lmr_noisy_base }, .min = -100, .max = 80, .hook = .noisy_lmr },
    .{ .name = "lmr_noisy_div", .ptr = .{ .int = &lmr_noisy_div }, .min = 150, .max = 600, .hook = .noisy_lmr },
    .{ .name = "lmr_pv_min", .ptr = .{ .size = &lmr_pv_min }, .min = 1, .max = 6, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "lmr_non_pv_min", .ptr = .{ .size = &lmr_non_pv_min }, .min = 1, .max = 4, .c_end = 0.10, .r_end = 0.01 },

    .{ .name = "se_min_depth", .ptr = .{ .size = &se_min_depth }, .min = 4, .max = 12, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "se_margin", .ptr = .{ .int = &se_margin }, .min = 100, .max = 600 },

    .{ .name = "probcut_margin", .ptr = .{ .int = &probcut_margin }, .min = 100, .max = 500 },
    .{ .name = "probcut_improve", .ptr = .{ .int = &probcut_improve }, .min = 400, .max = 2000 },
    .{ .name = "probcut_min_see", .ptr = .{ .int = &probcut_min_see }, .min = 0, .max = 500 },

    .{ .name = "history_div", .ptr = .{ .int = &history_div }, .min = 2048, .max = 8192 },
    .{ .name = "hist_bonus_mul", .ptr = .{ .int = &hist_bonus_mul }, .min = 100, .max = 600 },
    .{ .name = "hist_bonus_offset", .ptr = .{ .int = &hist_bonus_offset }, .min = 0, .max = 800 },
    .{ .name = "hist_bonus_max", .ptr = .{ .int = &hist_bonus_max }, .min = 1000, .max = 4000 },
    .{ .name = "hist_malus_mul", .ptr = .{ .int = &hist_malus_mul }, .min = 100, .max = 600 },
    .{ .name = "hist_malus_offset", .ptr = .{ .int = &hist_malus_offset }, .min = 0, .max = 800 },
    .{ .name = "hist_malus_max", .ptr = .{ .int = &hist_malus_max }, .min = 500, .max = 3000 },
    .{ .name = "capthist_div", .ptr = .{ .int = &capthist_div }, .min = 100, .max = 1000 },
    .{ .name = "see_weight", .ptr = .{ .int = &see_weight }, .min = 100, .max = 1200 },

    .{ .name = "corr_div_bm", .ptr = .{ .int = &corr_div_bm }, .min = 4, .max = 24, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "corr_div_nobm", .ptr = .{ .int = &corr_div_nobm }, .min = 4, .max = 24, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "corr_np_update_weight", .ptr = .{ .int = &corr_np_update_weight }, .min = 64, .max = 384 },
    .{ .name = "corr_pawn_read_weight", .ptr = .{ .int = &corr_pawn_read_weight }, .min = 64, .max = 400 },
    .{ .name = "corr_np_read_weight", .ptr = .{ .int = &corr_np_read_weight }, .min = 32, .max = 320 },
    .{ .name = "corr_major_read_weight", .ptr = .{ .int = &corr_major_read_weight }, .min = 32, .max = 320 },
    .{ .name = "corr_minor_read_weight", .ptr = .{ .int = &corr_minor_read_weight }, .min = 32, .max = 320 },
    .{ .name = "corr_read_divisor", .ptr = .{ .int = &corr_read_divisor }, .min = 65536, .max = 327680 },

    .{ .name = "tm_nodetm_min_depth", .ptr = .{ .size = &tm_nodetm_min_depth }, .min = 3, .max = 10, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "tm_nodetm_base", .ptr = .{ .float = &tm_nodetm_base }, .min = 0.80, .max = 2.20 },
    .{ .name = "tm_nodetm_mul", .ptr = .{ .float = &tm_nodetm_mul }, .min = 0.60, .max = 2.20 },
    .{ .name = "tm_horizon_div", .ptr = .{ .count = &tm_horizon_div }, .min = 2, .max = 12, .c_end = 0.10, .r_end = 0.01 },
    .{ .name = "tm_horizon_min", .ptr = .{ .count = &tm_horizon_min }, .min = 5, .max = 30, .c_end = 0.50, .r_end = 0.004 },

    .{ .name = "tm_stability_scale_0", .ptr = .{ .float = &tm_stability_scale[0] }, .min = 1.00, .max = 2.50 },
    .{ .name = "tm_stability_scale_1", .ptr = .{ .float = &tm_stability_scale[1] }, .min = 0.90, .max = 2.00 },
    .{ .name = "tm_stability_scale_2", .ptr = .{ .float = &tm_stability_scale[2] }, .min = 0.80, .max = 1.80 },
    .{ .name = "tm_stability_scale_3", .ptr = .{ .float = &tm_stability_scale[3] }, .min = 0.70, .max = 1.60 },
    .{ .name = "tm_stability_scale_4", .ptr = .{ .float = &tm_stability_scale[4] }, .min = 0.60, .max = 1.50 },
    .{ .name = "tm_stability_scale_5", .ptr = .{ .float = &tm_stability_scale[5] }, .min = 0.55, .max = 1.40 },
    .{ .name = "tm_stability_scale_6", .ptr = .{ .float = &tm_stability_scale[6] }, .min = 0.50, .max = 1.35 },
    .{ .name = "tm_stability_scale_7", .ptr = .{ .float = &tm_stability_scale[7] }, .min = 0.45, .max = 1.30 },
    .{ .name = "tm_stability_scale_8", .ptr = .{ .float = &tm_stability_scale[8] }, .min = 0.40, .max = 1.25 },
};

pub fn find(name: []const u8) ?Tunable {
    for (tunables) |t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}
