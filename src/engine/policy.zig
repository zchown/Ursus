const std = @import("std");
const brd = @import("board");
const mvs = @import("moves");
const see = @import("see");

pub const plane_size: usize = 768;
pub const input_size: usize = plane_size * 4;
pub const promos: usize = 4 * 22;
pub const see_threshold: i32 = -108;
pub const max_active: usize = 32;

pub const Act = enum(u32) { screlu = 0, pairwise = 1 };

pub const hl: usize = 1024;
pub const act: Act = .pairwise;
pub const layers: usize = 3; // 2 or 3
pub const hw: usize = if (act == .screlu) hl else hl / 2;

pub const qa: f32 = 255.0;
pub const qb: f32 = 64.0;

const cache_line = std.atomic.cache_line;
const vlen: comptime_int = std.simd.suggestVectorLength(f32) orelse 8;
const FVec = @Vector(vlen, f32);

comptime {
    std.debug.assert(layers == 2 or layers == 3);
    std.debug.assert(hl % vlen == 0 and hw % vlen == 0);
    if (act == .pairwise) std.debug.assert(hl % 2 == 0);
}

inline fn vload(ptr: [*]const f32) FVec {
    return @as(*const FVec, @ptrCast(@alignCast(ptr))).*;
}
inline fn vloadu(ptr: [*]const f32) FVec {
    var v: FVec = undefined;
    inline for (0..vlen) |i| v[i] = ptr[i];
    return v;
}

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
    l1b: []f32 = &.{},
    low: []f32 = &.{},
    lob: []f32 = &.{},

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

    fn rdU32(data: []const u8, off: usize) u32 {
        return std.mem.readInt(u32, data[off..][0..4], .little);
    }

    pub fn loadFromMemory(self: *PolicyNet, alloc: std.mem.Allocator, data: []const u8) !void {
        self.initTables();
        self.loaded = false;

        if (data.len < 40 or !std.mem.eql(u8, data[0..4], "UPO3")) {
            std.debug.print("info string Policy: bad magic (want UPO3)\n", .{});
            return error.PolicyBadMagic;
        }

        const h_version = rdU32(data, 4);
        const h_hl = rdU32(data, 8);
        const h_act = rdU32(data, 12);
        const h_layers = rdU32(data, 16);
        const h_nm = rdU32(data, 20);
        const h_qa = rdU32(data, 24);
        const h_qb = rdU32(data, 28);

        if (h_version != 3 or h_hl != hl or h_act != @intFromEnum(act) or
            h_layers != layers or h_nm != self.num_moves or
            h_qa != @as(u32, @intFromFloat(qa)) or h_qb != @as(u32, @intFromFloat(qb)))
        {
            std.debug.print(
                "info string Policy: header mismatch " ++
                    "(file v{d} hl={d} act={d} layers={d} nm={d} qa={d} qb={d}; " ++
                    "engine hl={d} act={d} layers={d} nm={d})\n",
                .{ h_version, h_hl, h_act, h_layers, h_nm, h_qa, h_qb, hl, @intFromEnum(act), layers, self.num_moves },
            );
            return error.PolicyHeaderMismatch;
        }

        var expected: usize = 40 + 2 * (input_size * hl) + 2 * hl +
            hw * self.num_moves + 2 * self.num_moves;
        if (layers == 3) expected += hw * hl + 2 * hl;
        if (data.len != expected) {
            std.debug.print(
                "info string Policy: size mismatch got {d} expected {d}\n",
                .{ data.len, expected },
            );
            return error.PolicySizeMismatch;
        }

        var off: usize = 40;

        const readI16 = struct {
            fn f(dst: []f32, src: []const u8, o: *usize) void {
                for (dst, 0..) |*w, i| {
                    const v = std.mem.readInt(i16, src[o.* + 2 * i ..][0..2], .little);
                    w.* = @as(f32, @floatFromInt(v)) / qa;
                }
                o.* += 2 * dst.len;
            }
        }.f;

        const readI8 = struct {
            fn f(dst: []f32, src: []const u8, o: *usize) void {
                for (dst, 0..) |*w, i| {
                    const v: i8 = @bitCast(src[o.* + i]);
                    w.* = @as(f32, @floatFromInt(v)) / qb;
                }
                o.* += dst.len;
            }
        }.f;

        self.l0w = try alloc.alloc(f32, input_size * hl);
        errdefer alloc.free(self.l0w);
        readI16(self.l0w, data, &off);

        var l0b_tmp: [hl]f32 = undefined;
        readI16(l0b_tmp[0..], data, &off);
        self.l0b = l0b_tmp;

        if (layers == 3) {
            self.l1w = try alloc.alloc(f32, hl * hw);
            errdefer alloc.free(self.l1w);
            readI8(self.l1w, data, &off);

            self.l1b = try alloc.alloc(f32, hl);
            errdefer alloc.free(self.l1b);
            readI16(self.l1b, data, &off);
        }

        self.low = try alloc.alloc(f32, self.num_moves * hw);
        errdefer alloc.free(self.low);
        readI8(self.low, data, &off);

        self.lob = try alloc.alloc(f32, self.num_moves);
        readI16(self.lob, data, &off);

        std.debug.assert(off == data.len);
        self.loaded = true;
    }

    pub fn loadEmbedded(self: *PolicyNet, alloc: std.mem.Allocator) !void {
        const blob = @embedFile("policy_big2.bin");
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

    inline fn applyAct(x: *const [hl]f32, out: *[hw]f32) void {
        const zero: FVec = @splat(0.0);
        const one: FVec = @splat(1.0);
        const xp: [*]const f32 = x;
        const op: [*]f32 = out;
        if (comptime act == .screlu) {
            var j: usize = 0;
            while (j < hl) : (j += vlen) {
                const c = @min(@max(vload(xp + j), zero), one);
                @as(*FVec, @ptrCast(@alignCast(op + j))).* = c * c;
            }
        } else {
            var j: usize = 0;
            while (j < hw) : (j += vlen) {
                const a = @min(@max(vload(xp + j), zero), one);
                const b = @min(@max(vload(xp + j + hw), zero), one);
                @as(*FVec, @ptrCast(@alignCast(op + j))).* = a * b;
            }
        }
    }

    pub fn computeHidden(
        self: *const PolicyNet,
        feats: []const u16,
        h: *align(cache_line) [hw]f32,
    ) void {
        @setFloatMode(.optimized);

        var x0: [hl]f32 align(cache_line) = self.l0b;
        const x0p: [*]f32 = &x0;

        for (feats) |f| {
            const row = self.l0w.ptr + @as(usize, f) * hl;
            var j: usize = 0;
            while (j < hl) : (j += vlen) {
                const a = vload(x0p + j);
                @as(*FVec, @ptrCast(@alignCast(x0p + j))).* = a + vloadu(row + j);
            }
        }

        if (comptime layers == 2) {
            applyAct(&x0, h);
            return;
        }

        var h1: [hw]f32 align(cache_line) = undefined;
        applyAct(&x0, &h1);
        const h1p: [*]const f32 = &h1;

        var x1: [hl]f32 align(cache_line) = undefined;
        for (0..hl) |o| {
            const row = self.l1w.ptr + o * hw;
            var accv: FVec = @splat(0.0);
            var k: usize = 0;
            while (k < hw) : (k += vlen) {
                accv = @mulAdd(FVec, vload(h1p + k), vloadu(row + k), accv);
            }
            x1[o] = self.l1b[o] + @reduce(.Add, accv);
        }

        applyAct(&x1, h);
    }

    pub fn logitForIndex(
        self: *const PolicyNet,
        h: *align(cache_line) const [hw]f32,
        mi: usize,
    ) f32 {
        @setFloatMode(.optimized);
        const row = self.low.ptr + mi * hw;
        const hp: [*]const f32 = h;
        var accv: FVec = @splat(0.0);
        var k: usize = 0;
        while (k < hw) : (k += vlen) {
            accv = @mulAdd(FVec, vload(hp + k), vloadu(row + k), accv);
        }
        return self.lob[mi] + @reduce(.Add, accv);
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

        var h: [hw]f32 align(std.atomic.cache_line) = undefined;
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


pub fn debugPrint(
    net: *const PolicyNet,
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    writer: anytype,
) !void {
    if (!net.loaded) {
        try writer.print("info string Policy not loaded\n", .{});
        return;
    }

    var rp: RootPolicy = .{};
    rp.compute(net, board, move_gen);

    if (!rp.ok) {
        try writer.print("info string policy compute failed\n", .{});
        return;
    }

    const list = move_gen.generateMoves(board, mvs.allMoves);

    try writer.print(
        "info string === POLICY DEBUG (UPO3 act={s} hl={d} hw={d} layers={d}) ===\n" ++
            "info string stm={s} from_to={d} num_moves={d}\n",
        .{
            @tagName(act),
            hl,
            hw,
            layers,
            if (board.toMove() == .White) "w" else "b",
            net.from_to,
            net.num_moves,
        },
    );

    var order: [max_root_moves]usize = undefined;
    for (0..rp.n) |i| order[i] = i;
    std.mem.sort(usize, order[0..rp.n], &rp, struct {
        fn lt(ctx: *const RootPolicy, a: usize, b: usize) bool {
            return ctx.prob_any[a] > ctx.prob_any[b];
        }
    }.lt);

    for (0..@min(rp.n, 16)) |r| {
        const i = order[r];
        const m = list.items[i];
        const mi = net.mapMoveToIndex(board, move_gen, m);
        const gsee = see.seeAtLeast(board, move_gen, m, see_threshold);
        const uci = m.uciToString(std.heap.smp_allocator) catch "????";
        defer std.heap.smp_allocator.free(uci);
        try writer.print(
            "info string #{d:0>2}  {s:<6} idx={d: >5} see={s} prob={d:.2}% qrank={d}\n",
            .{ r + 1, uci, mi, if (gsee) "Y" else "N", rp.prob_any[i] * 100.0, rp.quiet_rank[i] },
        );
    }

    try writer.print(
        "info string top1={d:.2}% norm_ent={d:.3} legal={d} nquiets={d}\n" ++
            "info string === END POLICY DEBUG ===\n",
        .{ rp.top_prob_any * 100.0, rp.norm_entropy_any, rp.n, rp.nq },
    );
}
