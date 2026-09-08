const std = @import("std");
const builtin = @import("builtin");
const brd = @import("board");
const moves = @import("moves");

pub const net_path = "nets/Alkaid.bin";

pub const features_per_bucket = 2 * brd.num_pieces * brd.num_squares;

pub const NUM_KING_BUCKETS: usize = 16;

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

pub const hidden_size = 1536;
pub const pairwise_size = hidden_size / 2;
pub const l1_size = 2 * pairwise_size;
pub const l2_size = 16;
pub const l3_size = 32;

comptime {
    std.debug.assert(hidden_size % 2 == 0);
    std.debug.assert(l1_size == hidden_size);
}

const QA: i16 = 255;
const QB: i32 = 64;
const ft_shift: u4 = 9;

const l1_input_scale: f32 = @as(f32, @floatFromInt(QA)) * @as(f32, @floatFromInt(QA)) /
    @as(f32, 1 << ft_shift);

const l1_dequant: f32 = 1.0 / (l1_input_scale * @as(f32, @floatFromInt(QB)));

const NUM_OUTPUT_BUCKETS: usize = 8;
const EVAL_SCALE: f32 = 128.0;
const cache_line = std.atomic.cache_line;

const CpuTarget = enum { avx2, sse2, aarch64, fallback };

const OutVec = @Vector(l2_size, i32);

pub const TARGET: CpuTarget = blk: {
    const cpu = builtin.cpu;
    switch (cpu.arch) {
        .x86_64 => {
            if (std.Target.x86.featureSetHas(cpu.features, .avx2)) break :blk .avx2;
            if (std.Target.x86.featureSetHas(cpu.features, .sse2)) break :blk .sse2;
        },
        .aarch64 => break :blk .aarch64,
        else => {},
    }
    break :blk .fallback;
};

const vec_i16_len: comptime_int = std.simd.suggestVectorLength(i16) orelse 8;
const vec_i32_len: comptime_int = vec_i16_len / 2;
const num_acc_vecs: usize = hidden_size / vec_i16_len;
const num_pairwise_vecs: usize = pairwise_size / vec_i16_len;
const num_l1_vecs: usize = l1_size / vec_i16_len;

const I16Vec = @Vector(vec_i16_len, i16);
const I32Vec = @Vector(vec_i32_len, i32);
const U16Vec = @Vector(vec_i16_len, u16);
const I8Vec = @Vector(vec_i16_len, i8);

inline fn maddwd(a: I16Vec, b: I16Vec) I32Vec {
    return switch (TARGET) {
        .avx2 => asm ("vpmaddwd %[b], %[a], %[ret]"
        : [ret] "=x" (-> I32Vec),
        : [a] "x" (a),
    [b] "x" (b),
    ),

        .sse2 => asm ("pmaddwd %[b], %[a]"
        : [ret] "=x" (-> I32Vec),
        : [a] "0" (a),
    [b] "x" (b),
    ),
        .aarch64 => unreachable,
        .fallback => blk: {
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
        .aarch64 => blk: {
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


inline fn dequantiseL1(acc: OutVec, bias: *const [l2_size]f32, out: *[l2_size]f32) void {
    const FVec = @Vector(l2_size, f32);
    const x: FVec = @as(FVec, @floatFromInt(acc)) * @as(FVec, @splat(l1_dequant)) +
        @as(FVec, bias.*);
    const c = @min(@max(x, @as(FVec, @splat(0.0))), @as(FVec, @splat(1.0)));
    out.* = c * c;
}

pub const dot_bytes: usize = if (has_vnni) 32 else 16;

const DotIn = @Vector(dot_bytes, i8);
const DotAcc = @Vector(dot_bytes / 4, i32);

pub const has_sdot: bool = builtin.cpu.arch == .aarch64 and
    std.Target.aarch64.featureSetHas(builtin.cpu.features, .dotprod);

pub const has_vnni: bool = builtin.cpu.arch == .x86_64 and
    (std.Target.x86.featureSetHas(builtin.cpu.features, .avxvnni) or
        std.Target.x86.featureSetHas(builtin.cpu.features, .avx512vnni));

pub const has_byte_dot: bool = has_sdot or has_vnni;

inline fn byteDotAccumulate(sum: DotAcc, a: DotIn, b: DotIn) DotAcc {
    if (has_sdot) {
        return asm ("sdot %[d].4s, %[n].16b, %[m].16b"
            : [d] "=w" (-> DotAcc),
            : [n] "w" (a),
              [m] "w" (b),
              [_] "0" (sum),
        );
    }

    if (has_vnni) {
        return asm ("vpdpbusd %[m], %[n], %[d]"
            : [d] "=x" (-> DotAcc),
            : [n] "x" (a),
              [m] "x" (b),
              [_] "0" (sum),
        );
    }

    var out = sum;
    inline for (0..dot_bytes / 4) |lane| {
        var acc: i32 = out[lane];
        inline for (0..4) |k| {
            acc += @as(i32, a[lane * 4 + k]) * @as(i32, b[lane * 4 + k]);
        }
        out[lane] = acc;
    }
    return out;
}

inline fn screlu(x: f32) f32 {
    const c = std.math.clamp(x, 0.0, 1.0);
    return c * c;
}

const nnue_piece_to_index = [2][6]u8{
[_]u8{ 0, 1, 2, 3, 4, 5 }, // Pawn, Knight, Bishop, Rook, Queen, King
[_]u8{ 6, 7, 8, 9, 10, 11 }, // Pawn, Knight, Bishop, Rook, Queen, King
};

pub const NetworkWeights = extern struct {
    ft_weights: [num_features][hidden_size]i16 align(cache_line),
    ft_biases: [hidden_size]i16 align(cache_line),

    l1_weights: [NUM_OUTPUT_BUCKETS][l2_size][l1_size]i8 align(cache_line),
    l1_biases: [NUM_OUTPUT_BUCKETS][l2_size]f32 align(cache_line),

    l2_weights: [NUM_OUTPUT_BUCKETS][l3_size][l2_size]f32 align(cache_line),
    l2_biases: [NUM_OUTPUT_BUCKETS][l3_size]f32 align(cache_line),

    l3_weights: [NUM_OUTPUT_BUCKETS][l3_size]f32 align(cache_line),
    l3_biases: [NUM_OUTPUT_BUCKETS]f32,
};

pub const net_data_bytes: usize = blk: {
    var n: usize = 0;
    n += num_features * hidden_size * @sizeOf(i16);
    n += hidden_size * @sizeOf(i16);
    n += NUM_OUTPUT_BUCKETS * l2_size * l1_size * @sizeOf(i8);
    n += NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(f32);
    n += NUM_OUTPUT_BUCKETS * l3_size * l2_size * @sizeOf(f32);
    n += NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(f32);
    n += NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(f32);
    n += NUM_OUTPUT_BUCKETS * @sizeOf(f32);
    break :blk n;
};

comptime {
    var off: usize = 0;
    std.debug.assert(@offsetOf(NetworkWeights, "ft_weights") == off);
    off += num_features * hidden_size * @sizeOf(i16);
    std.debug.assert(@offsetOf(NetworkWeights, "ft_biases") == off);
    off += hidden_size * @sizeOf(i16);
    std.debug.assert(@offsetOf(NetworkWeights, "l1_weights") == off);
    off += NUM_OUTPUT_BUCKETS * l2_size * l1_size * @sizeOf(i8);
    std.debug.assert(@offsetOf(NetworkWeights, "l1_biases") == off);
    off += NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(f32);
    std.debug.assert(@offsetOf(NetworkWeights, "l2_weights") == off);
    off += NUM_OUTPUT_BUCKETS * l3_size * l2_size * @sizeOf(f32);
    std.debug.assert(@offsetOf(NetworkWeights, "l2_biases") == off);
    off += NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(f32);
    std.debug.assert(@offsetOf(NetworkWeights, "l3_weights") == off);
    off += NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(f32);
    std.debug.assert(@offsetOf(NetworkWeights, "l3_biases") == off);
    off += NUM_OUTPUT_BUCKETS * @sizeOf(f32);
    std.debug.assert(off == net_data_bytes);

    const actual_len = @embedFile(net_path).len;
    if (actual_len < net_data_bytes or actual_len > @sizeOf(NetworkWeights)) @compileError(std.fmt.comptimePrint(
        \\net file size mismatch
        \\  file     : {d} bytes
        \\  expected : {d} bytes of data ({d} with tail padding)
        \\  diff     : {d} bytes
        \\expected breakdown:
        \\  ft_weights {d}
        \\  ft_biases  {d}
        \\  l1_weights {d}  (i8)
        \\  l1_biases  {d}  (f32)
        \\  l2_weights {d}  (f32)
        \\  l2_biases  {d}  (f32)
        \\  l3_weights {d}  (f32)
        \\  l3_biases  {d}  (f32)
    , .{
        actual_len,
        net_data_bytes,
        @sizeOf(NetworkWeights),
        @as(i64, @intCast(actual_len)) - @as(i64, @intCast(net_data_bytes)),
        num_features * hidden_size * @sizeOf(i16),
        hidden_size * @sizeOf(i16),
        NUM_OUTPUT_BUCKETS * l2_size * l1_size * @sizeOf(i8),
        NUM_OUTPUT_BUCKETS * l2_size * @sizeOf(f32),
        NUM_OUTPUT_BUCKETS * l3_size * l2_size * @sizeOf(f32),
        NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(f32),
        NUM_OUTPUT_BUCKETS * l3_size * @sizeOf(f32),
        NUM_OUTPUT_BUCKETS * @sizeOf(f32),
    }));
}

const net_tail_padding: usize = @sizeOf(NetworkWeights) - @embedFile(net_path).len;

const embedded_nnue_bytes align(@alignOf(NetworkWeights)) =
    @embedFile(net_path).* ++ [_]u8{0} ** net_tail_padding;

pub const L1Path = enum {
    dense,
    dense_dot,
    sparse_elem,
    sparse_block4,
};

pub const has_block_dot_asm = false;

pub const l1_path: L1Path =
    if (has_byte_dot and has_block_dot_asm) .sparse_block4 else if (has_byte_dot) .dense_dot else .dense;

pub const l1_block: usize = switch (l1_path) {
    .dense, .dense_dot, .sparse_elem => 1,
    .sparse_block4 => 4,
};

const num_l1_blocks = l1_size / l1_block;



var l1_weights_sparse: [NUM_OUTPUT_BUCKETS][num_l1_blocks][l2_size * l1_block]i8 align(cache_line) = undefined;

/// L2 weights transposed to input-major: for input j, all l3_size outputs
/// contiguous. Lets L2 run as 16 column FMAs into one 32-lane accumulator
/// instead of 32 horizontal reductions, which serialise badly.
var l2_weights_t: [NUM_OUTPUT_BUCKETS][l2_size][l3_size]f32 align(cache_line) = undefined;

fn permuteWeights(w: *const NetworkWeights) void {
    for (0..NUM_OUTPUT_BUCKETS) |b| {
        for (0..l3_size) |o| {
            for (0..l2_size) |j| {
                l2_weights_t[b][j][o] = w.l2_weights[b][o][j];
            }
        }
    }

    for (0..NUM_OUTPUT_BUCKETS) |b| {
        for (0..l2_size) |o| {
            for (0..l1_size) |j| {
                l1_weights_sparse[b][j / l1_block][o * l1_block + (j % l1_block)] = w.l1_weights[b][o][j];
            }
        }
    }
}

var net_weights: ?*const NetworkWeights = null;

pub fn initWeights() void {
    const w: *const NetworkWeights = @ptrCast(&embedded_nnue_bytes);
    net_weights = w;
    permuteWeights(w);
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

pub fn featureIndex(
view: brd.Color,
view_king_sq: u8,
piece_color: brd.Color,
piece_type: brd.Pieces,
square: u8,
) usize {
    var oriented_sq: u8 = if (view == .White) square else mirRank(square);
    if (shouldMirror(view_king_sq)) {
        oriented_sq = mirFile(oriented_sq);
    }
    const is_own: usize = if (view == piece_color) 0 else 1;
    const piece_idx = @intFromEnum(piece_type);
    const piece_offset = nnue_piece_to_index[is_own][piece_idx];
    const base_idx: usize = @as(usize, oriented_sq) + (@as(usize, piece_offset) * 64);

    const bucket = perspectiveKingBucket(view, view_king_sq);
    return bucket * features_per_bucket + base_idx;
}

inline fn prefetchFeatureRow(feature_idx: usize) void {
    const w = net_weights orelse return;
    const row: [*]const u8 = @ptrCast(&w.ft_weights[feature_idx]);
    @prefetch(row, .{ .rw = .read, .locality = 3, .cache = .data });
    @prefetch(row + 1024, .{ .rw = .read, .locality = 3, .cache = .data });
    @prefetch(row + 2048, .{ .rw = .read, .locality = 3, .cache = .data });
}

fn materialBucket(board: *const brd.Board) usize {
    const occupied: u64 = board.color_bb[0] | board.color_bb[1];
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
        if (TARGET == .aarch64) {
            asm volatile ("prfm pldl1keep, [%[p], #128]"
                :
                : [p] "r" (@as([*]const u8, @ptrCast(src))),
            );
        }
        for (0..num_acc_vecs) |i| {
            dst[i] +%= src[i];
        }
    }

    pub fn deactivateFeature(self: *Accumulator, feature_idx: usize) void {
        if (net_weights == null) return;
        const dst = self.vecs();
        const src = weightVecs(feature_idx);
        if (TARGET == .aarch64) {
            asm volatile ("prfm pldl1keep, [%[p], #128]"
                :
                : [p] "r" (@as([*]const u8, @ptrCast(src))),
            );
        }
        for (0..num_acc_vecs) |i| {
            dst[i] -%= src[i];
        }
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

        for (0..num_acc_vecs) |i| {
            dst[i] = src[i] +% add_w[i] -% sub_w[i];
        }
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

        for (0..num_acc_vecs) |i| {
            dst[i] = src[i] +% add_w[i] -% sub1_w[i] -% sub2_w[i];
        }
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

        for (0..num_acc_vecs) |i| {
            dst[i] = src[i] +% add1_w[i] +% add2_w[i] -% sub1_w[i] -% sub2_w[i];
        }
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
    board: *const brd.Board,
    move_data: moves.EncodedMove,
) void {
        const next = self.current + 1;
        var dirty = DirtyPieces{};
        const parent = &self.states[self.current];

        const moving_color = board.toMove();
        const opp_color = moving_color.opposite();
        const from_sq: u8 = @intCast(move_data.start_square);
        const to_sq: u8 = @intCast(move_data.end_square);
        const piece_type: brd.Pieces = @enumFromInt(move_data.piece);

        if (move_data.castling == 1) {
            const rook_from: u8 = if (to_sq > from_sq)
            (if (moving_color == .White) @as(u8, 7) else @as(u8, 63))
                else
            (if (moving_color == .White) @as(u8, 0) else @as(u8, 56));
            const rook_to: u8 = if (to_sq > from_sq)
            (if (moving_color == .White) @as(u8, 5) else @as(u8, 61))
                else
            (if (moving_color == .White) @as(u8, 3) else @as(u8, 59));
            dirty.addPiece(moving_color, .King, to_sq);
            dirty.addPiece(moving_color, .Rook, rook_to);
            dirty.subPiece(moving_color, .King, from_sq);
            dirty.subPiece(moving_color, .Rook, rook_from);
        } else if (move_data.en_passant == 1) {
            const ep_pawn_sq: u8 =
            if (moving_color == .White) to_sq - 8 else to_sq + 8;
            dirty.addPiece(moving_color, .Pawn, to_sq);
            dirty.subPiece(moving_color, .Pawn, from_sq);
            dirty.subPiece(opp_color, .Pawn, ep_pawn_sq);
        } else if (move_data.promoted_piece != 0) {
            const promoted_type: brd.Pieces = @enumFromInt(move_data.promoted_piece);
            dirty.subPiece(moving_color, .Pawn, from_sq);
            if (move_data.capture == 1) {
                const captured_type: brd.Pieces = @enumFromInt(move_data.captured_piece);
                dirty.subPiece(opp_color, captured_type, to_sq);
            }
            dirty.addPiece(moving_color, promoted_type, to_sq);
        } else {
            if (move_data.capture == 1) {
                const captured_type: brd.Pieces = @enumFromInt(move_data.captured_piece);
                dirty.subPiece(opp_color, captured_type, to_sq);
            }
            dirty.addPiece(moving_color, piece_type, to_sq);
            dirty.subPiece(moving_color, piece_type, from_sq);
        }

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
            const old_slot = perspectiveSlotId(view, parent.king_squares[c]);
            const new_slot = perspectiveSlotId(view, new_king_sqs[c]);
            if (old_slot != new_slot) {
                needs_refresh[c] = true;
            }
        }

        if (net_weights != null) {
            for (0..brd.num_colors) |c| {
                if (needs_refresh[c]) continue;
                const view: brd.Color = @enumFromInt(c);
                const ksq = new_king_sqs[c];
                var k: u8 = 0;
                while (k < dirty.num_adds) : (k += 1) {
                    const d = dirty.adds[k];
                    prefetchFeatureRow(featureIndex(view, ksq, d.piece_color, d.piece_type, d.square));
                }
                k = 0;
                while (k < dirty.num_subs) : (k += 1) {
                    const d = dirty.subs[k];
                    prefetchFeatureRow(featureIndex(view, ksq, d.piece_color, d.piece_type, d.square));
                }
            }
        }

        self.states[next].dirty = dirty;
        self.states[next].king_squares = new_king_sqs;
        self.states[next].needs_refresh = needs_refresh;
        self.states[next].computed = [_]bool{false} ** brd.num_colors;
        self.current = next;
    }

    fn ensureComputed(self: *NNUEStack, target: usize, board: *const brd.Board) void {
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
                    board,
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

fn refreshPerspective(board: *const brd.Board, state: *NNUEState, view: brd.Color) void {
    const c = @intFromEnum(view);
    const king_bb = board.piece_bb[c][@intFromEnum(brd.Pieces.King)];
    const view_king_sq: u8 = @intCast(@ctz(king_bb));
    state.king_squares[c] = view_king_sq;

    state.accumulators[c].initFromBias();

    for (std.meta.tags(brd.Color)) |piece_color| {
        const ci = @intFromEnum(piece_color);
        for (std.meta.tags(brd.Pieces)) |piece| {
            if (piece == .None) continue;
            const pi = @intFromEnum(piece);
            var bb = board.piece_bb[ci][pi];
            while (bb != 0) {
                const sq: u8 = @intCast(@ctz(bb));
                state.accumulators[c].activateFeature(
                featureIndex(view, view_king_sq, piece_color, piece, sq),
            );
                bb &= bb - 1;
            }
        }
    }

    state.acc_ptr[c] = &state.accumulators[c];
    state.needs_refresh[c] = false;
    state.computed[c] = true;
}

fn refreshPerspectiveCached(
board: *const brd.Board,
state: *NNUEState,
finny: *FinnyTable,
view: brd.Color,
) void {
    if (net_weights == null) return;
    const c = @intFromEnum(view);

    const king_bb = board.piece_bb[c][@intFromEnum(brd.Pieces.King)];
    const view_king_sq: u8 = @intCast(@ctz(king_bb));
    state.king_squares[c] = view_king_sq;
    const slot = perspectiveSlotId(view, view_king_sq);
    const entry = &finny.entries[c][slot];

    for (std.meta.tags(brd.Color)) |piece_color| {
        const ci = @intFromEnum(piece_color);
        for (std.meta.tags(brd.Pieces)) |piece| {
            if (piece == .None) continue;
            const pi = @intFromEnum(piece);

            const current_bb = board.piece_bb[ci][pi];
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

pub fn refreshAccumulator(board: *const brd.Board, state: *NNUEState) void {
    refreshPerspective(board, state, .White);
    refreshPerspective(board, state, .Black);
    state.dirty = .{};
}

pub fn refreshStack(stack: *NNUEStack, board: *const brd.Board) void {
    refreshPerspectiveCached(board, &stack.states[stack.current], &stack.finny, .White);
    refreshPerspectiveCached(board, &stack.states[stack.current], &stack.finny, .Black);
    stack.states[stack.current].dirty = .{};
}

fn activateFtPairwise(
    acc: *const Accumulator,
    out: *align(cache_line) [l1_size]i8,
    vec_offset: usize,
) void {
    const src = acc.constVecs();
    const dst: *[num_l1_vecs]I8Vec = @ptrCast(out);

    const zero_vec: I16Vec = @splat(0);
    const qa_vec: I16Vec = @splat(QA);

    for (0..num_pairwise_vecs) |v| {
        const a = @min(@max(src[v], zero_vec), qa_vec);
        const b = @min(@max(src[v + num_pairwise_vecs], zero_vec), qa_vec);

        const prod: U16Vec = @as(U16Vec, @intCast(a)) * @as(U16Vec, @intCast(b));
        dst[vec_offset + v] = @intCast(prod >> @as(U16Vec, @splat(ft_shift)));
    }
}

pub fn evaluate(stack: *NNUEStack, side_to_move: brd.Color, board: *const brd.Board) i32 {
    const w = net_weights orelse return 0;
    stack.ensureComputed(stack.current, board);

    const state = stack.top();
    const bucket = materialBucket(board);
    const stm: usize = @intFromEnum(side_to_move);
    const nstm: usize = 1 - stm;

    var ft_out: [l1_size]i8 align(cache_line) = undefined;
    activateFtPairwise(state.acc_ptr[stm], &ft_out, 0);
    activateFtPairwise(state.acc_ptr[nstm], &ft_out, num_pairwise_vecs);

    if (collect_sparsity) recordSparsity(&ft_out);

    const ft_vecs: *const [num_l1_vecs]I8Vec = @ptrCast(&ft_out);

    const l1b = &w.l1_biases[bucket];
    var l1_out: [l2_size]f32 = undefined;

    switch (l1_path) {
        .sparse_elem => {
            const Mask = std.meta.Int(.unsigned, vec_i16_len);
            const zero_vec: I8Vec = @splat(0);

            var nnz: [l1_size]u16 = undefined;
            var count: usize = 0;

            for (0..num_l1_vecs) |v| {
                var mask: Mask = @bitCast(ft_vecs[v] != zero_vec);
                const base: u16 = @intCast(v * vec_i16_len);
                while (mask != 0) {
                    nnz[count] = base + @ctz(mask);
                    count += 1;
                    mask &= mask - 1;
                }
            }

            comptime std.debug.assert(l1_block == 1);

            var acc: OutVec = @splat(0);
            const rows = &l1_weights_sparse[bucket];

            for (nnz[0..count]) |j| {
                const wv: @Vector(l2_size, i8) = rows[j];
                const xv: OutVec = @splat(@intCast(ft_out[j]));
                acc += @as(OutVec, @intCast(wv)) * xv;
            }

            dequantiseL1(acc, l1b, &l1_out);
        },

        .sparse_block4 => {
            comptime std.debug.assert(l1_block == 4);
            const blocks: *const [num_l1_blocks]u32 = @ptrCast(&ft_out);

            const lanes = 8;
            const BlkVec = @Vector(lanes, u32);
            const zero_blk: BlkVec = @splat(0);

            var nnz: [num_l1_blocks]u16 = undefined;
            var count: usize = 0;

            var v: usize = 0;
            while (v < num_l1_blocks / lanes) : (v += 1) {
                const chunk: BlkVec = blocks[v * lanes ..][0..lanes].*;
                var mask: u8 = @bitCast(chunk != zero_blk);
                const base: u16 = @intCast(v * lanes);
                while (mask != 0) {
                    nnz[count] = base + @ctz(mask);
                    count += 1;
                    mask &= mask - 1;
                }
            }

            var acc: OutVec = @splat(0);
            const rows = &l1_weights_sparse[bucket];

            for (nnz[0..count]) |k| {
                const x: [l1_block]i8 = ft_out[k * l1_block ..][0..l1_block].*;
                inline for (0..l1_block) |t| {
                    var wv: @Vector(l2_size, i8) = undefined;
                    inline for (0..l2_size) |o| wv[o] = rows[k][o * l1_block + t];
                    const xv: OutVec = @splat(@intCast(x[t]));
                    acc += @as(OutVec, @intCast(wv)) * xv;
                }
            }

            dequantiseL1(acc, l1b, &l1_out);
        },

        .dense_dot => {
            const num_chunks = l1_size / dot_bytes;
            const ACC_COUNT = 4;
            comptime std.debug.assert(num_chunks % ACC_COUNT == 0);

            const acts: *const [num_chunks]DotIn = @ptrCast(&ft_out);
            const l1w = &w.l1_weights[bucket];

            for (0..l2_size) |o| {
                const row: *const [num_chunks]DotIn = @ptrCast(@alignCast(&l1w[o]));

                var sums: [ACC_COUNT]DotAcc = @splat(@as(DotAcc, @splat(0)));
                var k: usize = 0;
                while (k < num_chunks) {
                    inline for (0..ACC_COUNT) |a| {
                        sums[a] = byteDotAccumulate(sums[a], acts[k + a], row[k + a]);
                    }
                    k += ACC_COUNT;
                }

                var total = sums[0];
                inline for (1..ACC_COUNT) |a| total += sums[a];

                l1_out[o] = screlu(@as(f32, @floatFromInt(@reduce(.Add, total))) *
                    l1_dequant + l1b[o]);
            }
        },

        .dense => {
            const ACC_COUNT = 4;
            comptime std.debug.assert(num_l1_vecs % ACC_COUNT == 0);

            const l1w = &w.l1_weights[bucket];

            for (0..l2_size) |o| {
                const row: *const [num_l1_vecs]I8Vec = @ptrCast(@alignCast(&l1w[o]));

                var sums: [ACC_COUNT]I32Vec = @splat(@as(I32Vec, @splat(0)));
                var j: usize = 0;
                while (j < num_l1_vecs) {
                    inline for (0..ACC_COUNT) |a| {
                        const wv: I16Vec = @intCast(row[j + a]);
                        const xv: I16Vec = @intCast(ft_vecs[j + a]);
                        sums[a] = dotAccumulate(sums[a], xv, wv);
                    }
                    j += ACC_COUNT;
                }

                var total_vec = sums[0];
                inline for (1..ACC_COUNT) |a| total_vec += sums[a];

                l1_out[o] = screlu(@as(f32, @floatFromInt(@reduce(.Add, total_vec))) *
                    l1_dequant + l1b[o]);
            }
        },
    }

    const L3Vec = @Vector(l3_size, f32);

    var l2_acc: L3Vec = w.l2_biases[bucket];
    const l2w = &l2_weights_t[bucket];
    for (0..l2_size) |j| {
        const col: L3Vec = l2w[j];
        l2_acc += col * @as(L3Vec, @splat(l1_out[j]));
    }

    const l2_clamped = @min(@max(l2_acc, @as(L3Vec, @splat(0.0))), @as(L3Vec, @splat(1.0)));
    const l2_out = l2_clamped * l2_clamped; // screlu

    const l3w: L3Vec = w.l3_weights[bucket];
    const out = w.l3_biases[bucket] + @reduce(.Add, l3w * l2_out);

    const scaled = @round(out * EVAL_SCALE);
    return @intFromFloat(std.math.clamp(scaled, -32000.0, 32000.0));
}

// Useful for debugging / profiling
pub const collect_sparsity = false;

var sp_calls: std.atomic.Value(u64) = .init(0);
var sp_nonzero: std.atomic.Value(u64) = .init(0);
var sp_blocks4: std.atomic.Value(u64) = .init(0);

const l1_quads = l1_size / 4;

fn countSparsity(ft_out: *align(cache_line) const [l1_size]i8) struct { nonzero: u32, blocks4: u32 } {
    const Mask = std.meta.Int(.unsigned, vec_i16_len);
    const zero: I8Vec = @splat(0);
    const vecs: *const [num_l1_vecs]I8Vec = @ptrCast(ft_out);

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

fn recordSparsity(ft_out: *align(cache_line) const [l1_size]i8) void {
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
        \\  built with          : {s}, has_byte_dot={}
        \\
    , .{
        calls,
        nz,                                    total,
        100.0 * (1.0 - nz / total),
        b4,                                    @as(f64, l1_quads),
        100.0 * (1.0 - b4 / @as(f64, l1_quads)),
        dense_macs,
        elem_macs, dense_macs / elem_macs,
        blk4_macs, dense_macs / blk4_macs,
        @tagName(l1_path), has_byte_dot,
    });
}

pub fn sparsityProbe(stack: *NNUEStack, side_to_move: brd.Color, board: *const brd.Board) struct { nonzero: u32, blocks4: u32 } {
    stack.ensureComputed(stack.current, board);
    const state = stack.top();
    const stm: usize = @intFromEnum(side_to_move);

    var ft_out: [l1_size]i8 align(cache_line) = undefined;
    activateFtPairwise(state.acc_ptr[stm], &ft_out, 0);
    activateFtPairwise(state.acc_ptr[1 - stm], &ft_out, num_pairwise_vecs);

    return countSparsity(&ft_out);
}

