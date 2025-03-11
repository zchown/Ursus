pub const Pieces = enum(usize) {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
};

pub const Color = enum(usize) {
    White,
    Black,
};

// General constants
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
pub const bb_empty = 0;
pub const bb_all = 0xFFFFFFFFFFFFFFFF;
pub const bb_file_a = 0x0101010101010101;
pub const bb_file_h = 0x8080808080808080;
pub const bb_rank_1 = 0x00000000000000FF;
pub const bb_rank_8 = 0xFF00000000000000;
pub const bb_diag_a1h8 = 0x8040201008040201;
pub const bb_diag_h1a8 = 0x0102040810204080;
