const std = @import("std");
const zob = @import("zobrist.zig");
const c = @import("consts.zig");

const Pieces = enum {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
};

const Color = enum {
    White,
    Black,
};

const Bitboard = u64;
const Castling = u8;
const bb_empty: Bitboard = 0;

const GameState = struct {
    side_to_move: Color,
    castling_rights: Castling,
    en_passant_square: ?u8,
    halfmove_clock: u8,
    fullmove_number: u16,
};

const History = struct {
    history_list: [c.max_game_moves]GameState,
    history_count: usize,
};

const Board = struct {
    piece_bb: [c.num_colors][c.num_pieces]Bitboard,
    color_bb: [c.num_colors]Bitboard,
    game_state: GameState,
    history: History,
    zobrist: zob.ZobristKey,
};

pub fn initBoard() Board {
    return .{
        .piece_bb = [c.num_colors][c.num_pieces]Bitboard{[_]Bitboard{bb_empty} ** c.num_pieces} ** c.num_colors,
        .color_bb = [_]Bitboard{bb_empty} ** c.num_colors,
        .game_state = initGameState(),
        .history = initHistory(),
        .zobrist = 0, // TODO: update when zobrist is implemented
    };
}

pub fn initGameState() GameState {
    return .{
        .side_to_move = Color.White,
        .castling_rights = c.castling_rights_all,
        .en_passant_square = null,
        .halfmove_clock = 0,
        .fullmove_number = 1,
    };
}

pub fn initHistory() History {
    return .{
        .history_list = undefined,
        .history_count = 0,
    };
}
