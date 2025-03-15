const std = @import("std");
const brd = @import("board.zig");
const Board = brd.Board;
const Bitboard = brd.Bitboard;
const GameState = brd.GameState;
const magic = @import("magics.zig");
const rad = @import("radagast.zig");

const not_a_file: Bitboard = 0xfefefefefefefefe;
const not_h_file: Bitboard = 0x7f7f7f7f7f7f7f7f;
const not_hg_file: Bitboard = 0x3f3f3f3f3f3f3f3f;
const not_ab_file: Bitboard = 0xfcfcfcfcfcfcfcfc;
const not_first_rank: Bitboard = 0xffffffffffffff00;
const not_eighth_rank: Bitboard = 0x00ffffffffffffff;
const dark_squares: Bitboard = 0xaa55aa55aa55aa55;

const allMoves = false;
const onlyCaptures = true;

pub const EncodedMove = packed struct (u32) {
    start_square: u6,
    end_square: u6,
    piece: u4,
    promoted_piece: u4,
    capture: u1,
    double_pawn_push: u1,
    en_passant: u1,
    castling: u1,

    _padding: u8 = 0,

    pub fn encode(start: brd.Square, end: brd.Square, piece: brd.Pieces, promoted_piece: ?brd.Pieces,
        capture: bool, double_pawn_push: bool, en_passant: bool, castling: bool) EncodedMove {
        const pp = promoted_piece orelse brd.Pieces.Pawn;
        return EncodedMove{
            .start_square = @intCast(start),
            .end_square = @intCast(end),
            .piece = @intFromEnum(piece),
            .promoted_piece = @intFromEnum(pp),
            .capture = @intCast(capture),
            .double_pawn_push = @intCast(double_pawn_push),
            .en_passant = @intCast(en_passant),
            .castling = @intCast(castling),
        };
    }

    pub fn print(self: EncodedMove) void {
        std.debug.print("Start square: {}\n", .{self.start_square});
        std.debug.print("End square: {}\n", .{self.end_square});
        std.debug.print("Piece: {}\n", .{self.piece});
        std.debug.print("Promoted piece: {}\n", .{self.promoted_piece});
        std.debug.print("Capture: {}\n", .{self.capture});
        std.debug.print("Double pawn push: {}\n", .{self.double_pawn_push});
        std.debug.print("En passant: {}\n", .{self.en_passant});
        std.debug.print("Castling: {}\n", .{self.castling});
    }
};

pub const MoveList = struct {
    list: [218:0]EncodedMove,
    current: usize = 0,

    pub fn new() MoveList {
        return MoveList{ .list = @splat(0)};
    }

    pub fn addMove(self: *MoveList, start: brd.Square, end: brd.Square, piece: brd.Pieces, promoted_piece: ?brd.Pieces,
        capture: bool, double_pawn_push: bool, en_passant: bool, castling: bool) void {

        const move = EncodedMove.encode(start, end, piece, promoted_piece, capture, double_pawn_push, en_passant, castling);

        self.list[self.current] = move;
        self.current += 1;
    }

    pub fn addEasyMove(self: *MoveList, start: brd.Square, end: brd.Square, piece: brd.Pieces, capture: bool) void {
        self.addMove(start, end, piece, null, capture, false, false, false);
    }

    pub fn print(self: *MoveList) void {
        for (0..self.current) |i| {
            self.list[i].print();
        }
    }
};

pub const MoveGen = struct {
    kings: [brd.num_squares]Bitboard,
    knights: [brd.num_squares]Bitboard,
    pawns: [brd.num_colors * brd.num_squares]Bitboard,
    bishops: [brd.num_squares][512]Bitboard,
    rooks: [brd.num_squares][4096]Bitboard,
    bishop_masks: [brd.num_squares]Bitboard,
    rook_masks: [brd.num_squares]Bitboard,

    pub fn new() MoveGen {
        var mg: MoveGen = undefined;
        mg.kings = undefined;
        mg.knights = undefined;
        mg.pawns = undefined;
        mg.bishops = undefined;
        mg.rooks = undefined;
        mg.bishop_masks = undefined;
        mg.rook_masks = undefined;

        mg.initKings();
        mg.initKnights();
        mg.initPawns();
        mg.initSliders();
        return mg;
    }

    // pseudo-legal move generation
    pub fn generateMoves(self: *MoveGen, board: *Board, move_flag: bool) MoveList {
        var move_list = MoveList.new();

        const color = board.game_state.side_to_move;

        // pawn moves
        self.generatePawnMoves(&self, board, &move_list, color, move_flag);

        // king moves
        self.generateKingMoves(board, &move_list, color, move_flag);

        // knight moves
        self.generateKnightMoves(&self, board, &move_list, color, move_flag);

        // bishop, rook, queen moves
        self.generateSlideMoves(&self, board, &move_list, color, move_flag);

        // castling moves
        generateCastleMoves(board, &move_list, color);

        return move_list;
    }

    pub fn generatePawnMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, move_flag: bool) void {
        var bb = board.piece_bb[color][brd.Pieces.Pawn];
        var start_square: brd.Square = undefined;
        var end_square: brd.Square = undefined;
        var attacks: Bitboard = undefined;

        var end_square_update: i8 = undefined;
        var pawn_promo_1: brd.Square = undefined;
        var pawn_promo_2: brd.Square = undefined;

        if (color == brd.Color.White) {
            end_square_update = -8;
            pawn_promo_1 = @intFromEnum(brd.Squares.a8);
            pawn_promo_2 = @intFromEnum(brd.Squares.h6);
        } else {
            end_square_update = 8;
            pawn_promo_1 = @intFromEnum(brd.Squares.a3);
            pawn_promo_2 = @intFromEnum(brd.Squares.h1);
        }

        while (bb != 0) {
            start_square = brd.getLSB(bb);
            end_square = start_square + end_square_update;

            // quite moves
            if (!move_flag and !(end_square < 0) and !(end_square < 63) and !brd.getBit(board.occupancy(), end_square)) {
                //pawn promotion
                if (start_square < pawn_promo_1 and start_square > pawn_promo_2) {
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Queen, false, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Rook, false, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Bishop, false, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Knight, false, false, false, false);
                } else {
                    // normal pawn move
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Pawn, false);

                    // double pawn push
                    if (color == brd.Color.White) {
                        if (start_square < @intFromEnum(brd.Squares.a3) 
                            and !brd.getBit(board.occupancy(), end_square + end_square_update)) {
                            move_list.addMove(start_square, end_square - 8, brd.Pieces.Pawn, null, false, true, false, false);
                        }
                    } else {
                        if (start_square > @intFromEnum(brd.Squares.h6)
                            and !brd.getBit(board.occupancy(), end_square + end_square_update)) {
                            move_list.addMove(start_square, end_square + 8, brd.Pieces.Pawn, null, false, true, false, false);
                        }
                    }
                }
            }

            // capture moves
            attacks = self.pawns[@intFromEnum(color) * 64 + start_square] & board.occupancy();
            while (attacks) {
                end_square = brd.getLSB(attacks);
                // promotion captures
                if (start_square < pawn_promo_1 and start_square > pawn_promo_2) {
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Queen, true, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Rook, true, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Bishop, true, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Knight, true, false, false, false);
                } else {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Pawn, true);
                }
                brd.popBit(&attacks, end_square);
            }

            if (board.game_state.en_passant != null) {
                const ep_square: brd.Square = board.game_state.en_passant orelse 0;
                const ep_attacks: Bitboard = self.pawns[@intFromEnum(color) * 64 + start_square] & brd.getSquareBB(ep_square);

                if (ep_attacks != 0) {
                    move_list.addMove(start_square, ep_square, brd.Pieces.Pawn, null, true, false, true, false);
                }
            }
            brd.popBit(&bb, start_square);
        }
    }

    pub fn generateKingMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, move_flag: bool) void {
        var bb = board.piece_bb[color][brd.Pieces.King];
        var start_square: brd.Square = undefined;
        var end_square: brd.Square = undefined;
        var attacks: Bitboard = undefined;

        while (bb != 0) {
            start_square = brd.getLSB(bb);
            attacks = self.kings[start_square] & ~board.color_bb[color];

            while (attacks) {
                end_square = brd.getLSB(attacks);

                // quite move
                if (!move_flag and !brd.getBit(board.color_bb[brd.flipColor(color)], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.King, false);
                } else {
                    // capture move
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.King, true);
                }

                brd.popBit(&attacks, end_square);
            }

            brd.popBit(&bb, start_square);
        }
    }

    pub fn generateSlideMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, move_flag: bool) void {
        var bb: Bitboard = undefined;
        var start_square: brd.Square = undefined;
        var end_square: brd.Square = undefined;
        var attacks: Bitboard = undefined;

        const pieces = [_]brd.Pieces{brd.Pieces.Bishop, brd.Pieces.Rook, brd.Pieces.Queen};
        const funcs = [_](fn (*MoveGen, brd.Square, Bitboard) Bitboard){
            self.getBishopAttacks,
            self.getRookAttacks,
            self.getQueenAttacks,
        };

        for (0..4) |i| {
            bb = board.piece_bb[color][pieces[i]];
            while (bb != 0) {
                start_square = brd.getLSB(bb);
                attacks = funcs[i](self, start_square, board.occupancy()) & ~board.color_bb[color];

                while (attacks) {
                    end_square = brd.getLSB(attacks);

                    // quite move
                    if (!move_flag and !brd.getBit(board.color_bb[brd.flipColor(color)], end_square)) {
                        move_list.addEasyMove(start_square, end_square, pieces[i], false);
                    } else {
                        // capture move
                        move_list.addEasyMove(start_square, end_square, pieces[i], true);
                    }

                    brd.popBit(&attacks, end_square);
                }

                brd.popBit(&bb, start_square);
            }
        }
    }

    pub fn generateKnightMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, move_flag: bool) void {
        var bb = board.piece_bb[color][brd.Pieces.Knight];
        var start_square: brd.Square = undefined;
        var end_square: brd.Square = undefined;
        var attacks: Bitboard = undefined;

        while (bb != 0) {
            start_square = brd.getLSB(bb);
            attacks = self.knights[start_square] & ~board.color_bb[color];

            while (attacks) {
                end_square = brd.getLSB(attacks);

                // quite move
                if (!move_flag and !brd.getBit(board.color_bb[brd.flipColor(color)], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Knight, false);
                } else {
                    // capture move
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Knight, true);
                }

                brd.popBit(&attacks, end_square);
            }

            brd.popBit(&bb, start_square);
        }
    }

    pub fn isAttacked(self: *MoveGen, sq: brd.Square, color: brd.Color, board: *Board) bool {
        const op_color = brd.flipColor(color);

        if (self.kings[sq] & board.piece_bb[color][brd.Piece.King] != 0) {
            return true;
        }

        if (self.knights[sq] & board.piece_bb[color][brd.Piece.Knight] != 0) {
            return true;
        }

        if (self.pawns[@intFromEnum(op_color) * 64 + sq] 
            & board.piece_bb[color][brd.Piece.Pawn] != 0) {
            return true;
        }

        if (self.getBishopAttacks(sq, board.occupany())
            & board.piece_bb[color][brd.Piece.Bishop] != 0) {
            return true;
        }

        if (self.getRookAttacks(sq, board.occupany())
            & board.piece_bb[color][brd.Piece.Rook] != 0) {
            return true;
        }

        if (self.getQueenAttacks(sq, board.occupany())
            & board.piece_bb[color][brd.Piece.Queen] != 0) {
            return true;
        }

        return false;
    }

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
            self.kings[sq] = kingAttacks(sq);
        }
    }

    fn kingAttacks(sq: brd.Square) Bitboard {
        const b = brd.getSquareBB(sq);
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
            self.knights[sq] = knightAttacks(sq);
        }
    }

    fn knightAttacks(sq: brd.Square) Bitboard {
        const b = brd.getSquareBB(sq);
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
            // White pawns
            self.pawns[sq] = pawnAttacks(sq, brd.Color.White);
            // Black pawns
            self.pawns[64 + sq] = pawnAttacks(sq, brd.Color.Black);
        }
    }

    fn pawnAttacks(sq: brd.Square, color: brd.Color) Bitboard {
        const b = brd.getSquareBB(sq);
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

            const relevant_bits_bishop: i32 = @intCast(rad.bishop_relevant_bits[sq]);
            const relevant_bits_rook: i32 = @intCast(rad.rook_relevant_bits[sq]);

            const occupancy_index_bishop: u64 =
                @as(u64, 1) << @intCast(relevant_bits_bishop);
            const occupancy_index_rook: u64 =
                @as(u64, 1) << @intCast(relevant_bits_rook);

            for (0..occupancy_index_bishop) |i| {
                const occ = rad.setOccupancy(i, @intCast(relevant_bits_bishop), self.bishop_masks[sq]);
                const magic_index = (occ * magic.bishop_magics[sq]) >>
                    @intCast(64 - relevant_bits_bishop);
                self.bishops[sq][magic_index] = rad.bishopAttacks(sq, occ);
            }

            for (0..occupancy_index_rook) |i| {
                const occ = rad.setOccupancy(i, @intCast(relevant_bits_rook), self.rook_masks[sq]);
                const magic_index = (occ * magic.rook_magics[sq]) >>
                    @intCast(64 - relevant_bits_rook);
                self.rooks[sq][magic_index] = rad.rookAttacks(sq, occ);
            }
        }
    }
};

pub fn generateCastleMoves(board: *Board, move_list: *MoveList, color: brd.Color) void {
    if (color == brd.Color.White) {
        if (board.game_state.castling_rights & brd.CastlingRights.WhiteKingSide != 0) {
            if (!brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.f1))
                and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.g1))) {
                move_list.addMove(@intFromEnum(brd.Squares.e1), @intFromEnum(brd.Squares.g1), brd.Pieces.King, null, false, false, false, true);
            }
        }

        if (board.game_state.castling_rights & brd.CastlingRights.WhiteQueenSide != 0) {
            if (!brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.d1))
                and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.c1))
                and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.b1))) {
                move_list.addMove(@intFromEnum(brd.Squares.e1), @intFromEnum(brd.Squares.c1), brd.Pieces.King, null, false, false, false, true);
            }
        }

    } else {
        if (board.game_state.castling_rights & brd.CastlingRights.BlackKingSide != 0) {
            if (!brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.f8))
                and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.g8))) {
                move_list.addMove(@intFromEnum(brd.Squares.e8), @intFromEnum(brd.Squares.g8), brd.Pieces.King, null, false, false, false, true);
            }
        }

        if (board.game_state.castling_rights & brd.CastlingRights.BlackQueenSide != 0) {
            if (!brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.d8))
                and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.c8))
                and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.b8))) {
                move_list.addMove(@intFromEnum(brd.Squares.e8), @intFromEnum(brd.Squares.c8), brd.Pieces.King, null, false, false, false, true);
            }
        }
    }
}

// pub fn makeMove(board: *Board, mv: EncodedMove) void {

// }
