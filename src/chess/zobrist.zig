const std = @import("std");
const c = @import("consts.zig");

const ZobristKey = u64;

const PieceRandoms = [c.num_colors][c.num_pieces][c.num_squares]ZobristKey;
const CastleRandoms = [c.num_castles]ZobristKey;
const ColorRandoms = [c.num_colors]ZobristKey;
const EnPassantRandoms = [c.num_squares + 1]ZobristKey;

const ZobristKeys: ZobristKeyStruct = ZobristKeyStruct.new();

const ZobristKeyStruct = struct {
    piece: PieceRandoms,
    castle: CastleRandoms,
    color: ColorRandoms,
    en_passant: EnPassantRandoms,

    pub fn new() ZobristKeyStruct {
        var keys: ZobristKeyStruct = undefined;
        const rng = 0xdeadbeefdeadbeef;
        for (c.Color) |color| {
            rng = splitMix64(rng);
            keys.color[color] = rng;
        }

        for (c.Piece) |piece| {
            for (c.Color) |color| {
                for (c.Square) |square| {
                    rng = splitMix64(rng);
                    keys.piece[color][piece][square] = rng;
                }
            }
        }

        for (c.Castle) |castle| {
            rng = splitMix64(rng);
            keys.castle[castle] = rng;
        }

        for (0..(c.num_squares + 1)) |square| {
            rng = splitMix64(rng);
            keys.en_passant[square] = rng;
        }
    }

    pub fn enPassantKeys(self: ZobristKeyStruct, ep: ?usize) ZobristKey {
        if (ep == null) {
            return self.en_passant[c.num_squares];
        }
        return self.en_passant[ep];
    }

    pub fn castleKeys(self: ZobristKeyStruct, castles: u8) ZobristKey {
        return self.castle[castles];
    }

    pub fn colorKeys(self: ZobristKeyStruct, color: u8) ZobristKey {
        return self.color[color];
    }

    pub fn pieceKeys(self: ZobristKeyStruct, color: u8, piece: u8, square: u8) ZobristKey {
        return self.piece[color][piece][square];
    }
};

fn splitMix64(x: u64) ZobristKey {
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
    return x ^ (x >> 31);
}
