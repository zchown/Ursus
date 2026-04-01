pub const max_ply = 128;
pub const max_game_ply = 1024;

pub var aspiration_window: i32 = 22;

pub const rfp_depth: i32 = 6;
pub var rfp_mul: i32 = 51;
pub var rfp_improve: i32 = 55;

pub var nmp_improve: i32 = 29;
pub var nmp_base: usize = 4;
pub var nmp_depth_div: usize = 3;
pub var nmp_beta_div: usize = 150;

pub var razoring_base: i32 = 299;
pub var razoring_mul: i32 = 73;

pub var lmp_improve: usize = 186;
pub var lmp_base: usize = 194;
pub var lmp_mul: usize = 288;

pub var futility_mul: i32 = 157;

pub var q_see_min: i32 = -150;
pub var q_see_margin: i32 = -41;
pub var q_delta_margin: i32 = 201;

pub var lmr_base: i32 = 428;
pub var lmr_div: i32 = 319;

pub var lmr_pv_min: usize = 4;
pub var lmr_non_pv_min: usize = 2;

pub var se_double_threshold: i32 = 24;
pub var se_triple_threshold: i32 = 21;

pub var history_div: i32 = 8252;

pub var corr_div_bm: i32 = 10;
pub var corr_div_nobm: i32 = 8;
pub var corr_np_update_weight: i32 = 178;

pub var corr_pawn_read_weight: i32 = 188;
pub var corr_np_read_weight: i32 = 122;  
pub var corr_major_read_weight: i32 = 102;
pub var corr_minor_read_weight: i32 = 111;

pub var corr_read_divisor: i32 = 127393;
