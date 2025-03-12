const std = @import("std");
const brd = @import("board.zig");
const Board = brd.Board;
const Bitboard = brd.Bitboard;
const GameState = brd.GameState;
const magic = @import("magics.zig");
const rad = @import("radagast.zig");

pub const not_a_file: Bitboard = 0xfefefefefefefefe;
pub const not_h_file: Bitboard = 0x7f7f7f7f7f7f7f7f;
pub const not_hg_file: Bitboard = 0x3f3f3f3f3f3f3f3f;
pub const not_ab_file: Bitboard = 0xfcfcfcfcfcfcfcfc;
pub const not_first_rank: Bitboard = 0xffffffffffffff00;
pub const not_eighth_rank: Bitboard = 0x00ffffffffffffff;
pub const dark_squares: Bitboard = 0xaa55aa55aa55aa55;

pub const MoveGen = struct {
    king: [brd.num_squares]Bitboard,
    knights: [brd.num_squares]Bitboard,
    pawns: [brd.num_colors * brd.num_squares]Bitboard,
    bishops: [brd.num_squares][512]Bitboard,
    rooks: [brd.num_squares][4096]Bitboard,
    bishop_masks: [brd.num_squares]Bitboard,
    rook_masks: [brd.num_squares]Bitboard,

    pub fn new() MoveGen {
        var mg: MoveGen = undefined;
        mg.king = [_]Bitboard{0};
        mg.knights = [_]Bitboard{0};
        mg.pawns = [_]Bitboard{0};
        mg.bishops = [_][512]Bitboard{0};
        mg.rooks = [_][4096]Bitboard{0};
        mg.bishop_masks = [_]Bitboard{0};
        mg.rook_masks = [_]Bitboard{0};

        mg.initKings();
        mg.initKnights();
        mg.initPawns();
        mg.initSliders();
        return mg;
    }

    // pub inline fn isAttacked(self: *MoveGen, sq: brd.Square, color: brd.Color, board: *Bitboard) bool {
    // }

    pub fn printAttackedSquares(self: *MoveGen, color: brd.Color, board: *Bitboard) void {
        for (0..brd.num_squares) |sq| {
            if (self.isAttacked(sq, color, board)) {
                std.debug.print("1");
            } else {
                std.debug.print("0");
            }
            if (sq % 8 == 7) {
                std.debug.print("\n");
            }
        }
    }

    pub fn getBishopAttacks(self: *MoveGen, sq: brd.Square, occ: Bitboard) Bitboard {
        occ &= self.bishop_masks[sq];
        occ *= magic.bishop_magics[sq];
        occ >>= 64 - magic.bishop_relevant_bits[sq];
        return self.bishops[sq][occ];
    }

    pub fn getRookAttacks(self: *MoveGen, sq: brd.Square, occ: Bitboard) Bitboard {
        occ &= self.rook_masks[sq];
        occ *= magic.rook_magics[sq];
        occ >>= 64 - magic.rook_relevant_bits[sq];
        return self.rooks[sq][occ];
    }

    pub fn getQueenAttacks(self: *MoveGen, sq: brd.Square, occ: Bitboard) Bitboard {
        var queen_attacks: Bitboard = undefined;

        var bishop_occ = occ;
        var rook_occ = occ;

        bishop_occ &= self.bishop_masks[sq];
        bishop_occ *= magic.bishop_magics[sq];
        bishop_occ >>= 64 - magic.bishop_relevant_bits[sq];

        queen_attacks = self.bishops[sq][bishop_occ];

        rook_occ &= self.rook_masks[sq];
        rook_occ *= magic.rook_magics[sq];
        rook_occ >>= 64 - magic.rook_relevant_bits[sq];

        queen_attacks = self.bishops[sq][bishop_occ] | self.rooks[sq][rook_occ];

        return queen_attacks;
    }

    fn initKings(self: *MoveGen) void {
        for (0..brd.num_squares) |sq| {
            self.kings[sq] = self.kingAttacks(sq);
        }
    }

    fn kingAttacks(sq: brd.Square) Bitboard {
        const b = brd.bb_squares[sq];
        var attacks: Bitboard = 0;

        if (b & not_h_file != 0) {
            if (b & not_eighth_rank != 0) {
                attacks |= b << 9;
            }
            if (b & not_first_rank != 0) {
                attacks |= b >> 7;
            }
            attacks |= b << 1;
        }
        if (b & not_a_file != 0) {
            if (b & not_eighth_rank != 0) {
                attacks |= b << 7;
            }
            if (b & not_first_rank != 0) {
                attacks |= b >> 9;
            }
            attacks |= b >> 1;
        }
        if (b & not_eighth_rank != 0) {
            attacks |= b << 8;
        }
        if (b & not_first_rank != 0) {
            attacks |= b >> 8;
        }
        return attacks;
    }

    fn initKnights(self: *MoveGen) void {
        for (0..brd.num_squares) |sq| {
            self.knights[sq] = self.knightAttacks(sq);
        }
    }

    fn knightAttacks(sq: brd.Square) Bitboard {
        const b = brd.bb_squares[sq];
        var attacks: Bitboard = 0;

        if (b & not_h_file != 0) {
            attacks |= b << 17;
            attacks |= b >> 15;
        }
        if (b & not_a_file != 0) {
            attacks |= b << 15;
            attacks |= b >> 17;
        }
        if (b & not_hg_file != 0) {
            attacks |= b << 10;
            attacks |= b >> 6;
        }
        if (b & not_ab_file != 0) {
            attacks |= b << 6;
            attacks |= b >> 10;
        }
        return attacks;
    }

    fn initPawns(self: *MoveGen) void {
        for (0..brd.num_squares) |sq| {
            self.pawns[(brd.Color.White * brd.num_squares) + sq] =
                self.pawnAttacks(sq, brd.Color.White);
            self.pawns[(brd.Color.Black * brd.num_squares) + sq] =
                self.pawnAttacks(sq, brd.Color.Black);
        }
    }

    fn pawnAttacks(sq: brd.Square, color: brd.Color) Bitboard {
        const b = brd.bb_squares[sq];
        var attacks: Bitboard = 0;

        if (color == brd.Color.White) {
            if (b & not_h_file != 0) {
                attacks |= b << 9;
            }
            if (b & not_a_file != 0) {
                attacks |= b << 7;
            }
        } else {
            if (b & not_h_file != 0) {
                attacks |= b >> 7;
            }
            if (b & not_a_file != 0) {
                attacks |= b >> 9;
            }
        }
        return attacks;
    }

    fn initSliders(self: *MoveGen) void {
        for (0..brd.num_squares) |sq| {
            self.bishop_masks[sq] = rad.maskBishopAttacks(sq);
            self.rook_masks[sq] = rad.maskRookAttacks(sq);

            const relevant_bits_bishop: i32 = rad.bishop_relevant_bits[sq];
            const relevant_bits_rook: i32 = rad.rook_relevant_bits[sq];

            const occupancy_index_bishop: u64 = 1 << relevant_bits_bishop;
            const occupancy_index_rook: u64 = 1 << relevant_bits_rook;

            for (0..occupancy_index_bishop) |i| {
                const occ = rad.set_occupancy(i, relevant_bits_bishop, self.bishop_masks[sq]);
                const magic_index = (occ * rad.bishop_magics[sq]) >>
                    (64 - relevant_bits_bishop);
                self.bishops[sq][magic_index] = rad.generateBishopAttacks(sq, occ);
            }

            for (0..occupancy_index_rook) |i| {
                const occ = rad.set_occupancy(i, relevant_bits_rook, self.rook_masks[sq]);
                const magic_index = (occ * rad.rook_magics[sq]) >>
                    (64 - relevant_bits_rook);
                self.rooks[sq][magic_index] = rad.generateRookAttacks(sq, occ);
            }
        }
    }
};
