const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const brd = root.brd;

// Network layout, mirroring the bullet trainer (main.rs):
//
//   768x16 king-bucketed, horizontally mirrored inputs
//     -> FT 1280 (i16, QA), crelu, pairwise multiply  -> 640 per perspective, stm ++ ntm = 1280
//     -> L1 1280 -> 16           (i8 weights, i32 bias)   x8 material output buckets
//     -> concat(x, |x|^2), crelu -> 32
//     -> L2 32 -> 32, crelu      (i32 weights, i32 bias)
//     -> L3 32 -> 1              (i32 weights, i32 bias)
//     -> eval = 400 * out
pub const net_path = "nets/Alkaid-ml.bin";

pub const hidden_size = 1280;
pub const pairwise_size = hidden_size / 2;
pub const l1_size = 2 * pairwise_size;
pub const l2_size = 16;
pub const l2_in_size = 2 * l2_size;
pub const l3_size = 32;

pub const features_per_bucket = 2 * brd.num_pieces * brd.num_squares;

pub const NUM_KING_BUCKETS: usize = 16;
const NUM_OUTPUT_BUCKETS: usize = 8;
const EVAL_SCALE: f32 = 128.0;
const KING_BUCKETS_BASE: [32]u8 = [_]u8{
    0,  1,  2,  3,
    4,  5,  6,  7,
    8,  8,  9,  9,
    10, 10, 11, 11,
    12, 12, 13, 13,
    12, 12, 13, 13,
    14, 14, 15, 15,
    14, 14, 15, 15,
};

pub const num_features = NUM_KING_BUCKETS * features_per_bucket;

comptime {
    std.debug.assert(hidden_size % 2 == 0);
    std.debug.assert(l1_size == hidden_size);
}

const QA: i16 = 255;
const Q1: i32 = 128;
const Q: i32 = 64;
const ft_shift: u4 = 8;

const l1_dequant: f32 = 1.0 / @as(f32, @floatFromInt(Q1 << ft_shift));

const l1_bias_scale: i64 = Q * 256;
const l2_weight_scale: i64 = Q;
const l2_bias_scale: i64 = Q * Q * Q;
const l3_weight_scale: i64 = Q;
const l3_bias_scale: i64 = Q * Q * Q * Q;

const cache_line = std.atomic.cache_line;

const CpuTarget = enum {
    avx512_vnni,
    avx512,
    avx_vnni,
    avx2,
    sdot,
    neon,
    sse2,
    fallback,
};

const x86_avx2 = builtin.cpu.arch == .x86_64 and
    std.Target.x86.featureSetHas(builtin.cpu.features, .avx2);
const x86_avxvnni = builtin.cpu.arch == .x86_64 and
    std.Target.x86.featureSetHas(builtin.cpu.features, .avxvnni);
const x86_avx512 = builtin.cpu.arch == .x86_64 and
    std.Target.x86.featureSetHas(builtin.cpu.features, .avx512f) and
    std.Target.x86.featureSetHas(builtin.cpu.features, .avx512bw);
const x86_avx512vnni = x86_avx512 and
    std.Target.x86.featureSetHas(builtin.cpu.features, .avx512vnni);
const arm_sdot = builtin.cpu.arch == .aarch64 and
    std.Target.aarch64.featureSetHas(builtin.cpu.features, .dotprod);

pub const TARGET: CpuTarget = blk: {
    const cpu = builtin.cpu;
    switch (cpu.arch) {
        .x86_64 => {
            if (x86_avx512vnni) break :blk .avx512_vnni;
            if (x86_avx512) break :blk .avx512;
            if (x86_avxvnni) break :blk .avx_vnni;
            if (x86_avx2) break :blk .avx2;
            if (std.Target.x86.featureSetHas(cpu.features, .sse2)) break :blk .sse2;
        },
        .aarch64 => {
            if (arm_sdot) break :blk .sdot;
            break :blk .neon;
        },
        else => {},
    }
    break :blk .fallback;
};

pub const has_sdot = TARGET == .sdot;
pub const has_vnni = TARGET == .avx_vnni or TARGET == .avx512_vnni;
pub const has_byte_dot = has_sdot or has_vnni;

const vec_i16_len: comptime_int = std.simd.suggestVectorLength(i16) orelse 8;
const vec_i32_len: comptime_int = vec_i16_len / 2;
const num_acc_vecs: usize = hidden_size / vec_i16_len;
const num_pairwise_vecs: usize = pairwise_size / vec_i16_len;
const num_l1_vecs: usize = l1_size / vec_i16_len;

const I16Vec = @Vector(vec_i16_len, i16);
const I32Vec = @Vector(vec_i32_len, i32);
const U16Vec = @Vector(vec_i16_len, u16);
const I8Vec = @Vector(vec_i16_len, i8);
const U8Vec = @Vector(vec_i16_len, u8);

const L1I16x8 = @Vector(8, i16);
const L1I32x8 = @Vector(8, i32);

inline fn maddwd(a: I16Vec, b: I16Vec) I32Vec {
    return switch (TARGET) {
        .avx512_vnni, .avx512, .avx_vnni, .avx2 => asm ("vpmaddwd %[b], %[a], %[ret]"
            : [ret] "=x" (-> I32Vec),
            : [a] "x" (a),
              [b] "x" (b),
        ),
        .sse2 => asm ("pmaddwd %[b], %[a]"
            : [ret] "=x" (-> I32Vec),
            : [a] "0" (a),
              [b] "x" (b),
        ),
        .sdot, .neon, .fallback => blk: {
            const a_parts = std.simd.deinterlace(2, a);
            const b_parts = std.simd.deinterlace(2, b);
            const lo: I32Vec = @as(I32Vec, a_parts[0]) * @as(I32Vec, b_parts[0]);
            const hi: I32Vec = @as(I32Vec, a_parts[1]) * @as(I32Vec, b_parts[1]);
            break :blk lo + hi;
        },
    };
}

inline fn dotAccumulate(sum: I32Vec, a: I16Vec, b: I16Vec) I32Vec {
    return switch (TARGET) {
        .sdot, .neon => blk: {
            const after_lo: I32Vec = asm (
                \\smlal %[d].4s, %[n].4h, %[m].4h
                : [d] "=w" (-> I32Vec),
                : [n] "w" (a),
                  [m] "w" (b),
                  [_] "0" (sum),
            );
            break :blk asm (
                \\smlal2 %[d].4s, %[n].8h, %[m].8h
                : [d] "=w" (-> I32Vec),
                : [n] "w" (a),
                  [m] "w" (b),
                  [_] "0" (after_lo),
            );
        },
        else => sum +% maddwd(a, b),
    };
}

pub const dot_bytes: usize = switch (TARGET) {
    .avx512_vnni => 64,
    .avx_vnni => 32,
    else => 16,
};

const DotU8 = @Vector(dot_bytes, u8);
const DotI8 = @Vector(dot_bytes, i8);
const DotAcc = @Vector(dot_bytes / 4, i32);

inline fn byteDotAccumulate(sum: DotAcc, a: DotU8, b: DotI8) DotAcc {
    return switch (TARGET) {
        .sdot => blk: {
            const biased: DotI8 = @bitCast(a ^ @as(DotU8, @splat(0x80)));
            break :blk asm ("sdot %[d].4s, %[n].16b, %[m].16b"
                : [d] "=w" (-> DotAcc),
                : [n] "w" (biased),
                  [m] "w" (b),
                  [_] "0" (sum),
            );
        },
        .avx_vnni => asm ("vpdpbusd %[m], %[n], %[d]"
            : [d] "=x" (-> DotAcc),
            : [n] "x" (a),
              [m] "x" (b),
              [_] "0" (sum),
        ),
        .avx512_vnni => asm ("vpdpbusd %[m], %[n], %[d]"
            : [d] "=x" (-> DotAcc),
            : [n] "x" (a),
              [m] "x" (b),
              [_] "0" (sum),
        ),
        else => blk: {
            var out = sum;
            inline for (0..dot_bytes / 4) |lane| {
                var acc: i32 = out[lane];
                inline for (0..4) |k| {
                    acc += @as(i32, a[lane * 4 + k]) * @as(i32, b[lane * 4 + k]);
                }
                out[lane] = acc;
            }
            break :blk out;
        },
    };
}

inline fn sparseAccumulate16(
    lo: *L1I32x8,
    hi: *L1I32x8,
    weights: *const [16]i8,
    x: u8,
) void {
    const xv: L1I16x8 = @splat(@as(i16, x));

    const lo_w: L1I16x8 = @intCast(@as(@Vector(8, i8), weights[0..8].*));
    const hi_w: L1I16x8 = @intCast(@as(@Vector(8, i8), weights[8..16].*));

    lo.* += @as(L1I32x8, @intCast(lo_w * xv));
    hi.* += @as(L1I32x8, @intCast(hi_w * xv));
}

const nnue_piece_to_index = [2][6]u8{
    [_]u8{ 0, 1, 2, 3, 4, 5 }, // Pawn, Knight, Bishop, Rook, Queen, King
    [_]u8{ 6, 7, 8, 9, 10, 11 }, // Pawn, Knight, Bishop, Rook, Queen, King
};

pub const NetworkWeights = extern struct {
    ft_weights: [num_features][hidden_size]i16 align(cache_line),
    ft_biases: [hidden_size]i16 align(cache_line),

    l1_weights: [l1_size][NUM_OUTPUT_BUCKETS][l2_size]i8 align(cache_line),
    l1_biases: [NUM_OUTPUT_BUCKETS][l2_size]i32 align(cache_line),

    l2_weights: [l2_in_size][NUM_OUTPUT_BUCKETS][l3_size]i32 align(cache_line),
    l2_biases: [NUM_OUTPUT_BUCKETS][l3_size]i32 align(cache_line),

    l3_weights: [l3_size][NUM_OUTPUT_BUCKETS]i32 align(cache_line),
    l3_biases: [NUM_OUTPUT_BUCKETS]i32,
};

pub const net_data_bytes: usize = blk: {
    var n: usize = 0;
    n += num_features * hidden_size * @sizeOf(i16);
    n += hidden_size * @sizeOf(i16);
    n += l1_size * NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(i8);
    n += NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(i32);
    n += l2_in_size * NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(i32);
    n += NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(i32);
    n += l3_size * NUM_OUTPUT_BUCKETS * @sizeOf(i32);
    n += NUM_OUTPUT_BUCKETS * @sizeOf(i32);
    break :blk n;
};

comptime {
    var off: usize = 0;
    std.debug.assert(@offsetOf(NetworkWeights, "ft_weights") == off);
    off += num_features * hidden_size * @sizeOf(i16);
    std.debug.assert(@offsetOf(NetworkWeights, "ft_biases") == off);
    off += hidden_size * @sizeOf(i16);
    std.debug.assert(@offsetOf(NetworkWeights, "l1_weights") == off);
    off += l1_size * NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(i8);
    std.debug.assert(@offsetOf(NetworkWeights, "l1_biases") == off);
    off += NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(i32);
    std.debug.assert(@offsetOf(NetworkWeights, "l2_weights") == off);
    off += l2_in_size * NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(i32);
    std.debug.assert(@offsetOf(NetworkWeights, "l2_biases") == off);
    off += NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(i32);
    std.debug.assert(@offsetOf(NetworkWeights, "l3_weights") == off);
    off += l3_size * NUM_OUTPUT_BUCKETS * @sizeOf(i32);
    std.debug.assert(@offsetOf(NetworkWeights, "l3_biases") == off);
    off += NUM_OUTPUT_BUCKETS * @sizeOf(i32);
    std.debug.assert(off == net_data_bytes);

    const actual_len = @embedFile(net_path).len;
    if (actual_len < net_data_bytes or actual_len > @sizeOf(NetworkWeights)) @compileError(std.fmt.comptimePrint(
        \\net file size mismatch
        \\  file     : {d} bytes
        \\  expected : {d} bytes of data ({d} with tail padding)
        \\  diff     : {d} bytes
        \\expected breakdown:
        \\  ft_weights {d}  (i16)
        \\  ft_biases  {d}  (i16)
        \\  l1_weights {d}  (i8)
        \\  l1_biases  {d}  (i32)
        \\  l2_weights {d}  (i32)
        \\  l2_biases  {d}  (i32)
        \\  l3_weights {d}  (i32)
        \\  l3_biases  {d}  (i32)
    , .{
        actual_len,
        net_data_bytes,
        @sizeOf(NetworkWeights),
        @as(i64, @intCast(actual_len)) - @as(i64, @intCast(net_data_bytes)),
        num_features * hidden_size * @sizeOf(i16),
        hidden_size * @sizeOf(i16),
        l1_size * NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(i8),
        NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(i32),
        l2_in_size * NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(i32),
        NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(i32),
        l3_size * NUM_OUTPUT_BUCKETS * @sizeOf(i32),
        NUM_OUTPUT_BUCKETS * @sizeOf(i32),
    }));
}

const net_tail_padding: usize = @sizeOf(NetworkWeights) - @embedFile(net_path).len;

const embedded_nnue_bytes align(@alignOf(NetworkWeights)) =
    @embedFile(net_path).* ++ [_]u8{0} ** net_tail_padding;

pub const L1Path = enum {
    dense,
    dense_dot,
    sparse_elem,
};

pub const l1_path: L1Path = if (has_byte_dot) .dense_dot else .dense;

var l1_weights_sparse: [NUM_OUTPUT_BUCKETS][l1_size][l2_size]i8 align(cache_line) = undefined;
var l1_weights_dense: [NUM_OUTPUT_BUCKETS][l2_size][l1_size]i8 align(cache_line) = undefined;
var l1_sdot_correction: [NUM_OUTPUT_BUCKETS][l2_size]i32 = undefined;
var l1_biases_f: [NUM_OUTPUT_BUCKETS][l2_size]f32 align(cache_line) = undefined;
var l2_weights_f: [NUM_OUTPUT_BUCKETS][l2_in_size][l3_size]f32 align(cache_line) = undefined;
var l2_biases_f: [NUM_OUTPUT_BUCKETS][l3_size]f32 align(cache_line) = undefined;
var l3_weights_f: [NUM_OUTPUT_BUCKETS][l3_size]f32 align(cache_line) = undefined;
var l3_biases_f: [NUM_OUTPUT_BUCKETS]f32 = undefined;

inline fn dequant(x: i32, scale: i64) f32 {
    return @floatCast(@as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(scale)));
}

fn prepareLayers(w: *const NetworkWeights) void {
    for (0..NUM_OUTPUT_BUCKETS) |b| {
        for (0..l2_size) |o| {
            var row_sum: i32 = 0;
            for (0..l1_size) |j| {
                const v = w.l1_weights[j][b][o];
                l1_weights_sparse[b][j][o] = v;
                l1_weights_dense[b][o][j] = v;
                row_sum += v;
            }
            l1_sdot_correction[b][o] = 128 * row_sum;
            l1_biases_f[b][o] = dequant(w.l1_biases[b][o], l1_bias_scale);
        }

        for (0..l3_size) |o| {
            for (0..l2_in_size) |j| {
                l2_weights_f[b][j][o] = dequant(w.l2_weights[j][b][o], l2_weight_scale);
            }
            l2_biases_f[b][o] = dequant(w.l2_biases[b][o], l2_bias_scale);
            l3_weights_f[b][o] = dequant(w.l3_weights[o][b], l3_weight_scale);
        }
        l3_biases_f[b] = dequant(w.l3_biases[b], l3_bias_scale);
    }
}

var net_weights: ?*const NetworkWeights = null;

pub fn initWeights() void {
    const w: *const NetworkWeights = @ptrCast(&embedded_nnue_bytes);
    net_weights = w;
    initFeatureIndexTable();
    prepareLayers(w);
}

inline fn mirRank(sq: u8) u8 {
    return sq ^ 56;
}

inline fn mirFile(sq: u8) u8 {
    return sq ^ 7;
}

inline fn shouldMirror(king_sq: u8) bool {
    return (king_sq & 7) >= 4;
}

inline fn perspectiveKingBucket(view: brd.Color, view_king_sq: u8) usize {
    var sq: u8 = if (view == .White) view_king_sq else mirRank(view_king_sq);
    if (shouldMirror(view_king_sq)) sq = mirFile(sq);
    const file: usize = @intCast(sq & 0b111);
    const rank: usize = @intCast(sq >> 3);
    return KING_BUCKETS_BASE[rank * 4 + file];
}

inline fn perspectiveSlotId(view: brd.Color, view_king_sq: u8) usize {
    const mirror_bit: usize = if (shouldMirror(view_king_sq)) 1 else 0;
    const bucket = perspectiveKingBucket(view, view_king_sq);
    return mirror_bit * NUM_KING_BUCKETS + bucket;
}

pub const NUM_FINNY_SLOTS: usize = 2 * NUM_KING_BUCKETS;

var feature_index_table: [brd.num_colors][64][brd.num_colors][6][64]u16 = undefined;
var slot_id_table: [brd.num_colors][64]u8 = undefined;

inline fn featureIndexSlow(
    view: brd.Color,
    view_king_sq: u8,
    piece_color: brd.Color,
    piece_type: brd.Pieces,
    square: u8,
) usize {
    var oriented_sq: u8 = if (view == .White) square else mirRank(square);
    if (shouldMirror(view_king_sq)) oriented_sq = mirFile(oriented_sq);
    const is_own: usize = if (view == piece_color) 0 else 1;
    const piece_offset = nnue_piece_to_index[is_own][@intFromEnum(piece_type)];
    const base_idx = @as(usize, oriented_sq) + @as(usize, piece_offset) * 64;
    return perspectiveKingBucket(view, view_king_sq) * features_per_bucket + base_idx;
}

fn initFeatureIndexTable() void {
    for (0..brd.num_colors) |view_i| {
        const view: brd.Color = @enumFromInt(view_i);
        for (0..64) |ksq_i| {
            const ksq: u8 = @intCast(ksq_i);
            slot_id_table[view_i][ksq_i] = @intCast((if (shouldMirror(ksq)) NUM_KING_BUCKETS else 0) + perspectiveKingBucket(view, ksq));
            for (0..brd.num_colors) |pc_i| {
                const pc: brd.Color = @enumFromInt(pc_i);
                for (0..6) |pt_i| {
                    const pt: brd.Pieces = @enumFromInt(pt_i);
                    for (0..64) |sq_i| {
                        feature_index_table[view_i][ksq_i][pc_i][pt_i][sq_i] =
                            @intCast(featureIndexSlow(view, ksq, pc, pt, @intCast(sq_i)));
                    }
                }
            }
        }
    }
}

pub inline fn featureIndex(
    view: brd.Color,
    view_king_sq: u8,
    piece_color: brd.Color,
    piece_type: brd.Pieces,
    square: u8,
) usize {
    return feature_index_table[@intFromEnum(view)][view_king_sq][@intFromEnum(piece_color)][@intFromEnum(piece_type)][square];
}

inline fn perspectiveSlotCached(view: brd.Color, king_sq: u8) usize {
    return slot_id_table[@intFromEnum(view)][king_sq];
}

fn materialBucket(gs: *const brd.GameState) usize {
    const occupied: u64 = gs.cur_position.getOccupancy();
    const piece_count: usize = @popCount(occupied);
    return @min((piece_count -| 2) / 4, NUM_OUTPUT_BUCKETS - 1);
}

const FeatureDelta = struct {
    piece_color: brd.Color,
    piece_type: brd.Pieces,
    square: u8,
};

const DirtyPieces = struct {
    adds: [2]FeatureDelta = undefined,
    subs: [2]FeatureDelta = undefined,
    num_adds: u8 = 0,
    num_subs: u8 = 0,

    inline fn addPiece(self: *DirtyPieces, color: brd.Color, piece: brd.Pieces, sq: u8) void {
        self.adds[self.num_adds] = .{ .piece_color = color, .piece_type = piece, .square = sq };
        self.num_adds += 1;
    }

    inline fn subPiece(self: *DirtyPieces, color: brd.Color, piece: brd.Pieces, sq: u8) void {
        self.subs[self.num_subs] = .{ .piece_color = color, .piece_type = piece, .square = sq };
        self.num_subs += 1;
    }
};

pub const Accumulator = struct {
    vals: [hidden_size]i16 align(cache_line),

    pub fn init() Accumulator {
        return .{ .vals = std.mem.zeroes([hidden_size]i16) };
    }

    pub fn initFromBias(self: *Accumulator) void {
        if (net_weights) |w| {
            self.vals = w.ft_biases;
        } else {
            self.vals = std.mem.zeroes([hidden_size]i16);
        }
    }

    inline fn vecs(self: *Accumulator) *[num_acc_vecs]I16Vec {
        return @ptrCast(&self.vals);
    }

    inline fn constVecs(self: *const Accumulator) *const [num_acc_vecs]I16Vec {
        return @ptrCast(&self.vals);
    }

    inline fn weightVecs(feature_idx: usize) *const [num_acc_vecs]I16Vec {
        return @ptrCast(&net_weights.?.ft_weights[feature_idx]);
    }

    pub fn activateFeature(self: *Accumulator, feature_idx: usize) void {
        if (net_weights == null) return;
        const dst = self.vecs();
        const src = weightVecs(feature_idx);
        if (TARGET == .sdot or TARGET == .neon) {
            asm volatile ("prfm pldl1keep, [%[p], #128]"
                :
                : [p] "r" (@as([*]const u8, @ptrCast(src))),
            );
        }
        var i: usize = 0;
        while (i + 4 <= num_acc_vecs) : (i += 4) {
            inline for (0..4) |u| dst[i + u] +%= src[i + u];
        }
        while (i < num_acc_vecs) : (i += 1) dst[i] +%= src[i];
    }

    pub fn deactivateFeature(self: *Accumulator, feature_idx: usize) void {
        if (net_weights == null) return;
        const dst = self.vecs();
        const src = weightVecs(feature_idx);
        if (TARGET == .sdot or TARGET == .neon) {
            asm volatile ("prfm pldl1keep, [%[p], #128]"
                :
                : [p] "r" (@as([*]const u8, @ptrCast(src))),
            );
        }
        var i: usize = 0;
        while (i + 4 <= num_acc_vecs) : (i += 4) {
            inline for (0..4) |u| dst[i + u] -%= src[i + u];
        }
        while (i < num_acc_vecs) : (i += 1) dst[i] -%= src[i];
    }

    fn addSubCopy(
        noalias self: *Accumulator,
        noalias parent: *const Accumulator,
        add_feat: usize,
        sub_feat: usize,
    ) void {
        const dst = self.vecs();
        const src = parent.constVecs();
        const add_w = weightVecs(add_feat);
        const sub_w = weightVecs(sub_feat);

        var i: usize = 0;
        while (i + 4 <= num_acc_vecs) : (i += 4) {
            inline for (0..4) |u| dst[i + u] = src[i + u] +% add_w[i + u] -% sub_w[i + u];
        }
        while (i < num_acc_vecs) : (i += 1) dst[i] = src[i] +% add_w[i] -% sub_w[i];
    }

    fn addSubSubCopy(
        noalias self: *Accumulator,
        noalias parent: *const Accumulator,
        add_feat: usize,
        sub1_feat: usize,
        sub2_feat: usize,
    ) void {
        const dst = self.vecs();
        const src = parent.constVecs();
        const add_w = weightVecs(add_feat);
        const sub1_w = weightVecs(sub1_feat);
        const sub2_w = weightVecs(sub2_feat);

        var i: usize = 0;
        while (i + 4 <= num_acc_vecs) : (i += 4) {
            inline for (0..4) |u|
                dst[i + u] = src[i + u] +% add_w[i + u] -% sub1_w[i + u] -% sub2_w[i + u];
        }
        while (i < num_acc_vecs) : (i += 1)
            dst[i] = src[i] +% add_w[i] -% sub1_w[i] -% sub2_w[i];
    }

    fn addAddSubSubCopy(
        noalias self: *Accumulator,
        noalias parent: *const Accumulator,
        add1_feat: usize,
        add2_feat: usize,
        sub1_feat: usize,
        sub2_feat: usize,
    ) void {
        const dst = self.vecs();
        const src = parent.constVecs();
        const add1_w = weightVecs(add1_feat);
        const add2_w = weightVecs(add2_feat);
        const sub1_w = weightVecs(sub1_feat);
        const sub2_w = weightVecs(sub2_feat);

        var i: usize = 0;
        while (i + 4 <= num_acc_vecs) : (i += 4) {
            inline for (0..4) |u|
                dst[i + u] = src[i + u] +% add1_w[i + u] +% add2_w[i + u] -% sub1_w[i + u] -% sub2_w[i + u];
        }
        while (i < num_acc_vecs) : (i += 1)
            dst[i] = src[i] +% add1_w[i] +% add2_w[i] -% sub1_w[i] -% sub2_w[i];
    }
};

fn applyLazyDeltaForPerspective(
    noalias state: *NNUEState,
    noalias parent: *const NNUEState,
    view_idx: usize,
) void {
    const dirty = &state.dirty;
    const view: brd.Color = @enumFromInt(view_idx);
    const king_sq = state.king_squares[view_idx];
    const parent_acc = parent.acc_ptr[view_idx];

    if (dirty.num_adds == 0 and dirty.num_subs == 0) {
        state.acc_ptr[view_idx] = parent_acc;
        return;
    }

    if (dirty.num_adds == 1 and dirty.num_subs == 1) {
        const add_idx = featureIndex(view, king_sq, dirty.adds[0].piece_color, dirty.adds[0].piece_type, dirty.adds[0].square);
        const sub_idx = featureIndex(view, king_sq, dirty.subs[0].piece_color, dirty.subs[0].piece_type, dirty.subs[0].square);
        state.accumulators[view_idx].addSubCopy(parent_acc, add_idx, sub_idx);
    } else if (dirty.num_adds == 1 and dirty.num_subs == 2) {
        const add_idx = featureIndex(view, king_sq, dirty.adds[0].piece_color, dirty.adds[0].piece_type, dirty.adds[0].square);
        const sub1_idx = featureIndex(view, king_sq, dirty.subs[0].piece_color, dirty.subs[0].piece_type, dirty.subs[0].square);
        const sub2_idx = featureIndex(view, king_sq, dirty.subs[1].piece_color, dirty.subs[1].piece_type, dirty.subs[1].square);
        state.accumulators[view_idx].addSubSubCopy(parent_acc, add_idx, sub1_idx, sub2_idx);
    } else if (dirty.num_adds == 2 and dirty.num_subs == 2) {
        const add1_idx = featureIndex(view, king_sq, dirty.adds[0].piece_color, dirty.adds[0].piece_type, dirty.adds[0].square);
        const add2_idx = featureIndex(view, king_sq, dirty.adds[1].piece_color, dirty.adds[1].piece_type, dirty.adds[1].square);
        const sub1_idx = featureIndex(view, king_sq, dirty.subs[0].piece_color, dirty.subs[0].piece_type, dirty.subs[0].square);
        const sub2_idx = featureIndex(view, king_sq, dirty.subs[1].piece_color, dirty.subs[1].piece_type, dirty.subs[1].square);
        state.accumulators[view_idx].addAddSubSubCopy(parent_acc, add1_idx, add2_idx, sub1_idx, sub2_idx);
    } else {
        state.accumulators[view_idx] = parent_acc.*;
    }
    state.acc_ptr[view_idx] = &state.accumulators[view_idx];
}

pub const NNUEState = struct {
    accumulators: [brd.num_colors]Accumulator,
    acc_ptr: [brd.num_colors]*const Accumulator,
    king_squares: [brd.num_colors]u8,
    dirty: DirtyPieces,
    needs_refresh: [brd.num_colors]bool,
    computed: [brd.num_colors]bool,

    pub fn init() NNUEState {
        return .{
            .accumulators = [_]Accumulator{Accumulator.init()} ** brd.num_colors,
            .acc_ptr = undefined,
            .king_squares = [_]u8{0} ** brd.num_colors,
            .dirty = .{},
            .needs_refresh = [_]bool{false} ** brd.num_colors,
            .computed = [_]bool{false} ** brd.num_colors,
        };
    }
};

pub const FinnyEntry = struct {
    accumulator: Accumulator,
    pieces: [brd.num_colors][brd.num_pieces]u64,

    pub fn reset(self: *FinnyEntry) void {
        self.accumulator.initFromBias();
        for (0..brd.num_colors) |c| {
            for (0..brd.num_pieces) |p| {
                self.pieces[c][p] = 0;
            }
        }
    }
};

pub const FinnyTable = struct {
    entries: [brd.num_colors][NUM_FINNY_SLOTS]FinnyEntry,

    pub fn init() FinnyTable {
        var ft: FinnyTable = undefined;
        ft.reset();
        return ft;
    }

    pub fn reset(self: *FinnyTable) void {
        for (0..brd.num_colors) |c| {
            for (0..NUM_FINNY_SLOTS) |s| {
                self.entries[c][s].reset();
            }
        }
    }
};

pub const NNUEStack = struct {
    states: [brd.max_game_moves + 1]NNUEState,
    finny: FinnyTable,
    current: usize,

    pub fn init() NNUEStack {
        return .{
            .states = undefined,
            .finny = FinnyTable.init(),
            .current = 0,
        };
    }

    pub inline fn top(self: *NNUEStack) *NNUEState {
        return &self.states[self.current];
    }

    pub inline fn push(self: *NNUEStack) void {
        const next = self.current + 1;
        self.states[next].king_squares = self.states[self.current].king_squares;
        self.states[next].dirty = .{};
        self.states[next].needs_refresh = [_]bool{false} ** brd.num_colors;
        self.states[next].computed = [_]bool{false} ** brd.num_colors;
        self.current = next;
    }

    pub inline fn pop(self: *NNUEStack) void {
        if (self.current > 0) self.current -= 1;
    }

    pub fn pushAndUpdate(
        self: *NNUEStack,
        gs: *const brd.GameState,
        m: brd.Move,
    ) void {
        const next = self.current + 1;
        const parent = &self.states[self.current];

        const changes = gs.dirtyPieces(m);
        var dirty = DirtyPieces{};
        for (changes.removedSlice()) |r| dirty.subPiece(r.piece.color, r.piece.piece, r.sq);
        for (changes.addedSlice()) |a| dirty.addPiece(a.piece.color, a.piece.piece, a.sq);

        var new_king_sqs = parent.king_squares;
        var i: u8 = 0;
        while (i < dirty.num_adds) : (i += 1) {
            const a = dirty.adds[i];
            if (a.piece_type == .King) {
                new_king_sqs[@intFromEnum(a.piece_color)] = a.square;
            }
        }

        var needs_refresh = [_]bool{false} ** brd.num_colors;
        inline for (0..brd.num_colors) |c| {
            const view = @as(brd.Color, @enumFromInt(c));
            const old_slot = perspectiveSlotCached(view, parent.king_squares[c]);
            const new_slot = perspectiveSlotCached(view, new_king_sqs[c]);
            if (old_slot != new_slot) {
                needs_refresh[c] = true;
            }
        }

        self.states[next].dirty = dirty;
        self.states[next].king_squares = new_king_sqs;
        self.states[next].needs_refresh = needs_refresh;
        self.states[next].computed = [_]bool{false} ** brd.num_colors;
        self.current = next;
    }

    fn ensureComputed(self: *NNUEStack, target: usize, gs: *const brd.GameState) void {
        if (net_weights == null) return;
        inline for (0..brd.num_colors) |c| {
            if (!self.states[target].computed[c]) {
                var first_dirty = target;
                while (first_dirty > 0 and !self.states[first_dirty - 1].computed[c]) {
                    first_dirty -= 1;
                }

                var has_refresh = false;
                var k = first_dirty;
                while (k <= target) : (k += 1) {
                    if (self.states[k].needs_refresh[c]) {
                        has_refresh = true;
                        break;
                    }
                }

                if (has_refresh) {
                    std.debug.assert(target == self.current);
                    refreshPerspectiveCached(
                        gs,
                        &self.states[target],
                        &self.finny,
                        @as(brd.Color, @enumFromInt(c)),
                    );
                } else {
                    var j = first_dirty;
                    while (j <= target) : (j += 1) {
                        applyLazyDeltaForPerspective(&self.states[j], &self.states[j - 1], c);
                        self.states[j].computed[c] = true;
                    }
                }
            }
        }
    }
};

inline fn refreshAccumulatorFromBoard(
    gs: *const brd.GameState,
    state: *NNUEState,
    view: brd.Color,
    view_king_sq: u8,
) void {
    const c = @intFromEnum(view);
    const acc = &state.accumulators[c];
    if (net_weights == null) {
        acc.vals = std.mem.zeroes([hidden_size]i16);
        return;
    }

    const dst = acc.vecs();
    const w = net_weights.?;
    const bv = acc.vecs();
    const biasv: *const [num_acc_vecs]I16Vec = @ptrCast(&w.ft_biases);
    var i: usize = 0;
    while (i + 4 <= num_acc_vecs) : (i += 4) {
        inline for (0..4) |u| bv[i + u] = biasv[i + u];
    }
    while (i < num_acc_vecs) : (i += 1) bv[i] = biasv[i];

    inline for (0..brd.num_colors) |ci| {
        inline for (0..6) |pi| {
            var bb = gs.cur_position.getPieceColorBoard(@enumFromInt(pi), @enumFromInt(ci));
            while (bb != 0) {
                const sq: u8 = @intCast(@ctz(bb));
                const idx = featureIndex(view, view_king_sq, @enumFromInt(ci), @enumFromInt(pi), sq);
                const row: *const [num_acc_vecs]I16Vec = @ptrCast(&w.ft_weights[idx]);

                var j: usize = 0;
                while (j + 4 <= num_acc_vecs) : (j += 4) {
                    inline for (0..4) |u| dst[j + u] +%= row[j + u];
                }
                while (j < num_acc_vecs) : (j += 1) dst[j] +%= row[j];
                bb &= bb - 1;
            }
        }
    }
}

fn refreshPerspective(gs: *const brd.GameState, state: *NNUEState, view: brd.Color) void {
    const c = @intFromEnum(view);
    const view_king_sq: u8 = gs.cur_position.kingSquare(view);
    state.king_squares[c] = view_king_sq;

    refreshAccumulatorFromBoard(gs, state, view, view_king_sq);

    state.acc_ptr[c] = &state.accumulators[c];
    state.needs_refresh[c] = false;
    state.computed[c] = true;
}

fn refreshPerspectiveCached(
    gs: *const brd.GameState,
    state: *NNUEState,
    finny: *FinnyTable,
    view: brd.Color,
) void {
    if (net_weights == null) return;
    const c = @intFromEnum(view);

    const view_king_sq: u8 = gs.cur_position.kingSquare(view);
    state.king_squares[c] = view_king_sq;
    const slot = perspectiveSlotCached(view, view_king_sq);
    const entry = &finny.entries[c][slot];

    for (std.meta.tags(brd.Color)) |piece_color| {
        const ci = @intFromEnum(piece_color);
        for (std.meta.tags(brd.Pieces)) |piece| {
            if (piece == .None) continue;
            const pi = @intFromEnum(piece);

            const current_bb = gs.cur_position.getPieceColorBoard(piece, piece_color);
            const cached_bb = entry.pieces[ci][pi];
            if (current_bb == cached_bb) continue;

            var added = current_bb & ~cached_bb;
            while (added != 0) {
                const sq: u8 = @intCast(@ctz(added));
                entry.accumulator.activateFeature(
                    featureIndex(view, view_king_sq, piece_color, piece, sq),
                );
                added &= added - 1;
            }

            var removed = cached_bb & ~current_bb;
            while (removed != 0) {
                const sq: u8 = @intCast(@ctz(removed));
                entry.accumulator.deactivateFeature(
                    featureIndex(view, view_king_sq, piece_color, piece, sq),
                );
                removed &= removed - 1;
            }

            entry.pieces[ci][pi] = current_bb;
        }
    }

    state.accumulators[c] = entry.accumulator;
    state.acc_ptr[c] = &state.accumulators[c];
    state.needs_refresh[c] = false;
    state.computed[c] = true;
}

pub fn refreshAccumulator(gs: *const brd.GameState, state: *NNUEState) void {
    refreshPerspective(gs, state, .White);
    refreshPerspective(gs, state, .Black);
    state.dirty = .{};
}

pub fn refreshStack(stack: *NNUEStack, gs: *const brd.GameState) void {
    refreshPerspectiveCached(gs, &stack.states[stack.current], &stack.finny, .White);
    refreshPerspectiveCached(gs, &stack.states[stack.current], &stack.finny, .Black);
    stack.states[stack.current].dirty = .{};
}

const NNZ_WORDS: usize = (l1_size + 63) / 64;
const NnzMask = [NNZ_WORDS]u64;

inline fn activateFtPairwise(
    acc: *const Accumulator,
    out: *align(cache_line) [l1_size]u8,
    vec_offset: usize,
    nnz: *NnzMask,
) u16 {
    const src = acc.constVecs();
    const dst: *[num_l1_vecs]U8Vec = @ptrCast(out);

    const zero_vec: I16Vec = @splat(0);
    const qa_vec: I16Vec = @splat(QA);
    var count: u16 = 0;

    for (0..num_pairwise_vecs) |v| {
        const a = @min(@max(src[v], zero_vec), qa_vec);
        const b = @min(@max(src[v + num_pairwise_vecs], zero_vec), qa_vec);

        const prod: U16Vec = @as(U16Vec, @intCast(a)) * @as(U16Vec, @intCast(b));
        const pack: U8Vec = @intCast(prod >> @as(U16Vec, @splat(ft_shift)));
        dst[vec_offset + v] = pack;

        const mask_type = std.meta.Int(.unsigned, vec_i16_len);
        const mask: mask_type = @bitCast(pack != @as(U8Vec, @splat(0)));
        const base_bit = vec_offset * vec_i16_len + v * vec_i16_len;
        nnz[base_bit / 64] |= @as(u64, mask) << @intCast(base_bit & 63);
        count += @intCast(@popCount(mask));
    }
    return count;
}

inline fn sparseThreshold() usize {
    return switch (TARGET) {
        .avx512_vnni => l1_size * 3 / 8,
        .avx512, .avx_vnni, .avx2 => l1_size / 2,
        .sdot => l1_size * 3 / 8,
        .neon => l1_size * 5 / 16,
        .sse2, .fallback => l1_size / 4,
    };
}

inline fn l1Sparse(
    ft_out: *align(cache_line) const [l1_size]u8,
    nnz: *const NnzMask,
    bucket: usize,
    out: *[l2_size]i32,
) void {
    comptime std.debug.assert(l2_size == 16);
    var acc_lo: L1I32x8 = @splat(0);
    var acc_hi: L1I32x8 = @splat(0);

    for (nnz, 0..) |word_value, word_idx| {
        var bits = word_value;
        while (bits != 0) {
            const bit: usize = @intCast(@ctz(bits));
            const j = word_idx * 64 + bit;
            sparseAccumulate16(&acc_lo, &acc_hi, &l1_weights_sparse[bucket][j], ft_out[j]);
            bits &= bits - 1;
        }
    }

    out[0..8].* = acc_lo;
    out[8..16].* = acc_hi;
}

inline fn l1DenseByteDot(
    ft_out: *align(cache_line) const [l1_size]u8,
    bucket: usize,
    out: *[l2_size]i32,
) void {
    const num_chunks = l1_size / dot_bytes;
    comptime std.debug.assert(num_chunks % 4 == 0);

    const acts: *const [num_chunks]DotU8 = @ptrCast(ft_out);
    const l1w = &l1_weights_dense[bucket];

    for (0..l2_size) |o| {
        const row: *const [num_chunks]DotI8 = @ptrCast(@alignCast(&l1w[o]));
        var sums: [4]DotAcc = @splat(@as(DotAcc, @splat(0)));

        var k: usize = 0;
        while (k < num_chunks) : (k += 4) {
            inline for (0..4) |a| {
                sums[a] = byteDotAccumulate(sums[a], acts[k + a], row[k + a]);
            }
        }

        var total = sums[0];
        inline for (1..4) |a| total += sums[a];
        var dot = @reduce(.Add, total);
        if (TARGET == .sdot) dot += l1_sdot_correction[bucket][o];
        out[o] = dot;
    }
}

inline fn l1DenseI16(
    ft_out: *align(cache_line) const [l1_size]u8,
    bucket: usize,
    out: *[l2_size]i32,
) void {
    const ft_vecs: *const [num_l1_vecs]U8Vec = @ptrCast(ft_out);
    const l1w = &l1_weights_dense[bucket];

    const ACC_COUNT = 4;
    comptime std.debug.assert(num_l1_vecs % ACC_COUNT == 0);

    for (0..l2_size) |o| {
        const row: *const [num_l1_vecs]I8Vec = @ptrCast(@alignCast(&l1w[o]));
        var sums: [ACC_COUNT]I32Vec = @splat(@as(I32Vec, @splat(0)));

        var j: usize = 0;
        while (j < num_l1_vecs) : (j += ACC_COUNT) {
            inline for (0..ACC_COUNT) |a| {
                const wv: I16Vec = @intCast(row[j + a]);
                const xv: I16Vec = @intCast(ft_vecs[j + a]);
                sums[a] = dotAccumulate(sums[a], xv, wv);
            }
        }

        var total_vec = sums[0];
        inline for (1..ACC_COUNT) |a| total_vec += sums[a];
        out[o] = @reduce(.Add, total_vec);
    }
}

pub fn evaluate(stack: *NNUEStack, side_to_move: brd.Color, gs: *const brd.GameState) i32 {
    if (net_weights == null) return 0;
    stack.ensureComputed(stack.current, gs);

    const state = stack.top();
    const bucket = materialBucket(gs);
    const stm: usize = @intFromEnum(side_to_move);
    const nstm = stm ^ 1;

    var ft_out: [l1_size]u8 align(cache_line) = undefined;
    var nnz = std.mem.zeroes(NnzMask);

    const nnz_stm = activateFtPairwise(state.acc_ptr[stm], &ft_out, 0, &nnz);
    const nnz_nstm = activateFtPairwise(state.acc_ptr[nstm], &ft_out, num_pairwise_vecs, &nnz);
    const nnz_count: usize = @as(usize, nnz_stm) + @as(usize, nnz_nstm);

    if (collect_sparsity) recordSparsityMask(&nnz, nnz_count);

    var l1_sums: [l2_size]i32 = undefined;
    if (nnz_count <= sparseThreshold()) {
        l1Sparse(&ft_out, &nnz, bucket, &l1_sums);
    } else if (has_byte_dot) {
        l1DenseByteDot(&ft_out, bucket, &l1_sums);
    } else {
        l1DenseI16(&ft_out, bucket, &l1_sums);
    }

    const L2Vec = @Vector(l2_size, f32);
    const l2_zero: L2Vec = @splat(0.0);
    const l2_one: L2Vec = @splat(1.0);
    const l1_int: @Vector(l2_size, i32) = l1_sums;
    const l1_x = @as(L2Vec, @floatFromInt(l1_int)) * @as(L2Vec, @splat(l1_dequant)) +
        @as(L2Vec, l1_biases_f[bucket]);

    var hl2: [l2_in_size]f32 = undefined;
    hl2[0..l2_size].* = @min(@max(l1_x, l2_zero), l2_one);
    hl2[l2_size..l2_in_size].* = @min(l1_x * l1_x, l2_one);

    const L3Vec = @Vector(l3_size, f32);
    var l2_acc: L3Vec = l2_biases_f[bucket];
    const l2w = &l2_weights_f[bucket];
    inline for (0..l2_in_size) |j| {
        l2_acc += @as(L3Vec, l2w[j]) * @as(L3Vec, @splat(hl2[j]));
    }
    const hl3 = @min(@max(l2_acc, @as(L3Vec, @splat(0.0))), @as(L3Vec, @splat(1.0)));

    const l3w: L3Vec = l3_weights_f[bucket];
    const out = l3_biases_f[bucket] + @reduce(.Add, l3w * hl3);

    const scaled = @round(out * EVAL_SCALE);
    return @intFromFloat(std.math.clamp(scaled, -32000.0, 32000.0));
}

pub const collect_sparsity = false;

var sp_calls: std.atomic.Value(u64) = .init(0);
var sp_nonzero: std.atomic.Value(u64) = .init(0);
var sp_blocks4: std.atomic.Value(u64) = .init(0);

const l1_quads = l1_size / 4;

fn countSparsity(ft_out: *align(cache_line) const [l1_size]u8) struct { nonzero: u32, blocks4: u32 } {
    const Mask = std.meta.Int(.unsigned, vec_i16_len);
    const zero: U8Vec = @splat(0);
    const vecs: *const [num_l1_vecs]U8Vec = @ptrCast(ft_out);

    var nonzero: u32 = 0;
    for (0..num_l1_vecs) |v| {
        const m: Mask = @bitCast(vecs[v] != zero);
        nonzero += @popCount(m);
    }

    const quads: *const [l1_quads]u32 = @ptrCast(ft_out);
    var blocks4: u32 = 0;
    for (quads) |q| {
        if (q != 0) blocks4 += 1;
    }
    return .{ .nonzero = nonzero, .blocks4 = blocks4 };
}

fn recordSparsityMask(nnz: *const NnzMask, count: usize) void {
    _ = sp_calls.fetchAdd(1, .monotonic);
    _ = sp_nonzero.fetchAdd(count, .monotonic);

    var blocks4: u64 = 0;
    for (0..l1_quads) |q| {
        const byte_base = q * 4;
        const word = byte_base / 64;
        const bit = byte_base & 63;
        const mask: u64 = if (bit <= 60)
            @as(u64, 0xF) << @intCast(bit)
        else
            ((@as(u64, 0xF) << @intCast(bit)) & std.math.maxInt(u64));
        if ((nnz[word] & mask) != 0) blocks4 += 1;
    }
    _ = sp_blocks4.fetchAdd(blocks4, .monotonic);
}

fn recordSparsity(ft_out: *align(cache_line) const [l1_size]u8) void {
    const c = countSparsity(ft_out);
    _ = sp_calls.fetchAdd(1, .monotonic);
    _ = sp_nonzero.fetchAdd(c.nonzero, .monotonic);
    _ = sp_blocks4.fetchAdd(c.blocks4, .monotonic);
}

pub fn resetSparsity() void {
    sp_calls.store(0, .monotonic);
    sp_nonzero.store(0, .monotonic);
    sp_blocks4.store(0, .monotonic);
}

pub fn reportSparsity() void {
    const calls = sp_calls.load(.monotonic);
    if (calls == 0) {
        std.debug.print("sparsity: no evals recorded (is collect_sparsity true?)\n", .{});
        return;
    }

    const nz = @as(f64, @floatFromInt(sp_nonzero.load(.monotonic))) / @as(f64, @floatFromInt(calls));
    const b4 = @as(f64, @floatFromInt(sp_blocks4.load(.monotonic))) / @as(f64, @floatFromInt(calls));
    const total: f64 = @floatFromInt(l1_size);

    const dense_macs = total * @as(f64, l2_size);
    const elem_macs = nz * @as(f64, l2_size);
    const blk4_macs = b4 * 4.0 * @as(f64, l2_size);

    std.debug.print(
        \\sparsity over {d} evals
        \\  nonzero activations : {d:.1} / {d}  ({d:.1}% zero)
        \\  live 4-blocks       : {d:.1} / {d}  ({d:.1}% skipped)
        \\  MACs  dense         : {d:.0}
        \\  MACs  sparse_elem   : {d:.0}  ({d:.1}x fewer)
        \\  MACs  sparse_block4 : {d:.0}  ({d:.1}x fewer)
        \\  sparse threshold    : {d}
        \\  kernel               : {s}
        \\
    , .{
        calls,
        nz,
        total,
        100.0 * (1.0 - nz / total),
        b4,
        @as(f64, l1_quads),
        100.0 * (1.0 - b4 / @as(f64, l1_quads)),
        dense_macs,
        elem_macs,
        if (elem_macs == 0) 0.0 else dense_macs / elem_macs,
        blk4_macs,
        if (blk4_macs == 0) 0.0 else dense_macs / blk4_macs,
        sparseThreshold(),
        @tagName(TARGET),
    });
}

pub fn sparsityProbe(stack: *NNUEStack, side_to_move: brd.Color, gs: *const brd.GameState) struct { nonzero: u32, blocks4: u32 } {
    stack.ensureComputed(stack.current, gs);
    const state = stack.top();
    const stm: usize = @intFromEnum(side_to_move);

    var ft_out: [l1_size]u8 align(cache_line) = undefined;
    var nnz = std.mem.zeroes(NnzMask);
    const count = activateFtPairwise(state.acc_ptr[stm], &ft_out, 0, &nnz);
    const count2 = activateFtPairwise(state.acc_ptr[1 - stm], &ft_out, num_pairwise_vecs, &nnz);

    var blocks4: u32 = 0;
    for (0..l1_quads) |q| {
        const byte_base = q * 4;
        const word = byte_base / 64;
        const bit = byte_base & 63;
        if ((nnz[word] & (@as(u64, 0xF) << @intCast(bit))) != 0) blocks4 += 1;
    }

    return .{
        .nonzero = count + count2,
        .blocks4 = blocks4,
    };
}
