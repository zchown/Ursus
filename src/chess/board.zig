const std = @import("std");
const zob = @import("zobrist.zig");

pub const num_colors = 2;
pub const num_pieces = 6;
pub const num_squares = 64;
pub const num_files = 8;
pub const num_ranks = 8;
pub const max_pieces = 32;

// Castling rights
pub const CastleRights = enum(usize) {
    WhiteKingside = 1,
    WhiteQueenside = 2,
    BlackKingside = 4,
    BlackQueenside = 8,
    AllCastling = 15,
    NumCastles = 16,
};

// Move constants
pub const max_game_moves = 2048;
pub const max_legal_moves = 255;
pub const max_move_rule = 100;

// Bitboard constants
pub const bb_all = 0xFFFFFFFFFFFFFFFF;
pub const bb_file_a = 0x0101010101010101;
pub const bb_file_h = 0x8080808080808080;
pub const bb_rank_1 = 0x00000000000000FF;
pub const bb_rank_8 = 0xFF00000000000000;
pub const bb_diag_a1h8 = 0x8040201008040201;
pub const bb_diag_h1a8 = 0x0102040810204080;

pub const Square = usize;
pub const Bitboard = u64;

pub const bb_empty: Bitboard = 0;

fn init_bb_squares() [num_squares]Bitboard {
    var squares: [num_squares]Bitboard = undefined;
    for (0..num_squares) |i| {
        squares[i] = 1 << i;
    }
    return squares;
}

pub const bb_squares = init_bb_squares();

pub const Pieces = enum(u3) {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
};

pub const Color = enum(u1) {
    White,
    Black,
};

pub const Piece = struct {
    color: Color,
    piece: Pieces,
    square: Square,
};

pub const GameState = struct {
    side_to_move: Color,
    castling_rights: CastleRights,
    en_passant_square: ?u8,
    halfmove_clock: u8,
    fullmove_number: u16,
    zobrist: zob.ZobristKey,

    pub fn new() GameState {
        return .{
            .side_to_move = Color.White,
            .castling_rights = CastleRights.AllCastling,
            .en_passant_square = null,
            .halfmove_clock = 0,
            .fullmove_number = 1,
            .zobrist = 0,
        };
    }

    pub fn initZobrist(self: GameState) zob.ZobristKey {
        var zobrist: zob.ZobristKey = 0;
        zobrist ^= zob.ZobristKeys.sideToMoveKey;
        zobrist ^= zob.ZobristKeys.castlingKeys(self.castling_rights);
        zobrist ^= zob.ZobristKeys.enPassantKeys(self.en_passant_square);
        return zobrist;
    }
};

pub const History = struct {
    history_list: [max_game_moves]GameState,
    history_count: usize,

    pub fn new() History {
        return .{
            .history_list = undefined,
            .history_count = 0,
        };
    }
};

pub const Board = struct {
    piece_bb: [num_colors][num_pieces]Bitboard,
    color_bb: [num_colors]Bitboard,
    game_state: GameState,
    history: History,

    pub fn new() Board {
        return .{
            .piece_bb = [num_colors][num_pieces]Bitboard{[_]Bitboard{bb_empty} ** num_pieces} ** num_colors,
            .color_bb = [_]Bitboard{bb_empty} ** num_colors,
            .game_state = GameState.new(),
            .history = History.new(),
        };
    }

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
        self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(color, piece, square);
    }

    pub fn addPiece(self: Board, color: Color, piece: Pieces, square: Square) void {
        self.piece_bb[color][piece] |= 1 << square;
        self.color_bb[color] |= 1 << square;
        self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(color, piece, square);
    }

    pub fn movePiece(self: Board, color: Color, piece: Pieces, from: Square, to: Square) void {
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

    pub fn updateCastlingRights(self: Board, castling: CastleRights) void {
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

    pub fn getPieceList(self: Board) [max_pieces]Piece {
        var piece_list: [max_pieces]?Piece = null ** max_pieces;
        var piece_count: usize = 0;
        for (0..num_colors) |color| {
            for (0..num_pieces) |piece| {
                var piece_bb: Bitboard = self.piece_bb[color][piece];
                while (piece_bb != 0) {
                    const square: Square = @ctz(piece_bb);
                    piece_list[piece_count] = .{
                        .color = color,
                        .piece = piece,
                        .square = square,
                    };
                    piece_count += 1;
                    piece_bb &= piece_bb - 1;
                }
            }
        }
        return piece_list;
    }

    pub fn reinitZobrist(self: Board) void {
        self.game_state.zobrist ^= zob.ZobristKeys.sideToMoveKey;
        self.game_state.zobrist ^= zob.ZobristKeys.castlingKeys(self.game_state.castling_rights);
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);

        var i: usize = 0;
        const piece_list: [max_pieces]Piece = self.getPieceList();
        while (piece_list[i] != null) {
            const piece: Piece = piece_list[i];
            self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(piece.color, piece.piece, piece.square);
            i += 1;
        }
    }
};

pub inline fn flipColor(color: Color) Color {
    return if (color == Color.White) Color.Black else Color.White;
}

pub inline fn countBits(bb: Bitboard) u32 {
    return @popCount(bb);
}

pub inline fn getLSB(bb: Bitboard) u32 {
    return @ctz(bb);
}

pub inline fn getBit(bb: Bitboard, square: Square) bool {
    return (bb & (1 << square)) != 0;
}

pub inline fn clearBit(bb: *Bitboard, square: Square) void {
    bb.* &= !(1 << square);
}

pub inline fn setBit(bb: *Bitboard, square: Square) void {
    bb.* |= (1 << square);
}

pub inline fn popBit(bb: *Bitboard, sq: Square) void {
    if (getBit(bb.*, sq)) {
        bb.* ^= 1 << sq;
    }
}

pub fn bitboardToArray(bb: Bitboard) [64]bool {
    var arr: [64]bool = undefined;
    for (0..64) |i| {
        arr[i] = getBit(bb, i);
    }
    return arr;
}
