const std = @import("std");
const zob = @import("zobrist.zig");
const c = @import("consts.zig");

const Square = usize;
const Bitboard = u64;
const Castling = u8;
const bb_empty: Bitboard = 0;

const GameState = struct {
    side_to_move: c.Color,
    castling_rights: Castling,
    en_passant_square: ?u8,
    halfmove_clock: u8,
    fullmove_number: u16,
    zobrist: zob.ZobristKey,

    pub fn initZobrist(self: GameState) zob.ZobristKey {
        var zobrist: zob.ZobristKey = 0;
        zobrist ^= zob.ZobristKeys.sideToMoveKey;
        zobrist ^= zob.ZobristKeys.castlingKeys(self.castling_rights);
        zobrist ^= zob.ZobristKeys.enPassantKeys(self.en_passant_square);
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

    pub fn getPieces(self: Board, color: c.Color, piece: c.Pieces) Bitboard {
        return self.piece_bb[color][piece];
    }

    pub fn occupency(self: Board) Bitboard {
        return self.color_bb[c.Color.White] | self.color_bb[c.Color.Black];
    }

    pub fn toMove(self: Board) c.Color {
        return self.game_state.side_to_move;
    }

    pub fn justMoved(self: Board) c.Color {
        return if (self.game_state.side_to_move == c.Color.White) c.Color.Black else c.Color.White;
    }

    pub fn kingSquare(self: Board, color: c.Color) Square {
        return @ctz(self.piece_bb[color][c.Pieces.King]);
    }

    pub fn removePiece(self: Board, color: c.Color, piece: c.Pieces, square: Square) void {
        self.piece_bb[color][piece] &= !(1 << square);
        self.color_bb[color] &= !(1 << square);
        self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(color, piece, square);
    }

    pub fn addPiece(self: Board, color: c.Color, piece: c.Pieces, square: Square) void {
        self.piece_bb[color][piece] |= 1 << square;
        self.color_bb[color] |= 1 << square;
        self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(color, piece, square);
    }

    pub fn movePiece(self: Board, color: c.Color, piece: c.Pieces, from: Square, to: Square) void {
        self.removePiece(color, piece, from);
        self.addPiece(color, piece, to);
    }

    pub fn setEnPassantSquare(self: Board, square: ?u8) void {
        self.game_state.en_passant_square = square;
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);
    }

    pub fn clearEnPassantSquare(self: Board) void {
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);
        self.setEnPassantSquare(null);
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);
    }

    pub fn flipSideToMove(self: Board) void {
        self.game_state.zobrist ^= zob.ZobristKeys.sideToMoveKey;
        self.game_state.side_to_move ^= 1;
        self.game_state.zobrist ^= zob.ZobristKeys.sideToMoveKey;
    }

    pub fn updateCastlingRights(self: Board, castling: Castling) void {
        self.game_state.zobrist ^= zob.ZobristKeys.castlingKeys(self.game_state.castling_rights);
        self.game_state.castling_rights = castling;
        self.game_state.zobrist ^= zob.ZobristKeys.castlingKeys(self.game_state.castling_rights);
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
        .side_to_move = c.Color.White,
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

pub inline fn flipColor(color: c.Color) c.Color {
    return if (color == c.Color.White) c.Color.Black else c.Color.White;
}
