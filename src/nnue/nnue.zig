const std = @import("std");
const brd = @import("board");
const moves = @import("moves");

pub const num_features = 2 * brd.num_pieces * brd.num_squares; // 2 * 6 * 64 = 768
pub const hidden_size = 1536;

const QA: i16 = 255;
const QB: i16 = 64;
const NUM_OUTPUT_BUCKETS: usize = 8;
const EVAL_SCALE: i64 = 128;

const vec_i16_len = 16;
const num_acc_vecs = hidden_size / vec_i16_len;
const I16Vec = @Vector(vec_i16_len, i16);

const nnue_piece_to_index = [2][6]u8{
    [_]u8{ 0, 1, 2, 3, 4, 5 }, // Pawn, Knight, Bishop, Rook, Queen, King
    [_]u8{ 6, 7, 8, 9, 10, 11 }, // Pawn, Knight, Bishop, Rook, Queen, King
};

pub const NetworkWeights = struct {
    ft_weights: [num_features][hidden_size]i16 align(@alignOf(I16Vec)),
    ft_biases: [hidden_size]i16 align(@alignOf(I16Vec)),
    out_weights: [NUM_OUTPUT_BUCKETS][2 * hidden_size]i16 align(@alignOf(I16Vec)),
    out_biases: [NUM_OUTPUT_BUCKETS]i16,
};

const embedded_nnue_bytes align(@alignOf(NetworkWeights)) = @embedFile("nnuev2.bin").*;
var net_weights: ?*const NetworkWeights = null;

pub fn initWeights() void {
    net_weights = @ptrCast(&embedded_nnue_bytes);
}

inline fn mirRank(sq: u8) u8 {
    return sq ^ 56;
}

pub fn featureIndex(
    view: brd.Color,
    piece_color: brd.Color,
    piece_type: brd.Pieces,
    square: u8,
) usize {
    const oriented_sq: usize = if (view == .White) square else mirRank(square);
    const is_own: usize = if (view == piece_color) 0 else 1;

    const piece_idx = @intFromEnum(piece_type);

    const piece_offset = nnue_piece_to_index[is_own][piece_idx];
    return oriented_sq + (@as(usize, piece_offset) * 64);
}

fn materialBucket(board: *const brd.Board) usize {
    var occupied: u64 = 0;
    inline for (0..brd.num_colors) |ci| {
        for (std.meta.tags(brd.Pieces)) |piece| {
            if (piece == .None) continue;
            occupied |= board.piece_bb[ci][@intFromEnum(piece)];
        }
    }
    const piece_count: usize = @popCount(occupied);
    return @min((piece_count -| 2) / 4, NUM_OUTPUT_BUCKETS - 1);
}

pub const Accumulator = struct {
    vals: [hidden_size]i16 align(@alignOf(I16Vec)),

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

    inline fn weightVecs(feature_idx: usize) *const [num_acc_vecs]I16Vec {
        return @ptrCast(&net_weights.?.ft_weights[feature_idx]);
    }

    pub fn activateFeature(self: *Accumulator, feature_idx: usize) void {
        if (net_weights == null) return;
        const dst = self.vecs();
        const src = weightVecs(feature_idx);
        inline for (0..num_acc_vecs) |i| dst[i] +%= src[i];
    }

    pub fn deactivateFeature(self: *Accumulator, feature_idx: usize) void {
        if (net_weights == null) return;
        const dst = self.vecs();
        const src = weightVecs(feature_idx);
        inline for (0..num_acc_vecs) |i| dst[i] -%= src[i];
    }

    pub fn moveFeature(self: *Accumulator, old_idx: usize, new_idx: usize) void {
        if (net_weights == null) return;
        const dst = self.vecs();
        const old = weightVecs(old_idx);
        const nw = weightVecs(new_idx);
        inline for (0..num_acc_vecs) |i|
            dst[i] = dst[i] -% old[i] +% nw[i];
    }
};

pub const NNUEState = struct {
    accumulators: [brd.num_colors]Accumulator,

    pub fn init() NNUEState {
        return .{
            .accumulators = [_]Accumulator{Accumulator.init()} ** brd.num_colors,
        };
    }

    pub fn copyFrom(self: *NNUEState, other: *const NNUEState) void {
        self.accumulators = other.accumulators;
    }
};

pub const NNUEStack = struct {
    states: [brd.max_game_moves + 1]NNUEState,
    current: usize,

    pub fn init() NNUEStack {
        return .{ .states = undefined, .current = 0 };
    }

    pub inline fn top(self: *NNUEStack) *NNUEState {
        return &self.states[self.current];
    }

    pub inline fn push(self: *NNUEStack) void {
        self.states[self.current + 1].copyFrom(&self.states[self.current]);
        self.current += 1;
    }

    pub inline fn pop(self: *NNUEStack) void {
        if (self.current > 0) self.current -= 1;
    }

    pub fn pushAndUpdate(
        self: *NNUEStack,
        board: *const brd.Board,
        move_data: moves.EncodedMove,
    ) void {
        self.push();
        const state = self.top();

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

            inline for (0..brd.num_colors) |vi| {
                const view: brd.Color = @enumFromInt(vi);
                const acc = &state.accumulators[vi];
                acc.moveFeature(
                    featureIndex(view, moving_color, .King, from_sq),
                    featureIndex(view, moving_color, .King, to_sq),
                );
                acc.moveFeature(
                    featureIndex(view, moving_color, .Rook, rook_from),
                    featureIndex(view, moving_color, .Rook, rook_to),
                );
            }
        } else if (move_data.en_passant == 1) {
            const ep_pawn_sq: u8 =
                if (moving_color == .White) to_sq - 8 else to_sq + 8;

            inline for (0..brd.num_colors) |vi| {
                const view: brd.Color = @enumFromInt(vi);
                const acc = &state.accumulators[vi];
                acc.moveFeature(
                    featureIndex(view, moving_color, .Pawn, from_sq),
                    featureIndex(view, moving_color, .Pawn, to_sq),
                );
                acc.deactivateFeature(featureIndex(view, opp_color, .Pawn, ep_pawn_sq));
            }
        } else if (move_data.promoted_piece != 0) {
            const promoted_type: brd.Pieces = @enumFromInt(move_data.promoted_piece);

            inline for (0..brd.num_colors) |vi| {
                const view: brd.Color = @enumFromInt(vi);
                const acc = &state.accumulators[vi];
                acc.deactivateFeature(featureIndex(view, moving_color, .Pawn, from_sq));
                if (move_data.capture == 1) {
                    const captured_type: brd.Pieces = @enumFromInt(move_data.captured_piece);
                    acc.deactivateFeature(featureIndex(view, opp_color, captured_type, to_sq));
                }
                acc.activateFeature(featureIndex(view, moving_color, promoted_type, to_sq));
            }
        } else {
            inline for (0..brd.num_colors) |vi| {
                const view: brd.Color = @enumFromInt(vi);
                const acc = &state.accumulators[vi];
                if (move_data.capture == 1) {
                    const captured_type: brd.Pieces = @enumFromInt(move_data.captured_piece);
                    acc.deactivateFeature(featureIndex(view, opp_color, captured_type, to_sq));
                }
                acc.moveFeature(
                    featureIndex(view, moving_color, piece_type, from_sq),
                    featureIndex(view, moving_color, piece_type, to_sq),
                );
            }
        }
    }
};

pub fn refreshAccumulator(board: *const brd.Board, state: *NNUEState) void {
    state.accumulators[0].initFromBias();
    state.accumulators[1].initFromBias();

    for (std.meta.tags(brd.Color)) |piece_color| {
        const ci = @intFromEnum(piece_color);
        for (std.meta.tags(brd.Pieces)) |piece| {
            if (piece == .None) continue;
            const pi = @intFromEnum(piece);
            var bb = board.piece_bb[ci][pi];
            while (bb != 0) {
                const sq: u8 = @intCast(@ctz(bb));
                state.accumulators[@intFromEnum(brd.Color.White)].activateFeature(featureIndex(.White, piece_color, piece, sq));
                state.accumulators[@intFromEnum(brd.Color.Black)].activateFeature(featureIndex(.Black, piece_color, piece, sq));
                bb &= bb - 1;
            }
        }
    }
}

pub fn evaluate(stack: *NNUEStack, side_to_move: brd.Color, board: *const brd.Board) i32 {
    const w = net_weights orelse return 0;
    const state = stack.top();

    const bucket = materialBucket(board);
    const stm = @intFromEnum(side_to_move);
    const nstm = 1 - stm;

    const I32Vec = @Vector(vec_i16_len, i32);
    const zero_vec = @as(I16Vec, @splat(0));
    const qa_vec = @as(I16Vec, @splat(QA));

    const stm_acc = state.accumulators[stm].vecs();
    const nstm_acc = state.accumulators[nstm].vecs();

    const bucket_weights = &w.out_weights[bucket];
    const stm_weights: *const [num_acc_vecs]I16Vec = @ptrCast(@alignCast(bucket_weights[0..hidden_size]));
    const nstm_weights: *const [num_acc_vecs]I16Vec = @ptrCast(@alignCast(bucket_weights[hidden_size .. 2 * hidden_size]));

    var sum_stm = @as(I32Vec, @splat(0));
    var sum_nstm = @as(I32Vec, @splat(0));

    for (0..num_acc_vecs) |i| {
        const stm_c: I32Vec = @min(@max(stm_acc[i], zero_vec), qa_vec);
        const sw: I32Vec = stm_weights[i];
        sum_stm +%= stm_c * stm_c * sw;

        const nstm_c: I32Vec = @min(@max(nstm_acc[i], zero_vec), qa_vec);
        const nw: I32Vec = nstm_weights[i];
        sum_nstm +%= nstm_c * nstm_c * nw;
    }

    const total_stm = @reduce(.Add, sum_stm);
    const total_nstm = @reduce(.Add, sum_nstm);

    const total = @as(i64, total_stm) + @as(i64, total_nstm);

    const qa: i64 = @as(i64, QA);
    const qa_qb: i64 = @as(i64, QA) * @as(i64, QB);

    var output: i64 = @divTrunc(total, qa);
    output += @as(i64, w.out_biases[bucket]);
    output *= EVAL_SCALE;
    output = @divTrunc(output, qa_qb);

    return @intCast(output);
}
