const std = @import("std");
const root = @import("root.zig");
const zob = root.zob;
const nnue = root.nnue;

pub const num_colors = 2;
pub const num_pieces = 6;
pub const num_squares = 64;
pub const num_files = 8;
pub const num_ranks = 8;
pub const max_pieces = 32;
pub const max_game_moves = 1021;

pub const Bitboard = u64;
pub const Square = u6;
pub const ZobristKey = zob.ZobristKey;

pub const CastleValues = enum(u4) {
    NoCastling = 0,
    WhiteKingside = 1,
    WhiteQueenside = 2,
    AllWhite = 3,
    BlackKingside = 4,
    BlackQueenside = 8,
    AllBlack = 12,
    AllCastling = 15,
};

pub const CastleRights = u4;

pub inline fn removeCastleRights(cr: CastleRights, cv: CastleValues) CastleRights {
    return cr & ~@intFromEnum(cv);
}

pub inline fn hasCastleRight(cr: CastleRights, cv: CastleValues) bool {
    return (cr & @intFromEnum(cv)) != 0;
}

pub inline fn colorCastleRights(c: Color) CastleValues {
    return if (c == .White) .AllWhite else .AllBlack;
}

pub inline fn castleRight(c: Color, kingside: bool) CastleValues {
    return if (c == .White)
        (if (kingside) .WhiteKingside else .WhiteQueenside)
    else
        (if (kingside) .BlackKingside else .BlackQueenside);
}

pub const Pieces = enum(u3) {
    Pawn = 0,
    Knight = 1,
    Bishop = 2,
    Rook = 3,
    Queen = 4,
    King = 5,
    None = 6,

    pub inline fn isNone(self: Pieces) bool {
        return self == .None;
    }

    pub inline fn idx(self: Pieces) usize {
        return @intFromEnum(self);
    }
};

pub const Color = enum(u1) {
    White = 0,
    Black = 1,

    pub inline fn opposite(self: Color) Color {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }

    pub inline fn idx(self: Color) usize {
        return @intFromEnum(self);
    }
};

pub const Piece = packed struct(u4) {
    piece: Pieces,
    color: Color,

    pub const none: Piece = .{ .piece = .None, .color = .White };

    pub fn fromChar(c: u8) ?Piece {
        const color: Color = if (c >= 'A' and c <= 'Z') .White else .Black;
        const piece: Pieces = switch (std.ascii.toLower(c)) {
            'p' => .Pawn,
            'n' => .Knight,
            'b' => .Bishop,
            'r' => .Rook,
            'q' => .Queen,
            'k' => .King,
            else => return null,
        };
        return .{ .piece = piece, .color = color };
    }

    pub fn toChar(self: Piece) u8 {
        const c: u8 = switch (self.piece) {
            .Pawn => 'p',
            .Knight => 'n',
            .Bishop => 'b',
            .Rook => 'r',
            .Queen => 'q',
            .King => 'k',
            .None => return '.',
        };
        return if (self.color == .White) std.ascii.toUpper(c) else c;
    }

    pub inline fn isNone(self: Piece) bool {
        return self.piece == .None;
    }

    pub inline fn eql(self: Piece, other: Piece) bool {
        return @as(u4, @bitCast(self)) == @as(u4, @bitCast(other));
    }
};

pub const PlacedPiece = struct {
    color: Color,
    piece: Pieces,
    square: Square,
};

pub const file_a: Bitboard = 0x0101010101010101;
pub const file_h: Bitboard = 0x8080808080808080;
pub const not_a_file: Bitboard = ~file_a;
pub const not_h_file: Bitboard = ~file_h;
pub const not_ab_file: Bitboard = 0xfcfcfcfcfcfcfcfc;
pub const not_gh_file: Bitboard = 0x3f3f3f3f3f3f3f3f;
pub const rank_1: Bitboard = 0x00000000000000ff;
pub const rank_3: Bitboard = 0x0000000000ff0000;
pub const rank_6: Bitboard = 0x0000ff0000000000;
pub const rank_8: Bitboard = 0xff00000000000000;
pub const dark_squares: Bitboard = 0xaa55aa55aa55aa55;

pub inline fn squareFromFileRank(file: u3, rank: u3) Square {
    return (@as(Square, rank) * 8) + @as(Square, file);
}

pub inline fn fileOf(sq: Square) u3 {
    return @truncate(sq);
}

pub inline fn rankOf(sq: Square) u3 {
    return @intCast(sq >> 3);
}

pub inline fn getSquareBB(sq: Square) Bitboard {
    return @as(Bitboard, 1) << sq;
}

pub inline fn getBit(bb: Bitboard, sq: Square) bool {
    return (bb & getSquareBB(sq)) != 0;
}

pub inline fn setBit(bb: *Bitboard, sq: Square) void {
    bb.* |= getSquareBB(sq);
}

pub inline fn clearBit(bb: *Bitboard, sq: Square) void {
    bb.* &= ~getSquareBB(sq);
}

pub inline fn countBits(bb: Bitboard) u32 {
    return @popCount(bb);
}

pub inline fn lsb(bb: Bitboard) Square {
    std.debug.assert(bb != 0);
    return @intCast(@ctz(bb));
}

pub inline fn popLsb(bb: *Bitboard) Square {
    const sq = lsb(bb.*);
    bb.* &= bb.* - 1;
    return sq;
}

pub inline fn northOne(b: Bitboard) Bitboard {
    return b << 8;
}

pub inline fn southOne(b: Bitboard) Bitboard {
    return b >> 8;
}

pub inline fn eastOne(b: Bitboard) Bitboard {
    return (b & not_h_file) << 1;
}

pub inline fn westOne(b: Bitboard) Bitboard {
    return (b & not_a_file) >> 1;
}

pub inline fn northEastOne(b: Bitboard) Bitboard {
    return (b & not_h_file) << 9;
}

pub inline fn northWestOne(b: Bitboard) Bitboard {
    return (b & not_a_file) << 7;
}

pub inline fn southEastOne(b: Bitboard) Bitboard {
    return (b & not_h_file) >> 7;
}

pub inline fn southWestOne(b: Bitboard) Bitboard {
    return (b & not_a_file) >> 9;
}

pub inline fn forwardOne(comptime c: Color, b: Bitboard) Bitboard {
    return if (c == .White) northOne(b) else southOne(b);
}

pub inline fn promoRankBB(c: Color) Bitboard {
    return if (c == .White) rank_8 else rank_1;
}

pub inline fn doublePushRankBB(c: Color) Bitboard {
    return if (c == .White) rank_3 else rank_6;
}

pub fn squareToString(sq: Square, buf: *[2]u8) []const u8 {
    buf[0] = 'a' + @as(u8, fileOf(sq));
    buf[1] = '1' + @as(u8, rankOf(sq));
    return buf;
}

pub fn parseSquare(s: []const u8) ?Square {
    if (s.len != 2) return null;
    if (s[0] < 'a' or s[0] > 'h' or s[1] < '1' or s[1] > '8') return null;
    return squareFromFileRank(@intCast(s[0] - 'a'), @intCast(s[1] - '1'));
}

pub fn bitboardToArray(bb: Bitboard) [64]bool {
    var arr: [64]bool = undefined;
    for (0..64) |i| {
        arr[i] = getBit(bb, @intCast(i));
    }
    return arr;
}

pub const Move = packed struct(u16) {
    pub const PFlags = enum(u2) {
        Knight = 0,
        Bishop = 1,
        Rook = 2,
        Queen = 3,
    };
    pub const QNFlags = enum(u2) {
        NQM = 0, // normal quiet move
        DPP = 1, // double pawn push
        QSC = 2, // queen side castle
        KSC = 3, // king side castle
    };
    pub const CNFlags = enum(u2) {
        NCM = 0, // normal capture move
        EP = 1, // en passant
    };

    from: Square,
    to: Square,

    cap: u1,
    promo: u1,
    flags: u2,

    pub const none: Move = .{ .from = 0, .to = 0, .cap = 0, .promo = 0, .flags = 0 };

    pub inline fn quiet(from: Square, to: Square) Move {
        return .{ .from = from, .to = to, .cap = 0, .promo = 0, .flags = @intFromEnum(QNFlags.NQM) };
    }

    pub inline fn doublePush(from: Square, to: Square) Move {
        return .{ .from = from, .to = to, .cap = 0, .promo = 0, .flags = @intFromEnum(QNFlags.DPP) };
    }

    pub inline fn castle(from: Square, to: Square, kingside: bool) Move {
        const f: QNFlags = if (kingside) .KSC else .QSC;
        return .{ .from = from, .to = to, .cap = 0, .promo = 0, .flags = @intFromEnum(f) };
    }

    pub inline fn capture(from: Square, to: Square) Move {
        return .{ .from = from, .to = to, .cap = 1, .promo = 0, .flags = @intFromEnum(CNFlags.NCM) };
    }

    pub inline fn enPassant(from: Square, to: Square) Move {
        return .{ .from = from, .to = to, .cap = 1, .promo = 0, .flags = @intFromEnum(CNFlags.EP) };
    }

    pub inline fn promotion(from: Square, to: Square, p: PFlags) Move {
        return .{ .from = from, .to = to, .cap = 0, .promo = 1, .flags = @intFromEnum(p) };
    }

    pub inline fn promoCapture(from: Square, to: Square, p: PFlags) Move {
        return .{ .from = from, .to = to, .cap = 1, .promo = 1, .flags = @intFromEnum(p) };
    }

    pub inline fn promoFlag(p: Pieces) PFlags {
        std.debug.assert(p != .Pawn and p != .King and p != .None);
        return @enumFromInt(@intFromEnum(p) - 1);
    }

    pub inline fn toU16(self: Move) u16 {
        return @bitCast(self);
    }

    pub inline fn fromU16(v: u16) Move {
        return @bitCast(v);
    }

    pub inline fn isNull(self: Move) bool {
        return self.toU16() == 0;
    }

    pub inline fn isCapture(self: Move) bool {
        return self.cap != 0;
    }

    pub inline fn isPromo(self: Move) bool {
        return self.promo != 0;
    }

    pub inline fn isCastle(self: Move) bool {
        return self.cap == 0 and self.promo == 0 and (self.flags >> 1) == 1;
    }

    pub inline fn isKingsideCastle(self: Move) bool {
        return self.isCastle() and self.flags == @intFromEnum(QNFlags.KSC);
    }

    pub inline fn isEP(self: Move) bool {
        return self.cap == 1 and self.promo == 0 and self.flags == @intFromEnum(CNFlags.EP);
    }

    pub inline fn isDoublePP(self: Move) bool {
        return self.cap == 0 and self.promo == 0 and self.flags == @intFromEnum(QNFlags.DPP);
    }

    pub inline fn isQuiet(self: Move) bool {
        return self.cap == 0 and self.promo == 0;
    }

    pub inline fn isNoisy(self: Move) bool {
        return self.cap != 0 or (self.promo != 0 and self.flags == @intFromEnum(PFlags.Queen));
    }

    pub inline fn promoPiece(self: Move) Pieces {
        return @enumFromInt(@as(u3, self.flags) + 1);
    }

    pub fn toUci(self: Move, buf: *[5]u8) []const u8 {
        _ = squareToString(self.from, buf[0..2]);
        _ = squareToString(self.to, buf[2..4]);
        if (self.isPromo()) {
            buf[4] = switch (self.promoPiece()) {
                .Knight => 'n',
                .Bishop => 'b',
                .Rook => 'r',
                else => 'q',
            };
            return buf[0..5];
        }
        return buf[0..4];
    }

    pub inline fn eql(self: Move, other: Move) bool {
        return self.toU16() == other.toU16();
    }
};

pub const UndoInfo = struct {
    captured: Piece,
    castle: CastleRights,
    ep_sq: ?Square,
    halfmove: u8,
    key: ZobristKey,
};

pub const DirtyPiece = struct {
    piece: Piece,
    sq: Square,
};

pub const DirtyPieces = struct {
    removed: [2]DirtyPiece = undefined,
    added: [2]DirtyPiece = undefined,
    num_removed: u2 = 0,
    num_added: u2 = 0,

    inline fn remove(self: *DirtyPieces, pc: Piece, sq: Square) void {
        self.removed[self.num_removed] = .{ .piece = pc, .sq = sq };
        self.num_removed += 1;
    }

    inline fn add(self: *DirtyPieces, pc: Piece, sq: Square) void {
        self.added[self.num_added] = .{ .piece = pc, .sq = sq };
        self.num_added += 1;
    }

    pub inline fn removedSlice(self: *const DirtyPieces) []const DirtyPiece {
        return self.removed[0..self.num_removed];
    }

    pub inline fn addedSlice(self: *const DirtyPieces) []const DirtyPiece {
        return self.added[0..self.num_added];
    }
};

pub const Position = struct {
    mailbox: [num_squares]Piece,
    piece_bb: [num_pieces]Bitboard,
    color_bb: [num_colors]Bitboard,
    castle: CastleRights,
    ep_sq: ?Square,
    halfmove: u8,

    hash: ZobristKey,
    pawn_hash: ZobristKey,
    non_pawn_hash: [num_colors]ZobristKey,
    major_hash: ZobristKey,
    minor_hash: ZobristKey,

    pub fn init() Position {
        return .{
            .mailbox = [_]Piece{Piece.none} ** num_squares,
            .piece_bb = [_]Bitboard{0} ** num_pieces,
            .color_bb = [_]Bitboard{0} ** num_colors,
            .castle = 0,
            .ep_sq = null,
            .halfmove = 0,
            .hash = 0,
            .pawn_hash = 0,
            .non_pawn_hash = [_]ZobristKey{0} ** num_colors,
            .major_hash = 0,
            .minor_hash = 0,
        };
    }

    pub inline fn getOccupancy(self: *const Position) Bitboard {
        return self.color_bb[0] | self.color_bb[1];
    }

    pub inline fn getColorBoard(self: *const Position, c: Color) Bitboard {
        return self.color_bb[@intFromEnum(c)];
    }

    pub inline fn getPieceBoard(self: *const Position, p: Pieces) Bitboard {
        if (p != .None) return self.piece_bb[@intFromEnum(p)];
        return ~self.getOccupancy();
    }

    pub inline fn getPieceColorBoard(self: *const Position, p: Pieces, c: Color) Bitboard {
        if (p != .None) return self.piece_bb[@intFromEnum(p)] & self.color_bb[@intFromEnum(c)];
        return ~self.getOccupancy();
    }

    pub inline fn diagonalSliders(self: *const Position, c: Color) Bitboard {
        return (self.piece_bb[@intFromEnum(Pieces.Bishop)] | self.piece_bb[@intFromEnum(Pieces.Queen)]) &
            self.color_bb[@intFromEnum(c)];
    }

    pub inline fn straightSliders(self: *const Position, c: Color) Bitboard {
        return (self.piece_bb[@intFromEnum(Pieces.Rook)] | self.piece_bb[@intFromEnum(Pieces.Queen)]) &
            self.color_bb[@intFromEnum(c)];
    }

    pub inline fn kingSquare(self: *const Position, c: Color) Square {
        return lsb(self.getPieceColorBoard(.King, c));
    }

    pub inline fn getFromSquare(self: *const Position, sq: Square) Piece {
        return self.mailbox[sq];
    }

    pub inline fn getPieceFromSquare(self: *const Position, sq: Square) Pieces {
        return self.mailbox[sq].piece;
    }

    pub inline fn getColorFromSquare(self: *const Position, sq: Square) Color {
        return self.mailbox[sq].color;
    }

    pub inline fn movedPiece(self: *const Position, m: Move) Piece {
        return self.mailbox[m.from];
    }

    pub inline fn capturedPiece(self: *const Position, m: Move) Piece {
        if (!m.isCapture()) return Piece.none;
        if (m.isEP()) return .{ .piece = .Pawn, .color = self.mailbox[m.from].color.opposite() };
        return self.mailbox[m.to];
    }

    pub inline fn captureSquare(self: *const Position, m: Move) Square {
        if (!m.isEP()) return m.to;
        return if (self.mailbox[m.from].color == .White) m.to - 8 else m.to + 8;
    }

    pub fn hasNonPawnMaterial(self: *const Position, c: Color) bool {
        const non_pawn = self.piece_bb[@intFromEnum(Pieces.Knight)] | self.piece_bb[@intFromEnum(Pieces.Bishop)] |
            self.piece_bb[@intFromEnum(Pieces.Rook)] | self.piece_bb[@intFromEnum(Pieces.Queen)];
        return (non_pawn & self.color_bb[@intFromEnum(c)]) != 0;
    }

    pub fn isMaterialDraw(self: *const Position) bool {
        const heavy_or_pawns = self.piece_bb[@intFromEnum(Pieces.Pawn)] | self.piece_bb[@intFromEnum(Pieces.Rook)] |
            self.piece_bb[@intFromEnum(Pieces.Queen)];
        if (heavy_or_pawns != 0) return false;

        const knights = self.piece_bb[@intFromEnum(Pieces.Knight)];
        const bishops = self.piece_bb[@intFromEnum(Pieces.Bishop)];
        const white_minors = @popCount((knights | bishops) & self.color_bb[0]);
        const black_minors = @popCount((knights | bishops) & self.color_bb[1]);

        if (white_minors + black_minors <= 1) return true;

        if (knights == 0 and white_minors == 1 and black_minors == 1) {
            const white_on_dark = (bishops & self.color_bb[0] & dark_squares) != 0;
            const black_on_dark = (bishops & self.color_bb[1] & dark_squares) != 0;
            if (white_on_dark == black_on_dark) return true;
        }

        return false;
    }

    pub fn getPieceList(self: *const Position) [max_pieces]?PlacedPiece {
        var list: [max_pieces]?PlacedPiece = undefined;
        var count: usize = 0;
        for ([_]Color{ .White, .Black }) |c| {
            for (0..num_pieces) |pi| {
                const p: Pieces = @enumFromInt(pi);
                var bb = self.getPieceColorBoard(p, c);
                while (bb != 0 and count < max_pieces) : (count += 1) {
                    list[count] = .{ .color = c, .piece = p, .square = popLsb(&bb) };
                }
            }
        }
        if (count < max_pieces) list[count] = null;
        return list;
    }

    inline fn setBB(self: *Position, c: Color, p: Pieces, sq_bb: Bitboard) void {
        self.piece_bb[@intFromEnum(p)] |= sq_bb;
        self.color_bb[@intFromEnum(c)] |= sq_bb;
    }

    inline fn clearBB(self: *Position, c: Color, p: Pieces, sq_bb: Bitboard) void {
        self.piece_bb[@intFromEnum(p)] &= ~sq_bb;
        self.color_bb[@intFromEnum(c)] &= ~sq_bb;
    }

    inline fn togglePieceHashes(self: *Position, c: Color, p: Pieces, sq: Square) void {
        const key = zob.ZobristKeys.pieceKeys(c, p, sq);
        self.hash ^= key;
        switch (p) {
            .Pawn => {
                self.pawn_hash ^= key;
                self.non_pawn_hash[@intFromEnum(c)] ^= key;
            },
            .Knight, .Bishop => {
                self.non_pawn_hash[@intFromEnum(c)] ^= key;
                self.minor_hash ^= key;
            },
            .Rook, .Queen => {
                self.non_pawn_hash[@intFromEnum(c)] ^= key;
                self.major_hash ^= key;
            },
            .King => {},
            .None => unreachable,
        }
    }

    pub fn addPiece(self: *Position, c: Color, p: Pieces, sq: Square) void {
        std.debug.assert(p != .None);
        const cur = self.mailbox[sq];
        const sq_bb = getSquareBB(sq);

        if (!cur.isNone()) {
            self.togglePieceHashes(cur.color, cur.piece, sq);
            self.clearBB(cur.color, cur.piece, sq_bb);
        }

        self.setBB(c, p, sq_bb);
        self.mailbox[sq] = .{ .piece = p, .color = c };
        self.togglePieceHashes(c, p, sq);
    }

    pub fn removePiece(self: *Position, sq: Square) void {
        const cur = self.mailbox[sq];
        if (!cur.isNone()) {
            self.togglePieceHashes(cur.color, cur.piece, sq);
            self.clearBB(cur.color, cur.piece, getSquareBB(sq));
        }
        self.mailbox[sq] = Piece.none;
    }

    pub fn setCastleRights(self: *Position, c: CastleRights) void {
        self.hash ^= zob.ZobristKeys.castleKeys(self.castle);
        self.castle = c;
        self.hash ^= zob.ZobristKeys.castleKeys(c);
    }

    pub fn setEpSquare(self: *Position, ep: ?Square) void {
        self.hash ^= epKey(self.ep_sq);
        self.ep_sq = ep;
        self.hash ^= epKey(ep);
    }

    inline fn epKey(ep: ?Square) ZobristKey {
        return zob.ZobristKeys.enPassantKeys(if (ep) |s| @as(u8, s) else null);
    }

    pub fn reinitZobrist(self: *Position, to_move: Color) void {
        self.hash = 0;
        self.pawn_hash = 0;
        self.non_pawn_hash = [_]ZobristKey{0} ** num_colors;
        self.major_hash = 0;
        self.minor_hash = 0;

        self.hash ^= zob.ZobristKeys.castleKeys(self.castle);
        self.hash ^= epKey(self.ep_sq);
        self.hash ^= zob.ZobristKeys.sideKeys(to_move);

        for (self.mailbox, 0..) |pc, i| {
            if (!pc.isNone()) self.togglePieceHashes(pc.color, pc.piece, @intCast(i));
        }
    }

    pub fn isConsistent(self: *const Position) bool {
        var occ: Bitboard = 0;
        for (self.mailbox, 0..) |pc, i| {
            const sq: Square = @intCast(i);
            if (pc.isNone()) {
                if (getBit(self.getOccupancy(), sq)) return false;
                continue;
            }
            occ |= getSquareBB(sq);
            if (!getBit(self.piece_bb[@intFromEnum(pc.piece)], sq)) return false;
            if (!getBit(self.color_bb[@intFromEnum(pc.color)], sq)) return false;
        }
        if (occ != self.getOccupancy()) return false;
        if ((self.color_bb[0] & self.color_bb[1]) != 0) return false;

        var seen: Bitboard = 0;
        for (self.piece_bb) |bb| {
            if ((seen & bb) != 0) return false;
            seen |= bb;
        }
        return seen == occ;
    }

    pub fn printBoard(self: *const Position) void {
        for (0..num_ranks) |r| {
            const rank: u3 = @intCast(num_ranks - 1 - r);
            for (0..num_files) |f| {
                std.debug.print("{c}", .{self.mailbox[squareFromFileRank(@intCast(f), rank)].toChar()});
            }
            std.debug.print("\n", .{});
        }
    }
};

pub const GameState = struct {
    cur_position: Position,
    history: [max_game_moves]UndoInfo,
    ply: usize,
    to_move: Color,
    fullmove: u16,

    white_ks_rook_file: u3,
    white_qs_rook_file: u3,
    black_ks_rook_file: u3,
    black_qs_rook_file: u3,

    nnue_stack: nnue.NNUEStack,

    pub fn init() GameState {
        var gs: GameState = .{
            .cur_position = Position.init(),
            .history = undefined,
            .ply = 0,
            .to_move = .White,
            .fullmove = 1,
            .white_ks_rook_file = 7,
            .white_qs_rook_file = 0,
            .black_ks_rook_file = 7,
            .black_qs_rook_file = 0,
            .nnue_stack = nnue.NNUEStack.init(),
        };
        gs.cur_position.reinitZobrist(gs.to_move);
        return gs;
    }

    pub fn initInPlace(self: *GameState) void {
        self.cur_position = Position.init();
        self.ply = 0;
        self.to_move = .White;
        self.fullmove = 1;
        self.white_ks_rook_file = 7;
        self.white_qs_rook_file = 0;
        self.black_ks_rook_file = 7;
        self.black_qs_rook_file = 0;
        self.nnue_stack.current = 0;
        self.nnue_stack.finny.reset();
        self.cur_position.reinitZobrist(self.to_move);
    }

    pub fn copyFrom(self: *GameState, other: *const GameState) void {
        self.cur_position = other.cur_position;
        self.ply = other.ply;
        self.to_move = other.to_move;
        self.fullmove = other.fullmove;
        self.white_ks_rook_file = other.white_ks_rook_file;
        self.white_qs_rook_file = other.white_qs_rook_file;
        self.black_ks_rook_file = other.black_ks_rook_file;
        self.black_qs_rook_file = other.black_qs_rook_file;
        @memcpy(self.history[0..other.ply], other.history[0..other.ply]);
        self.nnue_stack.current = other.nnue_stack.current;
        self.nnue_stack.finny.reset();
        self.refreshNNUE();
    }

    pub inline fn halfmoveClock(self: *const GameState) u8 {
        return self.cur_position.halfmove;
    }

    pub inline fn rookSquare(self: *const GameState, color: Color, kingside: bool) Square {
        const file: u3 = if (color == .White)
            (if (kingside) self.white_ks_rook_file else self.white_qs_rook_file)
        else
            (if (kingside) self.black_ks_rook_file else self.black_qs_rook_file);
        return squareFromFileRank(file, if (color == .White) 0 else 7);
    }

    pub inline fn rookCastleDest(color: Color, kingside: bool) Square {
        return squareFromFileRank(if (kingside) 5 else 3, if (color == .White) 0 else 7);
    }

    pub inline fn kingCastleDest(color: Color, kingside: bool) Square {
        return squareFromFileRank(if (kingside) 6 else 2, if (color == .White) 0 else 7);
    }

    fn clearRookRight(self: *const GameState, cr: CastleRights, c: Color, sq: Square) CastleRights {
        if (sq == self.rookSquare(c, true)) {
            return removeCastleRights(cr, castleRight(c, true));
        } else if (sq == self.rookSquare(c, false)) {
            return removeCastleRights(cr, castleRight(c, false));
        }
        return cr;
    }

    pub fn dirtyPieces(self: *const GameState, m: Move) DirtyPieces {
        const p = &self.cur_position;
        const moved = p.movedPiece(m);
        var d = DirtyPieces{};

        if (m.isCastle()) {
            const kingside = m.isKingsideCastle();
            const rook: Piece = .{ .piece = .Rook, .color = moved.color };
            d.remove(moved, m.from);
            d.remove(rook, self.rookSquare(moved.color, kingside));
            d.add(moved, m.to);
            d.add(rook, rookCastleDest(moved.color, kingside));
            return d;
        }

        d.remove(moved, m.from);
        const captured = p.capturedPiece(m);
        if (!captured.isNone()) d.remove(captured, p.captureSquare(m));
        d.add(if (m.isPromo()) .{ .piece = m.promoPiece(), .color = moved.color } else moved, m.to);
        return d;
    }

    pub fn makeMove(self: *GameState, m: Move) void {
        std.debug.assert(self.ply < max_game_moves);
        self.nnue_stack.pushAndUpdate(self, m);

        const p = &self.cur_position;
        const us = self.to_move;
        const them = us.opposite();
        const moved = p.movedPiece(m);
        const captured = p.capturedPiece(m);
        std.debug.assert(!moved.isNone() and moved.color == us);

        self.history[self.ply] = .{
            .captured = captured,
            .castle = p.castle,
            .ep_sq = p.ep_sq,
            .halfmove = p.halfmove,
            .key = p.hash,
        };
        self.ply += 1;

        if (moved.piece == .Pawn or m.isCapture()) {
            p.halfmove = 0;
        } else {
            p.halfmove +|= 1;
        }

        var cr = p.castle;
        if (cr != 0) {
            if (moved.piece == .King) {
                cr = removeCastleRights(cr, colorCastleRights(us));
            } else if (moved.piece == .Rook) {
                cr = self.clearRookRight(cr, us, m.from);
            }
            if (captured.piece == .Rook) {
                cr = self.clearRookRight(cr, them, m.to);
            }
        }

        var new_ep: ?Square = null;

        if (m.isCastle()) {
            const kingside = m.isKingsideCastle();
            const rook_from = self.rookSquare(us, kingside);
            const rook_to = rookCastleDest(us, kingside);

            p.removePiece(m.from);
            p.removePiece(rook_from);
            p.addPiece(us, .King, m.to);
            p.addPiece(us, .Rook, rook_to);
        } else if (m.isEP()) {
            const cap_sq: Square = if (us == .White) m.to - 8 else m.to + 8;
            p.removePiece(m.from);
            p.removePiece(cap_sq);
            p.addPiece(us, .Pawn, m.to);
        } else if (m.isPromo()) {
            p.removePiece(m.from);
            p.addPiece(us, m.promoPiece(), m.to);
        } else {
            p.removePiece(m.from);
            p.addPiece(us, moved.piece, m.to);

            if (m.isDoublePP()) {
                const to_bb = getSquareBB(m.to);
                const enemy_pawns = p.getPieceColorBoard(.Pawn, them);
                if ((eastOne(to_bb) | westOne(to_bb)) & enemy_pawns != 0) {
                    new_ep = if (us == .White) m.to - 8 else m.to + 8;
                }
            }
        }

        p.setEpSquare(new_ep);
        if (cr != p.castle) p.setCastleRights(cr);
        p.hash ^= zob.ZobristKeys.sideKeys(us) ^ zob.ZobristKeys.sideKeys(them);

        self.to_move = them;
        if (us == .Black) self.fullmove += 1;
    }

    pub fn unmakeMove(self: *GameState, m: Move) void {
        self.nnue_stack.pop();

        std.debug.assert(self.ply > 0);
        self.ply -= 1;
        const them = self.to_move;
        const us = them.opposite();
        self.to_move = us;
        if (us == .Black) self.fullmove -= 1;

        const undo = self.history[self.ply];
        const p = &self.cur_position;

        if (m.isCastle()) {
            const kingside = m.isKingsideCastle();
            p.removePiece(m.to);
            p.removePiece(rookCastleDest(us, kingside));
            p.addPiece(us, .King, m.from);
            p.addPiece(us, .Rook, self.rookSquare(us, kingside));
        } else if (m.isEP()) {
            const cap_sq: Square = if (us == .White) m.to - 8 else m.to + 8;
            p.removePiece(m.to);
            p.addPiece(us, .Pawn, m.from);
            p.addPiece(them, .Pawn, cap_sq);
        } else {
            const back: Pieces = if (m.isPromo()) .Pawn else p.getPieceFromSquare(m.to);
            p.removePiece(m.to);
            p.addPiece(us, back, m.from);
            if (!undo.captured.isNone()) {
                p.addPiece(undo.captured.color, undo.captured.piece, m.to);
            }
        }

        if (p.castle != undo.castle) p.setCastleRights(undo.castle);
        p.setEpSquare(undo.ep_sq);
        p.halfmove = undo.halfmove;
        p.hash ^= zob.ZobristKeys.sideKeys(us) ^ zob.ZobristKeys.sideKeys(them);

        std.debug.assert(p.hash == undo.key);
    }

    pub fn makeNullMove(self: *GameState) void {
        std.debug.assert(self.ply < max_game_moves);
        const p = &self.cur_position;
        self.history[self.ply] = .{
            .captured = Piece.none,
            .castle = p.castle,
            .ep_sq = p.ep_sq,
            .halfmove = p.halfmove,
            .key = p.hash,
        };
        self.ply += 1;
        self.nnue_stack.push();

        const us = self.to_move;
        const them = us.opposite();
        p.setEpSquare(null);
        p.hash ^= zob.ZobristKeys.sideKeys(us) ^ zob.ZobristKeys.sideKeys(them);
        self.to_move = them;
        if (us == .Black) self.fullmove += 1;
    }

    pub fn unmakeNullMove(self: *GameState) void {
        self.nnue_stack.pop();

        std.debug.assert(self.ply > 0);
        self.ply -= 1;
        const them = self.to_move;
        const us = them.opposite();
        self.to_move = us;
        if (us == .Black) self.fullmove -= 1;

        const p = &self.cur_position;
        p.setEpSquare(self.history[self.ply].ep_sq);
        p.hash ^= zob.ZobristKeys.sideKeys(us) ^ zob.ZobristKeys.sideKeys(them);
        std.debug.assert(p.hash == self.history[self.ply].key);
    }

    pub fn isDraw(self: *const GameState, search_ply: usize) bool {
        if (self.cur_position.halfmove >= 100) return true;
        if (self.cur_position.isMaterialDraw()) return true;
        return self.isThreefoldRepetition(search_ply);
    }

    pub fn isMaterialDraw(self: *const GameState) bool {
        return self.cur_position.isMaterialDraw();
    }

    pub fn isThreefoldRepetition(self: *const GameState, search_ply: usize) bool {
        const key = self.cur_position.hash;
        const limit = @min(@as(usize, self.cur_position.halfmove), self.ply);
        var count: u32 = 0;

        var i: usize = 1;
        while (i < limit) : (i += 2) {
            if (self.history[self.ply - 1 - i].key == key) {
                count += 1;
                if (i < search_ply) return true; // within search tree: twofold is enough
                if (count >= 2) return true; // game history: need actual threefold
            }
        }
        return false;
    }

    pub fn refreshNNUE(self: *GameState) void {
        nnue.refreshAccumulator(self, self.nnue_stack.top());
    }

    pub fn evaluateNNUE(self: *GameState) i32 {
        return nnue.evaluate(&self.nnue_stack, self.to_move, self);
    }

    pub fn isConsistent(self: *const GameState) bool {
        const p = &self.cur_position;
        if (!p.isConsistent()) return false;
        var fresh = p.*;
        fresh.reinitZobrist(self.to_move);
        return fresh.hash == p.hash and fresh.pawn_hash == p.pawn_hash and
            fresh.non_pawn_hash[0] == p.non_pawn_hash[0] and
            fresh.non_pawn_hash[1] == p.non_pawn_hash[1] and
            fresh.major_hash == p.major_hash and fresh.minor_hash == p.minor_hash;
    }

    pub fn printBoard(self: *const GameState) void {
        self.cur_position.printBoard();
    }
};

// zig fmt: off
pub const Squares = enum(Square) {
    a1, b1, c1, d1, e1, f1, g1, h1,
    a2, b2, c2, d2, e2, f2, g2, h2,
    a3, b3, c3, d3, e3, f3, g3, h3,
    a4, b4, c4, d4, e4, f4, g4, h4,
    a5, b5, c5, d5, e5, f5, g5, h5,
    a6, b6, c6, d6, e6, f6, g6, h6,
    a7, b7, c7, d7, e7, f7, g7, h7,
    a8, b8, c8, d8, e8, f8, g8, h8,
};
// zig fmt: on
