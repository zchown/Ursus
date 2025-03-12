const std = @import("std");
const brd = @import("board.zig");

pub const ZobristKey = u64;

const PieceRandoms = [brd.num_colors][brd.num_pieces][brd.num_squares]ZobristKey;
const CastleRandoms = [@intFromEnum(brd.CastleRights.NumCastles) + 1]ZobristKey;
const ColorRandoms = [brd.num_colors]ZobristKey;
const EnPassantRandoms = [brd.num_squares + 1]ZobristKey;

pub const ZobristKeys: ZobristKeyStruct = ZobristKeyStruct.new();

pub const ZobristKeyStruct = struct {
    piece: PieceRandoms,
    castle: CastleRandoms,
    color: ColorRandoms,
    en_passant: EnPassantRandoms,

    pub fn new() ZobristKeyStruct {
        var keys: ZobristKeyStruct = ZobristKeyStruct{
            .piece = std.mem.zeroes(PieceRandoms),
            .castle = std.mem.zeroes(CastleRandoms),
            .color = std.mem.zeroes(ColorRandoms),
            .en_passant = std.mem.zeroes(EnPassantRandoms),
        };
        var rng = 0xdeadbeefdeadbeef;
        rng = splitMix64(rng);
        // white
        keys.color[0] = rng;
        rng = splitMix64(rng);
        // black
        keys.color[1] = rng;

        @setEvalBranchQuota(1000000);
        inline for (std.meta.fields(brd.Pieces)) |piece| {
            for (0..brd.num_squares) |square| {
                rng = splitMix64(rng);
                // white
                keys.piece[0][piece.value][square] = rng;
                rng = splitMix64(rng);
                // black
                keys.piece[1][piece.value][square] = rng;
            }
        }

        inline for (std.meta.fields(brd.CastleRights)) |castle| {
            rng = splitMix64(rng);
            keys.castle[castle.value] = rng;
        }

        for (0..brd.num_squares) |square| {
            rng = splitMix64(rng);
            keys.en_passant[square] = rng;
        }
        return keys;
    }

    pub inline fn sideKeys(self: ZobristKeyStruct, side: brd.Color) ZobristKey {
        return self.color[@intFromEnum(side)];
    }

    pub inline fn enPassantKeys(self: ZobristKeyStruct, ep: ?u8) ZobristKey {
        return self.en_passant[ep orelse brd.num_squares];
    }

    pub inline fn castleKeys(self: ZobristKeyStruct, castles: brd.CastleRights) ZobristKey {
        return self.castle[@intFromEnum(castles)];
    }

    pub inline fn pieceKeys(self: ZobristKeyStruct, color: brd.Color, piece: brd.Pieces, square: usize) ZobristKey {
        return self.piece[@intFromEnum(color)][@intFromEnum(piece)][square];
    }
};

fn splitMix64(x: u64) ZobristKey {
    var y = (x ^ (x >> 30)) *% 0xbf58476d1ce4e5b9;
    y = (y ^ (y >> 27)) *% 0x94d049bb133111eb;
    return y ^ (y >> 31);
}
