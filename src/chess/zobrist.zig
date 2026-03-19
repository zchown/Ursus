const std = @import("std");
const brd = @import("board");
pub const ZobristKey = u64;

const PieceRandoms = [brd.num_colors][brd.num_pieces + 1][brd.num_squares]ZobristKey;
const CastleRandoms = [16]ZobristKey;
const ColorRandoms = [brd.num_colors]ZobristKey;
const EnPassantRandoms = [brd.num_squares + 1]ZobristKey;
const EvalPhaseRandoms = [24]ZobristKey;

pub const ZobristKeys: ZobristKeyStruct = ZobristKeyStruct.init();

pub const ZobristKeyStruct = struct {
    piece: PieceRandoms,
    castle: CastleRandoms,
    color: ColorRandoms,
    en_passant: EnPassantRandoms,
    eval_phase: EvalPhaseRandoms,

    pub fn init() ZobristKeyStruct {
        var keys: ZobristKeyStruct = ZobristKeyStruct{
            .piece = undefined,
            .castle = undefined,
            .color = undefined,
            .en_passant = @splat(0),
            .eval_phase = @splat(0),
        };
        var rng_state: u64 = 0xdeadbeefdeadbeef;
        
        // white
        keys.color[0] = nextSplitMix64(&rng_state);
        // black
        keys.color[1] = nextSplitMix64(&rng_state);

        @setEvalBranchQuota(1000000);
        inline for (std.meta.tags(brd.Pieces)) |piece| {
            for (0..brd.num_squares) |square| {
                // white
                keys.piece[0][@intFromEnum(piece)][square] = nextSplitMix64(&rng_state);
                // black
                keys.piece[1][@intFromEnum(piece)][square] = nextSplitMix64(&rng_state);
            }
        }

        inline for (0..16) |castle| {
            keys.castle[castle] = nextSplitMix64(&rng_state);
        }

        inline for (0..brd.num_squares + 1) |square| {
            keys.en_passant[square] = nextSplitMix64(&rng_state);
        }

        inline for (0..24) |phase| {
            keys.eval_phase[phase] = nextSplitMix64(&rng_state);
        }

        return keys;
    }

    pub inline fn sideKeys(self: ZobristKeyStruct, side: brd.Color) ZobristKey {
        return self.color[@intFromEnum(side)];
    }

    pub inline fn enPassantKeys(self: ZobristKeyStruct, ep: ?u8) ZobristKey {
        return self.en_passant[ep orelse brd.num_squares];
    }

    pub inline fn castleKeys(self: ZobristKeyStruct, castles: u4) ZobristKey {
        return self.castle[@intCast(castles)];
    }

    pub inline fn pieceKeys(self: ZobristKeyStruct, color: brd.Color, piece: brd.Pieces, square: usize) ZobristKey {
        return self.piece[@intFromEnum(color)][@intFromEnum(piece)][square];
    }
};

fn nextSplitMix64(state: *u64) ZobristKey {
    state.* +%= 0x9e3779b97f4a7c15;
    var z = state.*;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}
