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

// General constants
const num_colors = 2;
const num_pieces = 6;
const num_squares = 64;
const num_files = 8;
const num_ranks = 8;
const max_pieces = 32;

// Castling rights
const white_kingside = 1;
const white_queenside = 2;
const black_kingside = 4;
const black_queenside = 8;
const all_castling = 15;
const num_castles = 16;

// Move constants
const max_game_moves = 2048;
const max_legal_moves = 255;
const max_move_rule = 100;

// Bitboard constants
const bb_empty = 0;
const bb_all = 0xFFFFFFFFFFFFFFFF;
const bb_file_a = 0x0101010101010101;
const bb_file_h = 0x8080808080808080;
const bb_rank_1 = 0x00000000000000FF;
const bb_rank_8 = 0xFF00000000000000;
const bb_diag_a1h8 = 0x8040201008040201;
const bb_diag_h1a8 = 0x0102040810204080;
