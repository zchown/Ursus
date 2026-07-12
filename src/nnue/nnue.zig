const std = @import("std");
const builtin = @import("builtin");
const brd = @import("board");
const moves = @import("moves");

pub const features_per_bucket = 2 * brd.num_pieces * brd.num_squares;

pub const NUM_KING_BUCKETS: usize = 10;

const KING_BUCKETS_BASE: [32]u8 = [_]u8{
    0, 1, 2, 3,
    4, 4, 5, 5,
    6, 6, 6, 6,
    7, 7, 7, 7,
    8, 8, 8, 8,
    8, 8, 8, 8,
    9, 9, 9, 9,
    9, 9, 9, 9,
};

pub const num_features = NUM_KING_BUCKETS * features_per_bucket;
pub const hidden_size = 1536;

const QA: i16 = 255;
const QB: i16 = 64;
const NUM_OUTPUT_BUCKETS: usize = 8;
const EVAL_SCALE: i64 = 128;
const cache_line = std.atomic.cache_line;

const CpuTarget = enum { avx2, sse2, aarch64, fallback };

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
const vec_i32_len: comptime_int = vec_i16_len / 2; // maddwd halves lane count
const num_acc_vecs: usize = hidden_size / vec_i16_len;

const I16Vec = @Vector(vec_i16_len, i16);
const I32Vec = @Vector(vec_i32_len, i32); // exactly one native register wide

inline fn maddwd(a: I16Vec, b: I16Vec) I32Vec {
    return switch (TARGET) {
        // AVX2: 3-operand non-destructive encoding.
        // AT&T syntax: vpmaddwd src2, src1, dst
        .avx2 => asm ("vpmaddwd %[b], %[a], %[ret]"
        : [ret] "=x" (-> I32Vec),
        : [a] "x" (a),
    [b] "x" (b),
    ),

        // SSE2: 2-operand destructive encoding.
        // "0" constraint ties the first input to the output register.
        .sse2 => asm ("pmaddwd %[b], %[a]"
        : [ret] "=x" (-> I32Vec),
        : [a] "0" (a),
    [b] "x" (b),
    ),

        // aarch64 should never reach here – handled in scReluAccumulate.
        .aarch64 => unreachable,

        // Portable fallback: deinterlace even/odd lanes, widen, multiply, add.
        .fallback => blk: {
            const a_parts = std.simd.deinterlace(2, a);
            const b_parts = std.simd.deinterlace(2, b);
            const lo: I32Vec = @as(I32Vec, a_parts[0]) * @as(I32Vec, b_parts[0]);
            const hi: I32Vec = @as(I32Vec, a_parts[1]) * @as(I32Vec, b_parts[1]);
            break :blk lo + hi;
        },
    };
}

// sum += v² * w   for all i   (Lizard reordering: (v*w)*v)
inline fn scReluAccumulate(sum: I32Vec, vw: I16Vec, v: I16Vec) I32Vec {
    return switch (TARGET) {
        // aarch64: smlal + smlal2 — multiply-accumulate long, lower and upper halves.
        .aarch64 => blk: {
            const after_lo: I32Vec = asm (
            \\smlal %[d].4s, %[n].4h, %[m].4h
            : [d] "=w" (-> I32Vec),
            : [n] "w" (vw),
        [m] "w" (v),
        [_] "0" (sum),
        );
            break :blk asm (
            \\smlal2 %[d].4s, %[n].8h, %[m].8h
            : [d] "=w" (-> I32Vec),
            : [n] "w" (vw),
        [m] "w" (v),
        [_] "0" (after_lo),
        );
        },
        // All other targets: delegate to maddwd and add to sum.
        else => sum +% maddwd(vw, v),
    };
}


inline fn mulHigh(a: I16Vec, b: I16Vec) I16Vec {
    return a *% b;
}

const nnue_piece_to_index = [2][6]u8{
[_]u8{ 0, 1, 2, 3, 4, 5 }, // Pawn, Knight, Bishop, Rook, Queen, King
[_]u8{ 6, 7, 8, 9, 10, 11 }, // Pawn, Knight, Bishop, Rook, Queen, King
};

pub const NetworkWeights = struct {
    ft_weights: [num_features][hidden_size]i16 align(cache_line),
    ft_biases: [hidden_size]i16 align(cache_line),

    out_weights: [NUM_OUTPUT_BUCKETS][2 * hidden_size]i16 align(cache_line),
    out_biases: [NUM_OUTPUT_BUCKETS]i16,
};

const embedded_nnue_bytes align(@alignOf(NetworkWeights)) = @embedFile("quantised10bucket.bin").*;
var net_weights: ?*const NetworkWeights = null;

pub fn initWeights() void {
    net_weights = @ptrCast(&embedded_nnue_bytes);
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

pub fn evaluate(stack: *NNUEStack, side_to_move: brd.Color, board: *const brd.Board) i32 {
    const w = net_weights orelse return 0;
    stack.ensureComputed(stack.current, board);

    const state = stack.top();
    const bucket = materialBucket(board);
    const stm: usize = @intFromEnum(side_to_move);
    const nstm: usize = 1 - stm;

    const zero_vec: I16Vec = @splat(0);
    const qa_vec: I16Vec = @splat(QA);

    const stm_acc = state.acc_ptr[stm].constVecs();
    const nstm_acc = state.acc_ptr[nstm].constVecs();

    const bucket_weights = &w.out_weights[bucket];
    const stm_weights: *const [num_acc_vecs]I16Vec =
    @ptrCast(@alignCast(bucket_weights[0..hidden_size]));
    const nstm_weights: *const [num_acc_vecs]I16Vec =
    @ptrCast(@alignCast(bucket_weights[hidden_size .. 2 * hidden_size]));

    const ACC_COUNT = 4;
    comptime std.debug.assert(num_acc_vecs % ACC_COUNT == 0);

    var sums_stm: [ACC_COUNT]I32Vec = @splat(@as(I32Vec, @splat(0)));
    var sums_ntm: [ACC_COUNT]I32Vec = @splat(@as(I32Vec, @splat(0)));

    var i: usize = 0;
    while (i < num_acc_vecs) {
        inline for (0..ACC_COUNT) |a| {
            const vi = i + a;

            const stm_v  = @min(@max(stm_acc[vi],  zero_vec), qa_vec);
            const nstm_v = @min(@max(nstm_acc[vi], zero_vec), qa_vec);

            const stm_vw  = mulHigh(stm_v,  stm_weights[vi]);
            const nstm_vw = mulHigh(nstm_v, nstm_weights[vi]);

            sums_stm[a] = scReluAccumulate(sums_stm[a], stm_vw,  stm_v);
            sums_ntm[a] = scReluAccumulate(sums_ntm[a], nstm_vw, nstm_v);
        }
        i += ACC_COUNT;
    }

    var total_vec = sums_stm[0];
    inline for (1..ACC_COUNT) |a| total_vec += sums_stm[a];
    inline for (0..ACC_COUNT) |a| total_vec += sums_ntm[a];
    const total_i32 = @reduce(.Add, total_vec);

    const total: i64 = total_i32;
    const qa_qb: i64 = @as(i64, QA) * @as(i64, QB);

    var output: i64 = @divTrunc(total, @as(i64, QA));
    output += @as(i64, w.out_biases[bucket]);
    output *= EVAL_SCALE;
    output = @divTrunc(output, qa_qb);

    return @intCast(output);
}
