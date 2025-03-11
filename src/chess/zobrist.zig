const std = @import("std");
const brd = @import("board.zig");

pub const ZobristKey = u64;

const PieceRandoms = [brd.num_colors][brd.num_pieces][brd.num_squares]ZobristKey;
const CastleRandoms = [brd.num_castles]ZobristKey;
const ColorRandoms = [brd.num_colors]ZobristKey;
const EnPassantRandoms = [brd.num_squares + 1]ZobristKey;

pub const ZobristKeys: ZobristKeyStruct = ZobristKeyStruct.new();

pub const ZobristKeyStruct = struct {
    piece: PieceRandoms,
    castle: CastleRandoms,
    color: ColorRandoms,
    en_passant: EnPassantRandoms,

    pub fn new() ZobristKeyStruct {
        var keys: ZobristKeyStruct = undefined;
        const rng = 0xdeadbeefdeadbeef;
        for (brd.Color) |color| {
            rng = splitMix64(rng);
            keys.color[color] = rng;
        }

        for (brd.Piece) |piece| {
            for (brd.Square) |square| {
                rng = splitMix64(rng);
                keys.piece[brd.Color.White][piece][square] = rng;
                rng = splitMix64(rng);
                keys.piece[brd.Color.Black][piece][square] = rng;
            }
        }

        for (brd.Castle) |castle| {
            rng = splitMix64(rng);
            keys.castle[castle] = rng;
        }

        for (0..(brd.num_squares + 1)) |square| {
            rng = splitMix64(rng);
            keys.en_passant[square] = rng;
        }
    }

    pub inline fn enPassantKeys(self: ZobristKeyStruct, ep: ?usize) ZobristKey {
        if (ep == null) {
            return self.en_passant[brd.num_squares];
        }
        return self.en_passant[ep];
    }

    pub inline fn castleKeys(self: ZobristKeyStruct, castles: u8) ZobristKey {
        return self.castle[castles];
    }

    pub inline fn colorKeys(self: ZobristKeyStruct, color: u8) ZobristKey {
        return self.color[color];
    }

    pub inline fn pieceKeys(self: ZobristKeyStruct, color: u8, piece: u8, square: u8) ZobristKey {
        return self.piece[color][piece][square];
    }
};

fn splitMix64(x: u64) ZobristKey {
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
    return x ^ (x >> 31);
}
