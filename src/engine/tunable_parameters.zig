pub const max_ply = 128;
pub const max_game_ply = 1024;

pub var aspiration_window: i32 = 31;

pub const rfp_depth: i32 = 6;
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

pub var q_see_min: i32 = -144;
pub var q_see_margin: i32 = -45;
pub var q_delta_margin: i32 = 213;

pub var lmr_base: i32 = 90;
pub var lmr_div: i32 = 176;

pub var lmr_noisy_base: i32 = -13;
pub var lmr_noisy_div: i32 = 332;

pub var lmr_pv_min: usize = 3;
pub var lmr_non_pv_min: usize = 1;

pub var se_margin: i32 = 200;
pub var se_min_depth: usize = 7;

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
