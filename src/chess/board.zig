const std = @import("std");
const zob = @import("zobrist.zig");
const c = @import("consts.zig");

const Pieces = enum(usize) {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
};

const Color = enum(usize) {
    White,
    Black,
};

const Square = usize;
const Bitboard = u64;
const Castling = u8;
const bb_empty: Bitboard = 0;

const GameState = struct {
    side_to_move: Color,
    castling_rights: Castling,
    en_passant_square: ?u8,
    halfmove_clock: u8,
    fullmove_number: u16,
    zobrist: zob.ZobristKey,

    pub fn initZobrist(self: GameState) zob.ZobristKey {
        var zobrist: zob.ZobristKey = 0;
        zobrist ^= zob.sideToMoveKey;
        zobrist ^= zob.castlingKeys[self.castling_rights];
        zobrist ^= zob.enPassantKeys(self.en_passant_square);
        return zobrist;
    }
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

    pub fn getPieces(self: Board, color: Color, piece: Pieces) Bitboard {
        return self.piece_bb[color][piece];
    }

    pub fn occupency(self: Board) Bitboard {
        return self.color_bb[Color.White] | self.color_bb[Color.Black];
    }

    pub fn toMove(self: Board) Color {
        return self.game_state.side_to_move;
    }

    pub fn justMoved(self: Board) Color {
        return if (self.game_state.side_to_move == Color.White) Color.Black else Color.White;
    }

    pub fn kingSquare(self: Board, color: Color) Square {
        return @ctz(self.piece_bb[color][Pieces.King]);
    }

    pub fn removePiece(self: Board, color: Color, piece: Pieces, square: Square) void {
        self.piece_bb[color][piece] &= !(1 << square);
        self.color_bb[color] &= !(1 << square);
        self.game_state.zobrist ^= zob.pieceKeys[color][piece][square];
    }

    pub fn addPiece(self: Board, color: Color, piece: Pieces, square: Square) void {
        self.piece_bb[color][piece] |= 1 << square;
        self.color_bb[color] |= 1 << square;
        self.game_state.zobrist ^= zob.pieceKeys[color][piece][square];
    }

    pub fn movePiece(self: Board, color: Color, piece: Pieces, from: Square, to: Square) void {
        self.removePiece(color, piece, from);
        self.addPiece(color, piece, to);
    }

    pub fn setEnPassantSquare(self: Board, square: ?u8) void {
        self.game_state.en_passant_square = square;
        self.game_state.zobrist ^= zob.enPassantKeys[self.game_state.en_passant_square];
    }

    pub fn clearEnPassantSquare(self: Board) void {
        self.game_state.zobrist ^= zob.enPassantKeys(self.game_state.en_passant_square);
        self.setEnPassantSquare(null);
        self.game_state.zobrist ^= zob.enPassantKeys(self.game_state.en_passant_square);
    }

    pub fn flipSideToMove(self: Board) void {
        self.game_state.zobrist ^= zob.sideToMoveKey;
        self.game_state.side_to_move ^= 1;
        self.game_state.zobrist ^= zob.sideToMoveKey;
    }

    pub fn updateCastlingRights(self: Board, castling: Castling) void {
        self.game_state.zobrist ^= zob.castlingKeys[self.game_state.castling_rights];
        self.game_state.castling_rights = castling;
        self.game_state.zobrist ^= zob.castlingKeys[self.game_state.castling_rights];
    }

    pub fn copyBoard(self: Board) Board {
        return .{
            .piece_bb = self.piece_bb,
            .color_bb = self.color_bb,
            .game_state = self.game_state,
            .history = self.history,
        };
    }
};

pub fn initBoard() Board {
    return .{
        .piece_bb = [c.num_colors][c.num_pieces]Bitboard{[_]Bitboard{bb_empty} ** c.num_pieces} ** c.num_colors,
        .color_bb = [_]Bitboard{bb_empty} ** c.num_colors,
        .game_state = initGameState(),
        .history = initHistory(),
    };
}

pub fn initGameState() GameState {
    var gs: GameState = .{
        .side_to_move = Color.White,
        .castling_rights = c.castling_rights_all,
        .en_passant_square = null,
        .halfmove_clock = 0,
        .fullmove_number = 1,
        .zobrist = 0,
    };
    gs.initZobrist();
    return gs;
}

pub fn initHistory() History {
    return .{
        .history_list = undefined,
        .history_count = 0,
    };
}

pub inline fn flipColor(color: Color) Color {
    return if (color == Color.White) Color.Black else Color.White;
}
