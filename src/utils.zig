const std = @import("std");
const root = @import("root.zig");
const utils = root.utils;
const zob = root.zob;

pub const num_colors = 2;
pub const num_pieces = 6;
pub const num_squares = 64;
pub const num_files = 8;
pub const num_ranks = 8;
pub const max_pieces = 32;
pub const max_game_moves = 2048;

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

