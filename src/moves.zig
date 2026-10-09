const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;
const rad = root.rad;
const magic = root.magic;

const Bitboard = brd.Bitboard;
const Square = brd.Square;
const Color = brd.Color;
const Pieces = brd.Pieces;
const Position = brd.Position;
const GameState = brd.GameState;

pub const Move = brd.Move;

pub const max_moves = 256;

pub const GenMode = enum { all, captures, quiets };

pub const MoveList = struct {
    moves: [max_moves]Move = undefined,
    len: usize = 0,

    pub const empty: MoveList = .{};

    pub inline fn add(self: *MoveList, m: Move) void {
        std.debug.assert(self.len < max_moves);
        self.moves[self.len] = m;
        self.len += 1;
    }

    pub inline fn clear(self: *MoveList) void {
        self.len = 0;
    }

    pub inline fn slice(self: *const MoveList) []const Move {
        return self.moves[0..self.len];
    }

    pub fn contains(self: *const MoveList, m: Move) bool {
        for (self.slice()) |x| {
            if (x.eql(m)) return true;
        }
        return false;
    }

    pub fn findUci(self: *const MoveList, uci: []const u8) ?Move {
        var buf: [5]u8 = undefined;
        for (self.slice()) |m| {
            if (std.mem.eql(u8, m.toUci(&buf), uci)) return m;
        }
        return null;
    }
};

pub const MoveGen = struct {
    kings: [brd.num_squares]Bitboard,
    knights: [brd.num_squares]Bitboard,
    pawns: [brd.num_colors][brd.num_squares]Bitboard,
    bishops: [brd.num_squares][512]Bitboard,
    rooks: [brd.num_squares][4096]Bitboard,
    bishop_masks: [brd.num_squares]Bitboard,
    rook_masks: [brd.num_squares]Bitboard,
    between: [brd.num_squares][brd.num_squares]Bitboard,
    line: [brd.num_squares][brd.num_squares]Bitboard,

    pub const LegalInfo = struct {
        king_sq: Square,
        checkers: Bitboard,
        check_mask: Bitboard,
        pinned: Bitboard,
    };

    pub fn init(self: *MoveGen) void {
        for (0..brd.num_squares) |i| {
            const sq: Square = @intCast(i);
            self.kings[sq] = kingAttacks(sq);
            self.knights[sq] = knightAttacks(sq);
            self.pawns[@intFromEnum(Color.White)][sq] = pawnAttacks(.White, sq);
            self.pawns[@intFromEnum(Color.Black)][sq] = pawnAttacks(.Black, sq);
        }
        self.initSliders();
        self.initLines();
    }

    pub fn generateMoves(self: *const MoveGen, gs: *const GameState, comptime mode: GenMode) MoveList {
        var list = MoveList{};
        self.appendMoves(gs, mode, &list);
        return list;
    }

    pub fn appendMoves(self: *const MoveGen, gs: *const GameState, comptime mode: GenMode, list: *MoveList) void {
        switch (gs.to_move) {
            .White => self.generateFor(.White, mode, gs, list),
            .Black => self.generateFor(.Black, mode, gs, list),
        }
    }

    pub fn generateLegal(self: *const MoveGen, gs: *const GameState, comptime mode: GenMode) MoveList {
        const info = self.legalInfo(gs);
        var list = self.generateMoves(gs, mode);
        var n: usize = 0;
        for (0..list.len) |i| {
            const m = list.moves[i];
            if (self.isLegal(gs, m, &info)) {
                list.moves[n] = m;
                n += 1;
            }
        }
        list.len = n;
        return list;
    }

    fn generateFor(self: *const MoveGen, comptime us: Color, comptime mode: GenMode, gs: *const GameState, list: *MoveList) void {
        const p = &gs.cur_position;
        const them = comptime us.opposite();
        const occ = p.getOccupancy();
        const enemy = p.getColorBoard(them) & ~p.getPieceColorBoard(.King, them);
        const targets: Bitboard = switch (mode) {
            .all => enemy | ~occ,
            .captures => enemy,
            .quiets => ~occ,
        };

        self.generatePawnMoves(us, mode, p, enemy, list);

        var knights = p.getPieceColorBoard(.Knight, us);
        while (knights != 0) {
            const from = brd.popLsb(&knights);
            emit(list, from, self.knights[from] & targets, enemy);
        }

        var diagonal = p.diagonalSliders(us);
        while (diagonal != 0) {
            const from = brd.popLsb(&diagonal);
            emit(list, from, self.getBishopAttacks(from, occ) & targets, enemy);
        }
        var straight = p.straightSliders(us);
        while (straight != 0) {
            const from = brd.popLsb(&straight);
            emit(list, from, self.getRookAttacks(from, occ) & targets, enemy);
        }

        const ksq = p.kingSquare(us);
        emit(list, ksq, self.kings[ksq] & targets, enemy);

        if (mode != .captures) self.generateCastles(us, gs, ksq, list);
    }

    inline fn emit(list: *MoveList, from: Square, dests: Bitboard, enemy: Bitboard) void {
        var caps = dests & enemy;
        while (caps != 0) {
            list.add(Move.capture(from, brd.popLsb(&caps)));
        }
        var quiets = dests & ~enemy;
        while (quiets != 0) {
            list.add(Move.quiet(from, brd.popLsb(&quiets)));
        }
    }

    inline fn shiftBack(to: Square, comptime delta: i16) Square {
        return @intCast(@as(i16, to) - delta);
    }

    fn generatePawnMoves(self: *const MoveGen, comptime us: Color, comptime mode: GenMode, p: *const Position, enemy: Bitboard, list: *MoveList) void {
        const pawns = p.getPieceColorBoard(.Pawn, us);
        if (pawns == 0) return;

        const empty = ~p.getOccupancy();
        const promo_rank = comptime brd.promoRankBB(us);
        const push: i16 = comptime if (us == .White) 8 else -8;
        const single = brd.forwardOne(us, pawns) & empty;

        if (mode != .quiets) {
            const cap_h: i16 = comptime if (us == .White) 9 else -7; // toward the h-file
            const cap_a: i16 = comptime if (us == .White) 7 else -9; // toward the a-file
            const toward_h = if (us == .White) brd.northEastOne(pawns) else brd.southEastOne(pawns);
            const toward_a = if (us == .White) brd.northWestOne(pawns) else brd.southWestOne(pawns);
            emitPawnCaptures(cap_h, promo_rank, toward_h & enemy, list);
            emitPawnCaptures(cap_a, promo_rank, toward_a & enemy, list);

            var queen_promos = single & promo_rank;
            while (queen_promos != 0) {
                const to = brd.popLsb(&queen_promos);
                list.add(Move.promotion(shiftBack(to, push), to, .Queen));
            }

            if (p.ep_sq) |ep| {
                const them_i = @intFromEnum(us.opposite());
                var from_bb = self.pawns[them_i][ep] & pawns;
                while (from_bb != 0) {
                    list.add(Move.enPassant(brd.popLsb(&from_bb), ep));
                }
            }
        }

        if (mode != .captures) {
            var under_promos = single & promo_rank;
            while (under_promos != 0) {
                const to = brd.popLsb(&under_promos);
                const from = shiftBack(to, push);
                list.add(Move.promotion(from, to, .Rook));
                list.add(Move.promotion(from, to, .Bishop));
                list.add(Move.promotion(from, to, .Knight));
            }

            var quiets = single & ~promo_rank;
            while (quiets != 0) {
                const to = brd.popLsb(&quiets);
                list.add(Move.quiet(shiftBack(to, push), to));
            }

            const dpp_rank = comptime brd.doublePushRankBB(us);
            var doubles = brd.forwardOne(us, single & dpp_rank) & empty;
            while (doubles != 0) {
                const to = brd.popLsb(&doubles);
                list.add(Move.doublePush(shiftBack(to, push * 2), to));
            }
        }
    }

    inline fn emitPawnCaptures(comptime delta: i16, promo_rank: Bitboard, dests: Bitboard, list: *MoveList) void {
        var promos = dests & promo_rank;
        while (promos != 0) {
            const to = brd.popLsb(&promos);
            const from = shiftBack(to, delta);
            inline for ([_]Move.PFlags{ .Queen, .Rook, .Bishop, .Knight }) |pf| {
                list.add(Move.promoCapture(from, to, pf));
            }
        }
        var normal = dests & ~promo_rank;
        while (normal != 0) {
            const to = brd.popLsb(&normal);
            list.add(Move.capture(shiftBack(to, delta), to));
        }
    }

    fn generateCastles(self: *const MoveGen, comptime us: Color, gs: *const GameState, king_sq: Square, list: *MoveList) void {
        const cr = gs.cur_position.castle;
        inline for ([_]bool{ true, false }) |kingside| {
            const right = comptime brd.castleRight(us, kingside);
            if (brd.hasCastleRight(cr, right) and self.castleLegal(gs, us, king_sq, kingside)) {
                list.add(Move.castle(king_sq, GameState.kingCastleDest(us, kingside), kingside));
            }
        }
    }

    inline fn spanInclusive(a: Square, b: Square) Bitboard {
        std.debug.assert(brd.rankOf(a) == brd.rankOf(b));
        const lo = @min(a, b);
        const hi = @max(a, b);
        const n: u6 = @intCast(@as(u7, hi - lo) + 1);
        return ((@as(Bitboard, 1) << n) - 1) << lo;
    }

    fn castleLegal(self: *const MoveGen, gs: *const GameState, us: Color, king_sq: Square, kingside: bool) bool {
        const p = &gs.cur_position;
        const them = us.opposite();

        const rook_from = gs.rookSquare(us, kingside);
        const rook_pc = p.getFromSquare(rook_from);
        if (rook_pc.piece != .Rook or rook_pc.color != us) return false;

        const king_to = GameState.kingCastleDest(us, kingside);
        const rook_to = GameState.rookCastleDest(us, kingside);

        const occ = p.getOccupancy() & ~(brd.getSquareBB(king_sq) | brd.getSquareBB(rook_from));
        const king_path = spanInclusive(king_sq, king_to);
        const rook_path = spanInclusive(rook_from, rook_to);
        if ((occ & (king_path | rook_path)) != 0) return false;

        var walk = king_path;
        while (walk != 0) {
            if (self.isSquareAttackedBy(p, brd.popLsb(&walk), them, occ)) return false;
        }
        return true;
    }

    pub fn legalInfo(self: *const MoveGen, gs: *const GameState) LegalInfo {
        const p = &gs.cur_position;
        const us = gs.to_move;
        const them = us.opposite();
        const ksq = p.kingSquare(us);
        const occ = p.getOccupancy();

        const checkers = (self.knights[ksq] & p.getPieceColorBoard(.Knight, them)) |
            (self.pawns[@intFromEnum(us)][ksq] & p.getPieceColorBoard(.Pawn, them)) |
            (self.getBishopAttacks(ksq, occ) & p.diagonalSliders(them)) |
            (self.getRookAttacks(ksq, occ) & p.straightSliders(them));

        const check_mask: Bitboard = switch (@popCount(checkers)) {
            0 => ~@as(Bitboard, 0),
            1 => blk: {
                const checker_sq = brd.lsb(checkers);
                break :blk checkers | self.between[ksq][checker_sq];
            },
            else => 0,
        };

        const ours = p.getColorBoard(us);
        var pinned: Bitboard = 0;
        var snipers = (self.getRookAttacks(ksq, 0) & p.straightSliders(them)) |
            (self.getBishopAttacks(ksq, 0) & p.diagonalSliders(them));
        while (snipers != 0) {
            const s = brd.popLsb(&snipers);
            const blockers = self.between[ksq][s] & occ;
            if (blockers != 0 and (blockers & (blockers - 1)) == 0) pinned |= blockers & ours;
        }

        return .{
            .king_sq = ksq,
            .checkers = checkers,
            .check_mask = check_mask,
            .pinned = pinned,
        };
    }

    pub fn isLegal(self: *const MoveGen, gs: *const GameState, m: Move, info: *const LegalInfo) bool {
        const p = &gs.cur_position;

        if (m.isCastle()) return true;
        if (m.isEP()) return self.epLegal(p, gs.to_move, info, m.from, m.to);

        const to_bb = brd.getSquareBB(m.to);
        if (m.from == info.king_sq) {
            const occ = p.getOccupancy() ^ brd.getSquareBB(m.from);
            return !self.isSquareAttackedBy(p, m.to, gs.to_move.opposite(), occ);
        }

        if ((info.check_mask & to_bb) == 0) return false;
        return !brd.getBit(info.pinned, m.from) or (self.line[info.king_sq][m.from] & to_bb) != 0;
    }

    fn epLegal(self: *const MoveGen, p: *const Position, us: Color, info: *const LegalInfo, from: Square, ep: Square) bool {
        const cap_sq: Square = if (us == .White) ep - 8 else ep + 8;
        if (((brd.getSquareBB(ep) | brd.getSquareBB(cap_sq)) & info.check_mask) == 0) return false;

        const them = us.opposite();
        const occ = (p.getOccupancy() ^ brd.getSquareBB(from) ^ brd.getSquareBB(cap_sq)) | brd.getSquareBB(ep);
        if (self.getBishopAttacks(info.king_sq, occ) & p.diagonalSliders(them) != 0) return false;
        if (self.getRookAttacks(info.king_sq, occ) & p.straightSliders(them) != 0) return false;
        return true;
    }

    pub const CheckInfo = struct {
        ksq: Square,
        squares: [7]Bitboard,
        blockers: Bitboard,
    };

    pub fn checkInfo(self: *const MoveGen, gs: *const GameState) CheckInfo {
        const p = &gs.cur_position;
        const us = gs.to_move;
        const them = us.opposite();
        const ksq = p.kingSquare(them);
        const occ = p.getOccupancy();

        var ci: CheckInfo = .{ .ksq = ksq, .squares = @splat(0), .blockers = 0 };
        const bishop = self.getBishopAttacks(ksq, occ);
        const rook = self.getRookAttacks(ksq, occ);
        ci.squares[@intFromEnum(Pieces.Pawn)] = self.pawns[@intFromEnum(them)][ksq];
        ci.squares[@intFromEnum(Pieces.Knight)] = self.knights[ksq];
        ci.squares[@intFromEnum(Pieces.Bishop)] = bishop;
        ci.squares[@intFromEnum(Pieces.Rook)] = rook;
        ci.squares[@intFromEnum(Pieces.Queen)] = bishop | rook;

        var snipers = (self.getRookAttacks(ksq, 0) & p.straightSliders(us)) |
            (self.getBishopAttacks(ksq, 0) & p.diagonalSliders(us));
        while (snipers != 0) {
            const s = brd.popLsb(&snipers);
            const between = self.between[ksq][s] & occ;
            if (between != 0 and (between & (between - 1)) == 0) {
                ci.blockers |= between & p.getColorBoard(us);
            }
        }
        return ci;
    }

    pub fn givesCheck(self: *const MoveGen, gs: *const GameState, m: Move, ci: *const CheckInfo) bool {
        const p = &gs.cur_position;
        const to_bb = brd.getSquareBB(m.to);

        if (m.isPromo()) {
            const occ = (p.getOccupancy() ^ brd.getSquareBB(m.from)) | to_bb;
            const att: Bitboard = switch (m.promoPiece()) {
                .Knight => self.knights[m.to],
                .Bishop => self.getBishopAttacks(m.to, occ),
                .Rook => self.getRookAttacks(m.to, occ),
                .Queen => self.getQueenAttacks(m.to, occ),
                else => 0,
            };
            if (att & brd.getSquareBB(ci.ksq) != 0) return true;
        } else if (!m.isCastle()) {
            const piece = p.getPieceFromSquare(m.from);
            if (ci.squares[@intFromEnum(piece)] & to_bb != 0) return true;
        }

        if (brd.getBit(ci.blockers, m.from) and (self.line[ci.ksq][m.from] & to_bb) == 0) return true;

        return false;
    }

    pub fn verifyGivesCheck(self: *const MoveGen, gs: *GameState) bool {
        const ci = self.checkInfo(gs);
        const them = gs.to_move.opposite();
        const list = self.generateLegal(gs, .all);
        var ok = true;
        for (list.slice()) |m| {
            const predicted = self.givesCheck(gs, m, &ci);
            gs.makeMove(m);
            const actual = self.isInCheck(&gs.cur_position, them);
            gs.unmakeMove(m);
            const exact = !m.isCastle() and !m.isEP();
            if (predicted != actual and (exact or predicted)) {
                var buf: [5]u8 = undefined;
                std.debug.print("givesCheck mismatch: {s} predicted={} actual={}\n", .{ m.toUci(&buf), predicted, actual });
                ok = false;
            }
        }
        return ok;
    }

    pub fn isPseudoLegal(self: *const MoveGen, gs: *const GameState, m: Move) bool {
        if (m.isNull()) return false;

        const p = &gs.cur_position;
        const us = gs.to_move;
        const them = us.opposite();

        const pc = p.getFromSquare(m.from);
        if (pc.isNone() or pc.color != us) return false;

        if (m.cap == 1 and m.promo == 0 and m.flags > 1) return false;

        if (m.isCastle()) {
            if (pc.piece != .King) return false;
            const kingside = m.isKingsideCastle();
            if (!brd.hasCastleRight(p.castle, brd.castleRight(us, kingside))) return false;
            if (m.to != GameState.kingCastleDest(us, kingside)) return false;
            return self.castleLegal(gs, us, m.from, kingside);
        }

        const to_bb = brd.getSquareBB(m.to);

        if (m.isEP()) {
            if (pc.piece != .Pawn) return false;
            const ep = p.ep_sq orelse return false;
            return m.to == ep and (self.pawns[@intFromEnum(us)][m.from] & to_bb) != 0;
        }

        const target = p.getFromSquare(m.to);
        if (m.isCapture()) {
            if (target.isNone() or target.color != them or target.piece == .King) return false;
        } else if (!target.isNone()) {
            return false;
        }

        const occ = p.getOccupancy();
        switch (pc.piece) {
            .Knight, .Bishop, .Rook, .Queen, .King => {
                if (m.promo != 0 or m.flags != 0) return false;
                const attacks = switch (pc.piece) {
                    .Knight => self.knights[m.from],
                    .Bishop => self.getBishopAttacks(m.from, occ),
                    .Rook => self.getRookAttacks(m.from, occ),
                    .Queen => self.getQueenAttacks(m.from, occ),
                    else => self.kings[m.from],
                };
                return (attacks & to_bb) != 0;
            },
            .Pawn => {
                if (m.isPromo() != ((brd.promoRankBB(us) & to_bb) != 0)) return false;

                if (m.isCapture()) {
                    return (self.pawns[@intFromEnum(us)][m.from] & to_bb) != 0;
                }

                const push: i16 = if (us == .White) 8 else -8;
                const from_i: i16 = m.from;
                const to_i: i16 = m.to;

                if (m.isDoublePP()) {
                    const start_rank: u3 = if (us == .White) 1 else 6;
                    if (brd.rankOf(m.from) != start_rank) return false;
                    if (to_i != from_i + 2 * push) return false;
                    const mid: Square = @intCast(from_i + push);
                    return !brd.getBit(occ, mid);
                }

                return to_i == from_i + push;
            },
            .None => return false,
        }
    }

    pub inline fn getBishopAttacks(self: *const MoveGen, sq: Square, occ: Bitboard) Bitboard {
        const shift: u6 = @intCast(64 - rad.bishop_relevant_bits[sq]);
        const idx = ((occ & self.bishop_masks[sq]) *% magic.bishop_magics[sq]) >> shift;
        return self.bishops[sq][idx];
    }

    pub inline fn getRookAttacks(self: *const MoveGen, sq: Square, occ: Bitboard) Bitboard {
        const shift: u6 = @intCast(64 - rad.rook_relevant_bits[sq]);
        const idx = ((occ & self.rook_masks[sq]) *% magic.rook_magics[sq]) >> shift;
        return self.rooks[sq][idx];
    }

    pub inline fn getQueenAttacks(self: *const MoveGen, sq: Square, occ: Bitboard) Bitboard {
        return self.getBishopAttacks(sq, occ) | self.getRookAttacks(sq, occ);
    }

    pub inline fn isSquareAttackedBy(self: *const MoveGen, p: *const Position, sq: Square, by: Color, occ: Bitboard) bool {
        if ((self.knights[sq] & p.getPieceColorBoard(.Knight, by)) != 0) return true;
        const them_i = @intFromEnum(by.opposite());
        if ((self.pawns[them_i][sq] & p.getPieceColorBoard(.Pawn, by)) != 0) return true;
        if ((self.kings[sq] & p.getPieceColorBoard(.King, by)) != 0) return true;
        if ((self.getBishopAttacks(sq, occ) & p.diagonalSliders(by)) != 0) return true;
        if ((self.getRookAttacks(sq, occ) & p.straightSliders(by)) != 0) return true;
        return false;
    }

    pub inline fn isAttacked(self: *const MoveGen, p: *const Position, sq: Square, by: Color) bool {
        return self.isSquareAttackedBy(p, sq, by, p.getOccupancy());
    }

    pub fn isInCheck(self: *const MoveGen, p: *const Position, c: Color) bool {
        return self.isAttacked(p, p.kingSquare(c), c.opposite());
    }

    pub fn attackersTo(self: *const MoveGen, p: *const Position, sq: Square, occ: Bitboard) Bitboard {
        return (self.pawns[@intFromEnum(Color.White)][sq] & p.getPieceColorBoard(.Pawn, .Black)) |
            (self.pawns[@intFromEnum(Color.Black)][sq] & p.getPieceColorBoard(.Pawn, .White)) |
            (self.knights[sq] & p.getPieceBoard(.Knight)) |
            (self.getBishopAttacks(sq, occ) & (p.getPieceBoard(.Bishop) | p.getPieceBoard(.Queen))) |
            (self.getRookAttacks(sq, occ) & (p.getPieceBoard(.Rook) | p.getPieceBoard(.Queen))) |
            (self.kings[sq] & p.getPieceBoard(.King));
    }

    fn initSliders(self: *MoveGen) void {
        for (0..brd.num_squares) |i| {
            const sq: Square = @intCast(i);
            self.bishop_masks[sq] = rad.maskBishopAttacks(sq);
            self.rook_masks[sq] = rad.maskRookAttacks(sq);

            const bishop_bits: i32 = @intCast(rad.bishop_relevant_bits[sq]);
            const rook_bits: i32 = @intCast(rad.rook_relevant_bits[sq]);
            const bishop_shift: u6 = @intCast(64 - bishop_bits);
            const rook_shift: u6 = @intCast(64 - rook_bits);

            for (0..(@as(usize, 1) << @intCast(bishop_bits))) |index| {
                const occ = rad.setOccupancy(index, bishop_bits, self.bishop_masks[sq]);
                const magic_index = (occ *% magic.bishop_magics[sq]) >> bishop_shift;
                self.bishops[sq][magic_index] = rad.bishopAttacks(sq, occ);
            }

            for (0..(@as(usize, 1) << @intCast(rook_bits))) |index| {
                const occ = rad.setOccupancy(index, rook_bits, self.rook_masks[sq]);
                const magic_index = (occ *% magic.rook_magics[sq]) >> rook_shift;
                self.rooks[sq][magic_index] = rad.rookAttacks(sq, occ);
            }
        }
    }

    fn initLines(self: *MoveGen) void {
        for (0..brd.num_squares) |ai| {
            const a: Square = @intCast(ai);
            const a_bb = brd.getSquareBB(a);
            for (0..brd.num_squares) |bi| {
                const b: Square = @intCast(bi);
                const b_bb = brd.getSquareBB(b);
                self.between[a][b] = 0;
                self.line[a][b] = 0;
                if (a == b) continue;

                if ((self.getRookAttacks(a, 0) & b_bb) != 0) {
                    self.between[a][b] = self.getRookAttacks(a, b_bb) & self.getRookAttacks(b, a_bb);
                    self.line[a][b] = (self.getRookAttacks(a, 0) & self.getRookAttacks(b, 0)) | a_bb | b_bb;
                } else if ((self.getBishopAttacks(a, 0) & b_bb) != 0) {
                    self.between[a][b] = self.getBishopAttacks(a, b_bb) & self.getBishopAttacks(b, a_bb);
                    self.line[a][b] = (self.getBishopAttacks(a, 0) & self.getBishopAttacks(b, 0)) | a_bb | b_bb;
                }
            }
        }
    }
};

fn kingAttacks(sq: Square) Bitboard {
    const b = brd.getSquareBB(sq);
    const row = b | brd.eastOne(b) | brd.westOne(b);
    return (row | brd.northOne(row) | brd.southOne(row)) ^ b;
}

fn knightAttacks(sq: Square) Bitboard {
    const b = brd.getSquareBB(sq);
    return ((b & brd.not_h_file) << 17) | ((b & brd.not_h_file) >> 15) |
        ((b & brd.not_a_file) << 15) | ((b & brd.not_a_file) >> 17) |
        ((b & brd.not_gh_file) << 10) | ((b & brd.not_gh_file) >> 6) |
        ((b & brd.not_ab_file) << 6) | ((b & brd.not_ab_file) >> 10);
}

fn pawnAttacks(comptime c: Color, sq: Square) Bitboard {
    const b = brd.getSquareBB(sq);
    return if (c == .White)
        brd.northEastOne(b) | brd.northWestOne(b)
    else
        brd.southEastOne(b) | brd.southWestOne(b);
}

pub fn parseMove(gs: *const GameState, move_str: []const u8, chess960: bool) ?Move {
    if (move_str.len != 4 and move_str.len != 5) return null;
    const from = brd.parseSquare(move_str[0..2]) orelse return null;
    const to = brd.parseSquare(move_str[2..4]) orelse return null;

    const p = &gs.cur_position;
    const us = gs.to_move;
    const pc = p.getFromSquare(from);
    if (pc.isNone() or pc.color != us) return null;
    const target = p.getFromSquare(to);

    if (pc.piece == .King and move_str.len == 4) {
        for ([_]bool{ true, false }) |kingside| {
            if (!brd.hasCastleRight(p.castle, brd.castleRight(us, kingside))) continue;
            const king_to = GameState.kingCastleDest(us, kingside);
            const own_rook = target.piece == .Rook and target.color == us;
            if (own_rook and to == gs.rookSquare(us, kingside)) return Move.castle(from, king_to, kingside);
            if (!chess960 and to == king_to) return Move.castle(from, king_to, kingside);
        }
    }

    if (!target.isNone() and target.color == us) return null;
    const is_capture = !target.isNone();

    if (move_str.len == 5) {
        if (pc.piece != .Pawn) return null;
        const promo: Pieces = switch (move_str[4]) {
            'n' => .Knight,
            'b' => .Bishop,
            'r' => .Rook,
            'q' => .Queen,
            else => return null,
        };
        const pf = Move.promoFlag(promo);
        return if (is_capture) Move.promoCapture(from, to, pf) else Move.promotion(from, to, pf);
    }

    if (pc.piece == .Pawn) {
        if ((brd.promoRankBB(us) & brd.getSquareBB(to)) != 0) return null;
        if (!is_capture and brd.fileOf(from) != brd.fileOf(to)) {
            if (p.ep_sq) |ep| {
                if (to == ep) return Move.enPassant(from, to);
            }
            return null;
        }
        if (@max(from, to) - @min(from, to) == 16) return Move.doublePush(from, to);
    }

    return if (is_capture) Move.capture(from, to) else Move.quiet(from, to);
}

pub fn moveToUci(gs: *const GameState, m: Move, chess960: bool, buf: *[5]u8) []const u8 {
    if (chess960 and m.isCastle()) {
        const c: Color = if (brd.rankOf(m.from) == 0) .White else .Black;
        _ = brd.squareToString(m.from, buf[0..2]);
        _ = brd.squareToString(gs.rookSquare(c, m.isKingsideCastle()), buf[2..4]);
        return buf[0..4];
    }
    return m.toUci(buf);
}
