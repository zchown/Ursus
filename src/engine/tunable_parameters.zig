pub const max_ply = 128;
pub const max_game_ply = 1024;

pub const aspiration_window: i32 = 15;

pub const rfp_depth: i32 = 6;
pub const rfp_mul: i32 = 63;
pub const rfp_improve: i32 = 42;

pub const nmp_improve: i32 = 36;
pub const nmp_base: usize = 4;
pub const nmp_depth_div: usize = 3;
pub const nmp_beta_div: usize = 159;

pub const razoring_base: i32 = 337;
pub const razoring_mul: i32 = 70;

pub const iid_depth: usize = 1;

pub const lmp_improve: usize = 2;
pub const lmp_base: usize = 2;
pub const lmp_mul: usize = 2;

pub const futility_mul: i32 = 161;

pub const q_see_min: i32 = -133;
pub const q_see_margin: i32 = -37;
pub const q_delta_margin: i32 = 160;

pub const lmr_base: i32 = 428;
pub const lmr_div: i32 = 319;

pub const lmr_pv_min: usize = 4;
pub const lmr_non_pv_min: usize = 2;

pub const se_double_threshold: i32 = 28;
pub const se_triple_threshold: i32 = 14;

pub const pc_margin: i32 = 182;

pub const history_div: i32 = 8022;

pub const corr_div_bm: i32 = 10;
pub const corr_div_nobm: i32 = 8;
pub const corr_np_update_weight: i32 = 178;

pub var corr_pawn_read_weight: i32 = 175;
pub var corr_np_read_weight: i32 = 75;  
pub var corr_read_divisor: i32 = 64314;
