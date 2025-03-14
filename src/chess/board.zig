const std = @import("std");
const EnumArray = std.EnumArray;
const zob = @import("zobrist.zig");

pub const num_colors = 2;
pub const num_pieces = 6;
pub const num_squares = 64;
pub const num_files = 8;
pub const num_ranks = 8;
pub const max_pieces = 32;
pub const max_game_moves = 2048;

pub const CastleRights = enum(usize) {
    NoCastling = 0,
    WhiteKingside = 1,
    WhiteQueenside = 2,
    BlackKingside = 4,
    BlackQueenside = 8,
    AllCastling = 15,
    NumCastles = 16,
};

pub const Square = usize;
pub const Bitboard = u64;

pub const Pieces = enum(u3) {
    Pawn = 0,
    Knight = 1,
    Bishop = 2,
    Rook = 3,
    Queen = 4,
    King = 5,
    None = 6,
};

pub const Color = enum(u1) {
    White = 0,
    Black = 1,
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
        zobrist ^= zob.ZobristKeys.sideKeys(self.side_to_move);
        zobrist ^= zob.ZobristKeys.castleKeys(self.castling_rights);
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
    piece_bb: EnumArray(Color, EnumArray(Pieces, Bitboard)),
    color_bb: EnumArray(Color, Bitboard),
    game_state: GameState,
    history: History,

    pub fn new() Board {
        return .{
            .piece_bb = std.mem.zeroes(EnumArray(Color, EnumArray(Pieces, Bitboard))),
            .color_bb = std.mem.zeroes(EnumArray(Color, Bitboard)),
            .game_state = GameState.new(),
            .history = History.new(),
        };
    }

    // allows printing without needing to import fen
    // however fen.debuPrint is much nicer
    pub fn printBoard(self: *Board) void {
        const piece_chars: [num_colors][num_pieces]u8 = [num_colors][num_pieces]u8{
            [_]u8{ 'P', 'N', 'B', 'R', 'Q', 'K' },
            [_]u8{ 'p', 'n', 'b', 'r', 'q', 'k' },
        };

        for (0..num_ranks) |r| {
            const rank = num_ranks - r - 1;
            for (0..num_files) |file| {
                var piece_found: bool = false;
                for (0..num_colors) |color| {
                    for (0..num_pieces) |piece| {
                        if (getBit(self.piece_bb.get(color).get(piece), rank * num_files + file)) {
                            std.debug.print("{c}", .{piece_chars[color][piece]});
                            piece_found = true;
                            break;
                        }
                    }
                    if (piece_found) break;
                }
                if (!piece_found) {
                    std.debug.print(".", .{});
                }
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn getPieces(self: Board, color: Color, piece: Pieces) Bitboard {
        return self.piece_bb.get(color).get(piece);
    }

    pub fn occupancy(self: Board) Bitboard {
        return self.color_bb.get(Color.White) | self.color_bb.get(Color.Black);
    }

    pub fn toMove(self: Board) Color {
        return self.game_state.side_to_move;
    }

    pub fn justMoved(self: Board) Color {
        return if (self.game_state.side_to_move == Color.White) Color.Black else Color.White;
    }

    pub fn kingSquare(self: Board, color: Color) Square {
        return @ctz(self.piece_bb[@intFromEnum(color)][Pieces.King]);
    }

    pub fn removePiece(self: *Board, color: Color, piece: Pieces, square: Square) void {
        self.piece_bb.get(color).set(piece, self.piece_bb.get(color).get(piece) & !(1 << square));
        self.color_bb.getPtr(color).* &= !getSquareBB(square);
        self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(color, piece, square);
    }

    pub fn addPiece(self: *Board, color: Color, piece: Pieces, square: Square) void {
        self.piece_bb.getPtr(color).set(piece, self.piece_bb.get(color).get(piece) | getSquareBB(square));
        self.color_bb.getPtr(color).* |= getSquareBB(square);
        const newkey = zob.ZobristKeys.pieceKeys(color, piece, square);
        self.game_state.zobrist ^= newkey;
    }

    pub fn movePiece(self: *Board, color: Color, piece: Pieces, from: Square, to: Square) void {
        self.removePiece(color, piece, from);
        self.addPiece(color, piece, to);
    }

    pub fn setEnPassantSquare(self: *Board, square: ?u8) void {
        self.game_state.en_passant_square = square;
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);
    }

    pub fn clearEnPassantSquare(self: *Board) void {
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);
        self.setEnPassantSquare(null);
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);
    }

    pub fn flipSideToMove(self: *Board) void {
        self.game_state.zobrist ^= zob.ZobristKeys.sideKeys(self.game_state.side_to_move);
        self.game_state.side_to_move ^= 1;
        self.game_state.zobrist ^= zob.ZobristKeys.sideKeys(self.game_state.side_to_move);
    }

    pub fn updateCastlingRights(self: *Board, castling: CastleRights) void {
        self.game_state.zobrist ^= zob.ZobristKeys.castleKeys(self.game_state.castling_rights);
        self.game_state.castling_rights = castling;
        self.game_state.zobrist ^= zob.ZobristKeys.castleKeys(self.game_state.castling_rights);
    }

    pub fn copyBoard(self: Board) Board {
        return .{
            .piece_bb = self.piece_bb,
            .color_bb = self.color_bb,
            .game_state = self.game_state,
            .history = self.history,
        };
    }

    // this is not a very zig way to do this
    // TODO: update to sentinel array
    pub fn getPieceList(self: Board) [max_pieces]?Piece {
        var list: [max_pieces]?Piece = undefined;
        var count: usize = 0;

        for (std.meta.tags(Color)) |color| {
            for (std.meta.tags(Pieces)) |piece| {
                var bb: Bitboard = self.piece_bb.get(color).get(piece);
                while (bb != 0) {
                    const sq = getLSB(bb);
                    list[count] = Piece{
                        .color = color,
                        .piece = piece,
                        .square = sq,
                    };
                    count += 1;
                    bb &= bb - 1;
                }
            }
        }

        if (count < max_pieces) {
            list[count] = null;
        }
        return list;
    }

    pub fn reinitZobrist(self: *Board) void {
        self.game_state.zobrist ^= zob.ZobristKeys.sideKeys(self.game_state.side_to_move);
        self.game_state.zobrist ^= zob.ZobristKeys.castleKeys(self.game_state.castling_rights);
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);

        var i: usize = 0;
        const piece_list: [max_pieces]?Piece = self.getPieceList();
        while (i < max_pieces and piece_list[i] != null) {
            const piece: Piece = piece_list[i] orelse unreachable;
            self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(piece.color, piece.piece, piece.square);
            i += 1;
        }
    }

    pub fn printBitBoards(self: Board) void {
        for (std.meta.tags(Color)) |color| {
            for (std.meta.tags(Pieces)) |piece| {
                std.debug.print("Color: {d}\n", .{color});
                std.debug.print("Piece: {d}\n", .{piece});
                printBitboard(self.piece_bb.get(color).get(piece));
            }
        }
    }
};

pub inline fn flipColor(color: Color) Color {
    return if (color == Color.White) Color.Black else Color.White;
}

pub inline fn getSquareBB(square: Square) Bitboard {
    return @as(u64, 1) << @intCast(square);
}

pub inline fn countBits(bb: Bitboard) u32 {
    return @popCount(bb);
}

pub inline fn getLSB(bb: Bitboard) u32 {
    return @ctz(bb);
}

pub inline fn getBit(bb: Bitboard, square: Square) bool {
    return (bb & getSquareBB(square)) != 0;
}

pub inline fn clearBit(bb: *Bitboard, square: Square) void {
    bb.* &= !(1 << square);
}

pub inline fn setBit(bb: *Bitboard, square: Square) void {
    bb.* |= (1 << square);
}

pub inline fn popBit(bb: *Bitboard, sq: Square) void {
    if (getBit(bb.*, sq)) {
        bb.* ^= getSquareBB(sq);
    }
}

pub fn bitboardToArray(bb: Bitboard) [64]bool {
    var arr: [64]bool = undefined;
    for (0..64) |i| {
        arr[i] = getBit(bb, i);
    }
    return arr;
}

pub fn printBitboard(bb: Bitboard) void {
    const arr: [64]bool = bitboardToArray(bb);
    for (0..8) |r| {
        for (0..8) |f| {
            const i: usize = r * 8 + f;
            if (arr[i]) {
                std.debug.print("1", .{});
            } else {
                std.debug.print("0", .{});
            }
        }
        std.debug.print("\n", .{});
    }
}

