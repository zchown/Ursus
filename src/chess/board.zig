const std = @import("std");
const zob = @import("zobrist");
const nnue = @import("nnue");
const EncodedMove = @import("moves").EncodedMove;

pub const num_colors = 2;
pub const num_pieces = 6;
pub const num_squares = 64;
pub const num_files = 8;
pub const num_ranks = 8;
pub const max_pieces = 32;
pub const max_game_moves = 1021;

pub const CastleRights = enum(u4) {
    NoCastling = 0,
    WhiteKingside = 1,
    WhiteQueenside = 2,
    BlackKingside = 4,
    BlackQueenside = 8,
    AllCastling = 15,
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

    pub fn opposite(self: Color) Color {
        return if (self == Color.White) Color.Black else Color.White;
    }

};

pub const Piece = struct {
    color: Color,
    piece: Pieces,
    square: Square,
};

pub const GameState = struct {
    side_to_move: Color,
    castling_rights: u4,
    en_passant_square: ?u8,
    halfmove_clock: u8,
    fullmove_number: u16,
    zobrist: zob.ZobristKey,
    pawn_hash: zob.ZobristKey,
    white_np_hash: zob.ZobristKey,
    black_np_hash: zob.ZobristKey,
    major_hash: zob.ZobristKey,
    minor_hash: zob.ZobristKey,

    pub fn init() GameState {
        var toReturn = GameState{
            .side_to_move = Color.White,
            .castling_rights = @intFromEnum(CastleRights.AllCastling),
            .en_passant_square = null,
            .halfmove_clock = 0,
            .fullmove_number = 1,
            .zobrist = 0,
            .pawn_hash = 0,
            .white_np_hash = 0,
            .black_np_hash = 0,
            .major_hash = 0,
            .minor_hash = 0,
        };
        toReturn.zobrist = toReturn.initZobrist();
        return toReturn;
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

    pub fn init() History {
        return .{
            .history_list = std.mem.zeroes([max_game_moves]GameState),
            .history_count = 0,
        };
    }

    pub inline fn addToHistory(self: *History, state: GameState) void {
        self.history_list[self.history_count] = state;
        self.history_count += 1;
    }

};

pub const Board = struct {
    piece_bb: [num_colors][num_pieces]Bitboard,
    color_bb: [num_colors]Bitboard,
    game_state: GameState,
    history: History,
    nnue_stack: nnue.NNUEStack,

    pub fn init() Board {
        return .{
            .piece_bb = std.mem.zeroes([num_colors][num_pieces]Bitboard),
            .color_bb = std.mem.zeroes([num_colors]Bitboard),
            .game_state = GameState.init(),
            .history = History.init(),
            .nnue_stack = nnue.NNUEStack.init(),
        };
    }

    pub fn printBoard(self: *Board) void {
        const piece_chars: [num_colors][num_pieces]u8 = [num_colors][num_pieces]u8{
            [_]u8{ 'P', 'N', 'B', 'R', 'Q', 'K' },
            [_]u8{ 'p', 'n', 'b', 'r', 'q', 'k' },
        };

        for (0..num_ranks) |r| {
            const rank = num_ranks - r - 1;
            for (0..num_files) |file| {
                const square = rank * num_files + file;
                var found = false;
                for (std.meta.tags(Color)) |color| {
                    const color_idx = @intFromEnum(color);
                    for (std.meta.tags(Pieces)) |piece| {
                        const piece_idx = @intFromEnum(piece);
                        if (self.piece_bb[color_idx][piece_idx] & (@as(Bitboard, 1) << @intCast(square)) != 0) {
                            std.debug.print("{c}", .{piece_chars[color_idx][piece_idx]});
                            found = true;
                            break;
                        }
                    }
                    if (found) break;
                }
                if (!found) {
                    std.debug.print(".", .{});
                }
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn makeNullMove(self: *Board) void {
        self.history.addToHistory(self.game_state);
        self.nnue_stack.push();
        self.clearEnPassantSquare();
        self.flipSideToMove();
        self.game_state.halfmove_clock += 1;
        if (self.game_state.side_to_move == Color.Black) {
            self.game_state.fullmove_number += 1;
        }
    }

    pub fn unmakeNullMove(self: *Board) void {
        self.nnue_stack.pop();
        if (self.history.history_count > 0) {
            self.history.history_count -= 1;
            self.game_state = self.history.history_list[self.history.history_count];
        }
    }
    
    pub fn getPieces(self: *const Board, color: Color, piece: Pieces) Bitboard {
        return self.piece_bb[@intFromEnum(color)][@intFromEnum(piece)];
    }

    pub inline fn occupancy(self: *const Board) Bitboard {
        return self.color_bb[@intFromEnum(Color.White)] | self.color_bb[@intFromEnum(Color.Black)];
    }

    pub inline fn toMove(self: *const Board) Color {
        return self.game_state.side_to_move;
    }

    pub inline fn justMoved(self: *const Board) Color {
        return if (self.game_state.side_to_move == Color.White) Color.Black else Color.White;
    }

    pub inline fn kingSquare(self: *const Board, color: Color) Square {
        return @ctz(self.piece_bb[@intFromEnum(color)][@intFromEnum(Pieces.King)]);
    }

    pub inline fn removePiece(self: *Board, color: Color, piece: Pieces, square: Square) void {
        const color_idx = @intFromEnum(color);
        const piece_idx = @intFromEnum(piece);
        const mask = ~(@as(Bitboard, 1) << @intCast(square));
        self.piece_bb[color_idx][piece_idx] &= mask;
        self.color_bb[color_idx] &= mask;
        self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(color, piece, square);

        if (piece == Pieces.Pawn) {
            self.game_state.pawn_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
        }
        if (piece != Pieces.King) {
            if (color == Color.White) {
                self.game_state.white_np_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
            }
            else {
                self.game_state.black_np_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
            }

            if (piece == Pieces.Rook or piece == Pieces.Queen) {
                self.game_state.major_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
            }
            if (piece == Pieces.Bishop or piece == Pieces.Knight) {
                self.game_state.minor_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
            }

        }
    }

    pub inline fn addPiece(self: *Board, color: Color, piece: Pieces, square: Square) void {
        const color_idx = @intFromEnum(color);
        const piece_idx = @intFromEnum(piece);
        const mask = @as(Bitboard, 1) << @intCast(square);
        self.piece_bb[color_idx][piece_idx] |= mask;
        self.color_bb[color_idx] |= mask;
        self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(color, piece, square);

        if (piece == Pieces.Pawn) {
            self.game_state.pawn_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
        }
        if (piece != Pieces.King) {
            if (color == Color.White) {
                self.game_state.white_np_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
            }
            else {
                self.game_state.black_np_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
            }

            if (piece == Pieces.Rook or piece == Pieces.Queen) {
                self.game_state.major_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
            }
            if (piece == Pieces.Bishop or piece == Pieces.Knight) {
                self.game_state.minor_hash ^= zob.ZobristKeys.pieceKeys(color, piece, square);
            }

        }
    }

    pub inline fn movePiece(self: *Board, color: Color, piece: Pieces, from: Square, to: Square) void {
        self.removePiece(color, piece, from);
        self.addPiece(color, piece, to);
    }

    pub inline fn setEnPassantSquare(self: *Board, square: ?u8) void {
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);
        self.game_state.en_passant_square = square;
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);
    }

    pub inline fn clearEnPassantSquare(self: *Board) void {
        self.setEnPassantSquare(null);
    }

    pub inline fn flipSideToMove(self: *Board) void {
        self.game_state.zobrist ^= zob.ZobristKeys.sideKeys(self.game_state.side_to_move);
        self.game_state.side_to_move = if (self.game_state.side_to_move == Color.White) Color.Black else Color.White;
        self.game_state.zobrist ^= zob.ZobristKeys.sideKeys(self.game_state.side_to_move);
    }

    pub inline fn addCastlingRights(self: *Board, castling: CastleRights) void {
        self.game_state.zobrist ^= zob.ZobristKeys.castleKeys(self.game_state.castling_rights);
        self.game_state.castling_rights |= @intFromEnum(castling);
        self.game_state.zobrist ^= zob.ZobristKeys.castleKeys(self.game_state.castling_rights);
    }

    pub inline fn removeCastlingRights(self: *Board, castling: CastleRights) void {
        self.game_state.zobrist ^= zob.ZobristKeys.castleKeys(self.game_state.castling_rights);
        self.game_state.castling_rights &= ~@intFromEnum(castling);
        self.game_state.zobrist ^= zob.ZobristKeys.castleKeys(self.game_state.castling_rights);
    }

    pub fn copyBoard(self: *Board) Board {
        return .{
            .piece_bb = self.piece_bb,
            .color_bb = self.color_bb,
            .game_state = self.game_state,
            .history = self.history,
            .nnue_stack = self.nnue_stack,
        };
    }

    // pub fn copyFrom(self: *Board, other: *Board) void {
    //     self.piece_bb = other.piece_bb;
    //     self.color_bb = other.color_bb;
    //     self.game_state = other.game_state;
    //     self.history = other.history;
    //     self.nnue_stack = other.nnue_stack;
    // }
    pub fn copyFrom(self: *Board, other: *Board) void {
        const dest = std.mem.asBytes(self);
        const src = std.mem.asBytes(other);
        @memcpy(dest, src);
    }

    pub fn getPieceList(self: *const Board) [max_pieces]?Piece {
        var list: [max_pieces]?Piece = undefined;
        var count: usize = 0;

        for (std.meta.tags(Color)) |color| {
            const color_idx = @intFromEnum(color);
            for (std.meta.tags(Pieces)) |piece| {
                if (piece == Pieces.None) continue;
                const piece_idx = @intFromEnum(piece);
                var bb: Bitboard = self.piece_bb[color_idx][piece_idx];
                while (bb != 0) {
                    const sq = @ctz(bb);
                    list[count] = .{
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

    pub fn getPieceFromSquare(self: *const Board, square: Square) ?Pieces {
        for (std.meta.tags(Color)) |color| {
            const color_idx = @intFromEnum(color);
            for (std.meta.tags(Pieces)) |piece| {
                if (piece == Pieces.None) continue;
                const piece_idx = @intFromEnum(piece);
                if ((self.piece_bb[color_idx][piece_idx] & (@as(Bitboard, 1) << @intCast(square))) != 0) {
                    return piece;
                }
            }
        }
        return null;
    }

    pub fn getColorFromSquare(self: *const Board, square: Square) ?Color {
        for (std.meta.tags(Color)) |color| {
            const color_idx = @intFromEnum(color);
            for (std.meta.tags(Pieces)) |piece| {
                if (piece == Pieces.None) continue;
                const piece_idx = @intFromEnum(piece);
                if ((self.piece_bb[color_idx][piece_idx] & (@as(Bitboard, 1) << @intCast(square))) != 0) {
                    return color;
                }
            }
        }
        return null;
    }

    pub fn reinitZobrist(self: *Board) void {
        self.game_state.zobrist = 0;
        self.game_state.pawn_hash = 0;
        self.game_state.white_np_hash = 0;
        self.game_state.black_np_hash = 0;
        self.game_state.major_hash = 0;
        self.game_state.minor_hash = 0;
        self.game_state.zobrist ^= zob.ZobristKeys.sideKeys(self.game_state.side_to_move);
        self.game_state.zobrist ^= zob.ZobristKeys.castleKeys(self.game_state.castling_rights);
        self.game_state.zobrist ^= zob.ZobristKeys.enPassantKeys(self.game_state.en_passant_square);

        var i: usize = 0;
        const piece_list = self.getPieceList();
        while (i < max_pieces and piece_list[i] != null) : (i += 1) {
            const piece = piece_list[i].?;
            self.game_state.zobrist ^= zob.ZobristKeys.pieceKeys(piece.color, piece.piece, piece.square);

            if (piece.piece == Pieces.Pawn) {
                self.game_state.pawn_hash ^= zob.ZobristKeys.pieceKeys(piece.color, piece.piece, piece.square);
            }
            if (piece.piece != Pieces.King) {
                if (piece.color == Color.White) {
                    self.game_state.white_np_hash ^= zob.ZobristKeys.pieceKeys(piece.color, piece.piece, piece.square);
                }
                else {
                    self.game_state.black_np_hash ^= zob.ZobristKeys.pieceKeys(piece.color, piece.piece, piece.square);
                }

                if (piece.piece == Pieces.Rook or piece.piece == Pieces.Queen) {
                    self.game_state.major_hash ^= zob.ZobristKeys.pieceKeys(piece.color, piece.piece, piece.square);
                }
                if (piece.piece == Pieces.Bishop or piece.piece == Pieces.Knight) {
                    self.game_state.minor_hash ^= zob.ZobristKeys.pieceKeys(piece.color, piece.piece, piece.square);
                }

            }
        }
    }

    pub fn hasNonPawnMaterial(self: *const Board, color: Color) bool {
        const color_idx = @intFromEnum(color);
        const non_pawn_bb = self.piece_bb[color_idx][@intFromEnum(Pieces.Knight)] |
                           self.piece_bb[color_idx][@intFromEnum(Pieces.Bishop)] |
                           self.piece_bb[color_idx][@intFromEnum(Pieces.Rook)] |
                           self.piece_bb[color_idx][@intFromEnum(Pieces.Queen)];
        return non_pawn_bb != 0;
    }

    pub fn refreshNNUE(self: *Board) void {
        nnue.refreshAccumulator(self, self.nnue_stack.top());
    }

    pub fn evaluateNNUE(self: *Board) i32 {
        return nnue.evaluate(&self.nnue_stack, self.game_state.side_to_move, self);
    }

    pub fn isDraw(self: *Board, ply: usize) bool {
        if (self.game_state.halfmove_clock >= 100) {
            return true;
        }
        if (isMaterialDraw(self)) {
            return true;
        }
        if (isThreefoldRepetition(self, ply)) {
            return true;
        }
        return false;
    }

    pub fn isMaterialDraw(self: *Board) bool {
        const white_pawns = @popCount(self.piece_bb[@intFromEnum(Color.White)][@intFromEnum(Pieces.Pawn)]);
        const black_pawns = @popCount(self.piece_bb[@intFromEnum(Color.Black)][@intFromEnum(Pieces.Pawn)]);

        const white_knights = @popCount(self.piece_bb[@intFromEnum(Color.White)][@intFromEnum(Pieces.Knight)]);
        const black_knights = @popCount(self.piece_bb[@intFromEnum(Color.Black)][@intFromEnum(Pieces.Knight)]);

        const white_bishops = @popCount(self.piece_bb[@intFromEnum(Color.White)][@intFromEnum(Pieces.Bishop)]);
        const black_bishops = @popCount(self.piece_bb[@intFromEnum(Color.Black)][@intFromEnum(Pieces.Bishop)]);

        const white_rooks = @popCount(self.piece_bb[@intFromEnum(Color.White)][@intFromEnum(Pieces.Rook)]);
        const black_rooks = @popCount(self.piece_bb[@intFromEnum(Color.Black)][@intFromEnum(Pieces.Rook)]);

        const white_queens = @popCount(self.piece_bb[@intFromEnum(Color.White)][@intFromEnum(Pieces.Queen)]);
        const black_queens = @popCount(self.piece_bb[@intFromEnum(Color.Black)][@intFromEnum(Pieces.Queen)]);

        // If any pawns, rooks, or queens exist, there's sufficient material
        if (white_pawns > 0 or black_pawns > 0) return false;
        if (white_rooks > 0 or black_rooks > 0) return false;
        if (white_queens > 0 or black_queens > 0) return false;

        // Count total minor pieces
        const white_minors = white_knights + white_bishops;
        const black_minors = black_knights + black_bishops;

        // King vs King
        if (white_minors == 0 and black_minors == 0) {
            return true;
        }

        // King + minor vs King
        if (white_minors == 1 and black_minors == 0) {
            return true;
        }
        if (white_minors == 0 and black_minors == 1) {
            return true;
        }

        // King + Bishop vs King + Bishop (same colored bishops)
        if (white_bishops == 1 and black_bishops == 1 and
            white_knights == 0 and black_knights == 0)
        {
            // Check if bishops are on same color squares
            const white_bishop_bb = self.piece_bb[@intFromEnum(Color.White)][@intFromEnum(Pieces.Bishop)];
            const black_bishop_bb = self.piece_bb[@intFromEnum(Color.Black)][@intFromEnum(Pieces.Bishop)];

            const dark_squares: u64 = 0xaa55aa55aa55aa55;
            const white_on_dark = (white_bishop_bb & dark_squares) != 0;
            const black_on_dark = (black_bishop_bb & dark_squares) != 0;

            if (white_on_dark == black_on_dark) {
                return true;
            }
        }

        return false;
    }

    pub fn isThreefoldRepetition(self: *Board, ply: usize) bool {
        const current_zobrist = self.game_state.zobrist;
        const halfmove_limit = @min(self.game_state.halfmove_clock, self.history.history_count);
        var count: u32 = 0;

        var i: usize = 0;
        while (i < halfmove_limit) : (i += 1) {
            const history_index = self.history.history_count - 1 - i;
            const past_state = self.history.history_list[history_index];

            if (past_state.zobrist == current_zobrist) {
                count += 1;
                if (i < ply) return true; // within search tree: twofold is enough
                if (count >= 2) return true; // game history: need actual threefold
            }
        }

        return false;
    }
};

pub inline fn flipColor(color: Color) Color {
    return if (color == Color.White) Color.Black else Color.White;
}

pub inline fn getSquareBB(square: Square) Bitboard {
    return @as(u64, 1) << @truncate(@as(u64, square));
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

// zig fmt: off
pub const Squares = enum(usize) {
    a1, b1, c1, d1, e1, f1, g1, h1,
    a2, b2, c2, d2, e2, f2, g2, h2,
    a3, b3, c3, d3, e3, f3, g3, h3,
    a4, b4, c4, d4, e4, f4, g4, h4,
    a5, b5, c5, d5, e5, f5, g5, h5,
    a6, b6, c6, d6, e6, f6, g6, h6,
    a7, b7, c7, d7, e7, f7, g7, h7,
    a8, b8, c8, d8, e8, f8, g8, h8,
};
// zig fmt: on
