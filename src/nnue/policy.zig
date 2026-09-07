const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const see = @import("see");

pub const plane_size: usize = 768;
pub const input_size: usize = plane_size * 4;
pub const hl: usize = 512;
pub const hp: usize = hl / 2;
pub const promos: usize = 4 * 22;
pub const see_threshold: i32 = -108;
pub const max_active: usize = 32;

// match header from my trainer
pub const bin_version: u32 = 3;
pub const expected_act_id: u32 = 1;
pub const expected_layers: u32 = 3;

pub const qa_scale: u32 = 255;
pub const qb_scale: u32 = 64;
pub const qa: f32 = @floatFromInt(qa_scale);
pub const qb: f32 = @floatFromInt(qb_scale);

pub const root_lmr_top: i32 = 3;
pub const root_lmr_min_depth: usize = 3;

pub const tm_min_depth: usize = 6;
pub const tm_agree_conf: f32 = 0.35;
pub const tm_uncertain: f32 = 0.18;
pub const tm_entropy_gate: f32 = 0.80;
pub const tm_agree_scale: f32 = 0.88;
pub const tm_disagree_scale: f32 = 1.35;
pub const tm_uncertain_scale: f32 = 1.25;

const file_a: u64 = 0x0101010101010101;
const file_h: u64 = file_a << 7;

const diags = [15]u64{
    0x0100000000000000, 0x0201000000000000, 0x0402010000000000,
    0x0804020100000000, 0x1008040201000000, 0x2010080402010000,
    0x4020100804020100, 0x8040201008040201, 0x0080402010080402,
    0x0000804020100804, 0x0000008040201008, 0x0000000080402010,
    0x0000000000804020, 0x0000000000008040, 0x0000000000000080,
};

fn destPawn(sq: usize) u64 {
    const bit = @as(u64, 1) << @intCast(sq);
    return ((bit & ~file_a) << 7) | (bit << 8) | ((bit & ~file_h) << 9);
}

fn destKnight(sq: usize) u64 {
    const n = @as(u64, 1) << @intCast(sq);
    const h1 = ((n >> 1) & 0x7f7f7f7f7f7f7f7f) | ((n << 1) & 0xfefefefefefefefe);
    const h2 = ((n >> 2) & 0x3f3f3f3f3f3f3f3f) | ((n << 2) & 0xfcfcfcfcfcfcfcfc);
    return (h1 << 16) | (h1 >> 16) | (h2 << 8) | (h2 >> 8);
}

fn destBishop(sq: usize) u64 {
    const rank = sq / 8;
    const file = sq % 8;
    return @byteSwap(diags[file + rank]) ^ diags[7 + file - rank];
}

fn destRook(sq: usize) u64 {
    const rank = sq / 8;
    const file = sq % 8;
    return (@as(u64, 0xFF) << @intCast(rank * 8)) ^ (file_a << @intCast(file));
}

fn destQueen(sq: usize) u64 {
    return destBishop(sq) | destRook(sq);
}

fn destKing(sq: usize) u64 {
    var k = @as(u64, 1) << @intCast(sq);
    k |= (k << 8) | (k >> 8);
    k |= ((k & ~file_a) >> 1) | ((k & ~file_h) << 1);
    return k ^ (@as(u64, 1) << @intCast(sq));
}


pub const PolicyNet = struct {
    loaded: bool = false,

    from_to: usize = 0, // 3920
    num_moves: usize = 0, // 7840

    l0w: []f32 = &.{},
    l0b: [hl]f32 = undefined,
    l1w: []f32 = &.{},
    l1b: [hl]f32 = undefined,
    l2w: []f32 = &.{},
    l2b: []f32 = &.{},

    destinations: [64][6]u64 = undefined,
    offsets: [6][65]u32 = undefined,

    pub fn initTables(self: *PolicyNet) void {
        for (0..64) |sq| {
            self.destinations[sq][0] = destPawn(sq);
            self.destinations[sq][1] = destKnight(sq);
            self.destinations[sq][2] = destBishop(sq);
            self.destinations[sq][3] = destRook(sq);
            self.destinations[sq][4] = destQueen(sq);
            self.destinations[sq][5] = destKing(sq);
        }

        var curr: u32 = 0;
        for (0..6) |pc| {
            for (0..64) |sq| {
                self.offsets[pc][sq] = curr;
                curr += @popCount(self.destinations[sq][pc]);
            }
            self.offsets[pc][64] = curr;
        }

        self.from_to = @as(usize, self.offsets[5][64]) + promos + 2 + 8;
        self.num_moves = 2 * self.from_to;
    }

    pub fn loadFromMemory(self: *PolicyNet, alloc: std.mem.Allocator, data: []const u8) !void {
        self.initTables();
        self.loaded = false;

        const header_size: usize = 40;
        if (data.len < header_size) {
            std.debug.print(
                "info string Policy: blob too small for UPO3 header ({d} bytes)\n",
                .{data.len},
            );
            return error.PolicyHeaderTooSmall;
        }
        if (!std.mem.eql(u8, data[0..4], "UPO3")) {
            std.debug.print("info string Policy: bad magic (expected UPO3)\n", .{});
            return error.PolicyBadMagic;
        }

        const readU32 = struct {
            fn f(src: []const u8, o: usize) u32 {
                return @as(u32, src[o]) |
                    (@as(u32, src[o + 1]) << 8) |
                    (@as(u32, src[o + 2]) << 16) |
                    (@as(u32, src[o + 3]) << 24);
            }
        }.f;

        const file_version = readU32(data, 4);
        const file_hl = readU32(data, 8);
        const file_act = readU32(data, 12);
        const file_layers = readU32(data, 16);
        const file_num_moves = readU32(data, 20);
        const file_qa = readU32(data, 24);
        const file_qb = readU32(data, 28);
        // data[32..40] reserved

        const header_ok = file_version == bin_version and
            file_hl == hl and
            file_act == expected_act_id and
            file_layers == expected_layers and
            @as(usize, file_num_moves) == self.num_moves and
            file_qa == qa_scale and
            file_qb == qb_scale;

        if (!header_ok) {
            std.debug.print(
                "info string Policy: header mismatch got(version={d} hl={d} act={d} layers={d} " ++
                    "num_moves={d} qa={d} qb={d}) want(version={d} hl={d} act={d} layers={d} " ++
                    "num_moves={d} qa={d} qb={d})\n",
                .{
                    file_version, file_hl, file_act, file_layers, file_num_moves, file_qa, file_qb,
                    bin_version,  hl,      expected_act_id, expected_layers, self.num_moves, qa_scale, qb_scale,
                },
            );
            return error.PolicyHeaderMismatch;
        }

        const expected = header_size +
            input_size * hl * 2 + // l0w  i16, [input_size, hl]
            hl * 2 + // l0b  i16
            hl * hp * 1 + // l1w  i8,  [hl, hp] (mid, output-major)
            hl * 2 + // l1b  i16
            hp * self.num_moves * 1 + // l2w  i8,  [num_moves, hp] (move-major)
            self.num_moves * 2; // l2b  i16

        if (data.len != expected) {
            std.debug.print(
                "info string Policy: size mismatch got {d} expected {d} (from_to={d} num_moves={d})\n",
                .{ data.len, expected, self.from_to, self.num_moves },
            );
            return error.PolicySizeMismatch;
        }

        var off: usize = header_size;

        const readQ16 = struct {
            fn f(dst: []f32, src: []const u8, o: *usize, scale: f32) void {
                for (dst, 0..) |*w, i| {
                    const lo: u16 = src[o.* + i * 2];
                    const hi: u16 = src[o.* + i * 2 + 1];
                    const bits: u16 = lo | (hi << 8);
                    const q: i16 = @bitCast(bits);
                    w.* = @as(f32, @floatFromInt(q)) / scale;
                }
                o.* += dst.len * 2;
            }
        }.f;

        const readQ8 = struct {
            fn f(dst: []f32, src: []const u8, o: *usize, scale: f32) void {
                for (dst, 0..) |*w, i| {
                    const q: i8 = @bitCast(src[o.* + i]);
                    w.* = @as(f32, @floatFromInt(q)) / scale;
                }
                o.* += dst.len;
            }
        }.f;

        self.l0w = try alloc.alloc(f32, input_size * hl);
        errdefer alloc.free(self.l0w);
        readQ16(self.l0w, data, &off, qa);
        readQ16(self.l0b[0..], data, &off, qa);

        self.l1w = try alloc.alloc(f32, hl * hp);
        errdefer alloc.free(self.l1w);
        readQ8(self.l1w, data, &off, qb);
        readQ16(self.l1b[0..], data, &off, qa);

        self.l2w = try alloc.alloc(f32, hp * self.num_moves);
        errdefer alloc.free(self.l2w);
        readQ8(self.l2w, data, &off, qb);

        self.l2b = try alloc.alloc(f32, self.num_moves);
        readQ16(self.l2b, data, &off, qa);

        std.debug.assert(off == data.len);
        self.loaded = true;
    }

    pub fn loadEmbedded(self: *PolicyNet, alloc: std.mem.Allocator) !void {
        const blob = @embedFile("nets/policy_pw512.bin");
        try self.loadFromMemory(alloc, blob);
    }

    pub fn attacksBySide(board: *brd.Board, move_gen: *mvs.MoveGen, side: brd.Color) u64 {
        const c = @intFromEnum(side);
        const occ = board.occupancy();
        var atk: u64 = 0;

        var bb = board.piece_bb[c][@intFromEnum(brd.Pieces.Pawn)];
        while (bb != 0) : (bb &= bb - 1) {
            const sq: usize = @ctz(bb);
            atk |= move_gen.pawns[@as(usize, c) * 64 + sq];
        }

        bb = board.piece_bb[c][@intFromEnum(brd.Pieces.Knight)];
        while (bb != 0) : (bb &= bb - 1) {
            atk |= move_gen.knights[@ctz(bb)];
        }

        bb = board.piece_bb[c][@intFromEnum(brd.Pieces.Bishop)] |
            board.piece_bb[c][@intFromEnum(brd.Pieces.Queen)];
        while (bb != 0) : (bb &= bb - 1) {
            atk |= move_gen.getBishopAttacks(@ctz(bb), occ);
        }

        bb = board.piece_bb[c][@intFromEnum(brd.Pieces.Rook)] |
            board.piece_bb[c][@intFromEnum(brd.Pieces.Queen)];
        while (bb != 0) : (bb &= bb - 1) {
            atk |= move_gen.getRookAttacks(@ctz(bb), occ);
        }

        const kbb = board.piece_bb[c][@intFromEnum(brd.Pieces.King)];
        if (kbb != 0) atk |= move_gen.kings[brd.getLSB(kbb)];

        return atk;
    }

    fn stmKingSq(board: *brd.Board) usize {
        const c = @intFromEnum(board.toMove());
        return brd.getLSB(board.piece_bb[c][@intFromEnum(brd.Pieces.King)]);
    }

    fn flipMask(board: *brd.Board) usize {
        const ksq = stmKingSq(board);
        const vert: usize = if (board.toMove() == .Black) 56 else 0;
        const hori: usize = if ((ksq % 8) > 3) 7 else 0;
        return vert ^ hori;
    }

    pub fn collectFeatures(
        board: *brd.Board,
        move_gen: *mvs.MoveGen,
        feats: *[max_active]u16,
    ) usize {
        var n: usize = 0;

        const flip = flipMask(board);
        const stm = board.toMove();
        const nstm = brd.flipColor(stm);

        const threats = attacksBySide(board, move_gen, nstm);
        const defences = attacksBySide(board, move_gen, stm);

        for (0..6) |p| {
            const pc = 64 * p;

            inline for (.{ stm, nstm }, .{ @as(usize, 0), @as(usize, 384) }) |side, base| {
                var bb = board.piece_bb[@intFromEnum(side)][p];
                while (bb != 0) : (bb &= bb - 1) {
                    const sq: usize = @ctz(bb);
                    var feat = base + pc + (sq ^ flip);

                    const bit = @as(u64, 1) << @intCast(sq);
                    if (threats & bit != 0) feat += plane_size;
                    if (defences & bit != 0) feat += plane_size * 2;

                    if (n < max_active) {
                        feats[n] = @intCast(feat);
                        n += 1;
                    }
                }
            }
        }
        return n;
    }

    pub fn mapMoveToIndex(
        self: *const PolicyNet,
        board: *brd.Board,
        move_gen: *mvs.MoveGen,
        move: mvs.EncodedMove,
    ) i32 {
        const ksq = stmKingSq(board);
        const hm: usize = if ((ksq % 8) > 3) 7 else 0;
        const flip: usize = hm ^ (if (board.toMove() == .Black) @as(usize, 56) else 0);

        const src = @as(usize, move.start_square) ^ flip;
        const dst = @as(usize, move.end_square) ^ flip;

        var idx: usize = 0;

        if (move.promoted_piece != 0) {
            const promo_pc: usize = @as(usize, move.promoted_piece) - 1;
            const promo_id = 2 * (src % 8) + (dst % 8);
            idx = @as(usize, self.offsets[5][64]) + (promos / 4) * promo_pc + promo_id;
        } else if (move.castling == 1) {
            const is_ks: usize = if ((move.end_square % 8) == 6) 1 else 0;
            const is_hm: usize = if (hm == 0) 1 else 0;
            idx = @as(usize, self.offsets[5][64]) + promos + (is_ks ^ is_hm);
        } else if (move.double_pawn_push == 1) {
            idx = @as(usize, self.offsets[5][64]) + promos + 2 + (src % 8);
        } else {
            const pc = @as(usize, move.piece);
            if (pc > 5) return -1;
            const dest_bb = self.destinations[src][pc];
            const below = dest_bb & ((@as(u64, 1) << @intCast(dst)) - 1);
            idx = @as(usize, self.offsets[pc][src]) + @popCount(below);
        }

        const good_see = see.seeAtLeast(board, move_gen, move, see_threshold);

        const index = self.from_to * @as(usize, @intFromBool(good_see)) + idx;
        if (index >= self.num_moves) return -1;
        return @intCast(index);
    }

    fn crelu01(x: f32) f32 {
        return std.math.clamp(x, 0.0, 1.0);
    }

    pub fn computeHidden(self: *const PolicyNet, feats: []const u16, h: *[hp]f32) void {
        var pre0: [hl]f32 = self.l0b;
        for (feats) |f| {
            const row = self.l0w[@as(usize, f) * hl ..][0..hl];
            for (0..hl) |j| pre0[j] += row[j];
        }

        var h0: [hp]f32 = undefined;
        for (0..hp) |i| {
            h0[i] = crelu01(pre0[i]) * crelu01(pre0[i + hp]);
        }

        var pre1: [hl]f32 = self.l1b;
        for (0..hl) |j| {
            const row = self.l1w[j * hp ..][0..hp];
            var acc: f32 = 0.0;
            for (0..hp) |k| acc += h0[k] * row[k];
            pre1[j] += acc;
        }

        for (0..hp) |i| {
            h[i] = crelu01(pre1[i]) * crelu01(pre1[i + hp]);
        }
    }

    pub fn logitForIndex(self: *const PolicyNet, h: *const [hp]f32, mi: usize) f32 {
        const row = self.l2w[mi * hp ..][0..hp];
        var acc: f32 = self.l2b[mi];
        for (0..hp) |k| acc += h[k] * row[k];
        return acc;
    }
};

pub const max_root_moves = 218;

pub const RootPolicy = struct {
    ok: bool = false,

    n: usize = 0,
    nq: usize = 0,

    move_u32: [max_root_moves]u32 = undefined,
    quiet_rank: [max_root_moves]i32 = undefined,
    prob_any: [max_root_moves]f32 = undefined,

    top_any: u32 = 0,
    top_prob_any: f32 = 0.0,
    norm_entropy_any: f32 = 1.0,

    pub fn reset(self: *RootPolicy) void {
        self.* = .{};
    }

    pub fn rankOf(self: *const RootPolicy, m: u32) i32 {
        for (0..self.n) |i| {
            if (self.move_u32[i] == m) return self.quiet_rank[i];
        }
        return -1;
    }

    fn isPolicyQuiet(m: mvs.EncodedMove) bool {
        return m.capture == 0 and m.en_passant == 0 and
            m.promoted_piece == 0 and m.castling == 0;
    }

    pub fn compute(
        self: *RootPolicy,
        net: *const PolicyNet,
        board: *brd.Board,
        move_gen: *mvs.MoveGen,
    ) void {
        self.reset();
        if (!net.loaded) return;

        const list = move_gen.generateMoves(board, mvs.allMoves);
        if (list.len == 0 or list.len > max_root_moves) return;
        self.n = list.len;

        var feats: [max_active]u16 = undefined;
        const nfeats = PolicyNet.collectFeatures(board, move_gen, &feats);

        var h: [hp]f32 = undefined;
        net.computeHidden(feats[0..nfeats], &h);

        var logits: [max_root_moves]f32 = undefined;
        var max_all: f32 = -1e30;

        for (0..self.n) |i| {
            const m = list.items[i];
            self.move_u32[i] = m.toU32();
            self.quiet_rank[i] = -1;

            const mi = net.mapMoveToIndex(board, move_gen, m);
            logits[i] = if (mi >= 0) net.logitForIndex(&h, @intCast(mi)) else -1e9;
            max_all = @max(max_all, logits[i]);
        }

        var sum: f32 = 0.0;
        for (0..self.n) |i| {
            self.prob_any[i] = @exp(logits[i] - max_all);
            sum += self.prob_any[i];
        }
        if (sum <= 0.0) sum = 1.0;

        var best_i: usize = 0;
        var ent: f32 = 0.0;
        for (0..self.n) |i| {
            self.prob_any[i] /= sum;
            if (self.prob_any[i] > self.prob_any[best_i]) best_i = i;
            if (self.prob_any[i] > 1e-12) {
                ent -= self.prob_any[i] * @log(self.prob_any[i]);
            }
        }

        self.top_any = self.move_u32[best_i];
        self.top_prob_any = self.prob_any[best_i];
        self.norm_entropy_any = if (self.n > 1)
            ent / @log(@as(f32, @floatFromInt(self.n)))
        else
            0.0;

        var qidx: [max_root_moves]usize = undefined;
        var nq: usize = 0;
        for (0..self.n) |i| {
            if (isPolicyQuiet(list.items[i])) {
                qidx[nq] = i;
                nq += 1;
            }
        }
        self.nq = nq;

        var r: usize = 0;
        while (r < nq) : (r += 1) {
            var best_j = r;
            var j = r + 1;
            while (j < nq) : (j += 1) {
                if (logits[qidx[j]] > logits[qidx[best_j]]) best_j = j;
            }
            std.mem.swap(usize, &qidx[r], &qidx[best_j]);
            self.quiet_rank[qidx[r]] = @intCast(r);
        }

        self.ok = true;
    }

    pub fn tmScale(self: *const RootPolicy, bm: u32, depth: usize) f32 {
        if (!self.ok or bm == 0 or depth < tm_min_depth) return 1.0;

        const agree = bm == self.top_any;
        if (agree and self.top_prob_any >= tm_agree_conf and
            self.norm_entropy_any <= tm_entropy_gate)
        {
            return tm_agree_scale;
        }
        if (!agree) return tm_disagree_scale;
        if (self.top_prob_any < tm_uncertain) return tm_uncertain_scale;
        return 1.0;
    }

    pub fn lmrDelta(self: *const RootPolicy, m: mvs.EncodedMove, depth: usize) i32 {
        if (!self.ok or depth < root_lmr_min_depth) return 0;
        if (!isPolicyQuiet(m)) return 0;

        const pr = self.rankOf(m.toU32());
        if (pr < 0) return 0;

        if (pr < root_lmr_top) return -1;
        if (self.nq >= 4 and pr >= @as(i32, @intCast(self.nq / 2))) return 1;
        return 0;
    }
};
