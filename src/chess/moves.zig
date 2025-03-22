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

pub const allMoves = false;
pub const onlyCaptures = true;

pub const EncodedMove = packed struct(u32) {
    start_square: u6 = 0,
    end_square: u6 = 0,
    piece: u4 = 0,
    promoted_piece: u4 = 0,
    capture: u1 = 0,
    captured_piece: u4 = 0,
    double_pawn_push: u1 = 0,
    en_passant: u1 = 0,
    castling: u1 = 0,

    _padding: u4 = 0,

    pub fn encode(start: brd.Square, end: brd.Square, piece: brd.Pieces, promoted_piece: ?brd.Pieces, capture: bool, captured_piece: ?brd.Pieces, double_pawn_push: bool, en_passant: bool, castling: bool) EncodedMove {
        return EncodedMove{
            .start_square = @intCast(start),
            .end_square = @intCast(end),
            .piece = @intFromEnum(piece),
            .promoted_piece = @intFromEnum(promoted_piece orelse brd.Pieces.Pawn),
            .capture = @intFromBool(capture),
            .captured_piece = @intFromEnum(captured_piece orelse brd.Pieces.Pawn),
            .double_pawn_push = @intFromBool(double_pawn_push),
            .en_passant = @intFromBool(en_passant),
            .castling = @intFromBool(castling),
        };
    }

    pub fn print(self: EncodedMove) void {
        std.debug.print("Start square: {}\n", .{self.start_square});
        std.debug.print("End square: {}\n", .{self.end_square});
        std.debug.print("Piece: {}\n", .{self.piece});
        std.debug.print("Promoted piece: {}\n", .{self.promoted_piece});
        std.debug.print("Capture: {}\n", .{self.capture});
        std.debug.print("Captured piece: {}\n", .{self.captured_piece});
        std.debug.print("Double pawn push: {}\n", .{self.double_pawn_push});
        std.debug.print("En passant: {}\n", .{self.en_passant});
        std.debug.print("Castling: {}\n", .{self.castling});
    }

    pub fn printAlgebraic(self: EncodedMove) void {
        if (self.castling != 0) {
            const startFile: u8 = self.start_square % 8;
            const endFile: u8 = self.end_square % 8;
            if (endFile > startFile) {
                std.debug.print("O-O\n", .{});
            } else {
                std.debug.print("O-O-O\n", .{});
            }
            return;
        }

        const pieceAbbrev: u8 = switch (self.piece) {
            0 => ' ',
            1 => 'N',
            2 => 'B',
            3 => 'R',
            4 => 'Q',
            5 => 'K',
            else => '?',
        };

        if (self.piece == 0 and self.capture != 0) {
            const startFileLetter: u8 = ('a' +| @as(u8, @intCast((self.start_square % 8))));
            std.debug.print("{c}x", .{startFileLetter});
        } else if (self.piece != 0) {
            std.debug.print("{c}", .{pieceAbbrev});
            if (self.capture != 0) {
                std.debug.print("x", .{});
            }
        }

        const fileLetter: u8 = ('a' +| @as(u8, @intCast(self.end_square % 8)));
        const rank: u8 = @as(u8, @intCast((self.end_square / 8) + 1));
        std.debug.print("{c}{any}", .{ fileLetter, rank });

        if (self.promoted_piece != 0) {
            const promoAbbrev = switch (self.promoted_piece) {
                1 => "N",
                2 => "B",
                3 => "R",
                4 => "Q",
                else => "?",
            };
            std.debug.print("={c}", .{promoAbbrev});
        }

        if (self.en_passant == 1) {
            std.debug.print(" e.p.", .{});
        }

        std.debug.print("\n", .{});
    }
};

pub const MoveList = struct {
    list: [218:EncodedMove{}]EncodedMove,
    current: usize = 0,

    pub fn new() MoveList {
        var ml = MoveList{ .list = undefined, .current = 0 };
        ml.list[0] = EncodedMove{};
        return ml;
    }

    pub inline fn addMove(self: *MoveList, start: brd.Square, end: brd.Square, piece: brd.Pieces, promoted_piece: ?brd.Pieces, capture: bool, captured_piece: ?brd.Pieces, double_pawn_push: bool, en_passant: bool, castling: bool) void {
        const move = EncodedMove.encode(start, end, piece, promoted_piece, capture, captured_piece, double_pawn_push, en_passant, castling);

        self.list[self.current] = move;
        self.current += 1;

        if (self.current < 218) {
            self.list[self.current] = EncodedMove{};
        }
    }

    pub inline fn addEasyMove(self: *MoveList, start: brd.Square, end: brd.Square, piece: brd.Pieces, capture: bool, captured_piece: ?brd.Pieces) void {
        self.addMove(start, end, piece, null, capture, captured_piece, false, false, false);
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
        self.generatePawnMoves(board, &move_list, color, move_flag);

        // king moves
        self.generateKingMoves(board, &move_list, color, move_flag);

        // knight moves
        self.generateKnightMoves(board, &move_list, color, move_flag);

        // bishop, rook, queen moves
        self.generateSlideMoves(board, &move_list, color, move_flag);

        // castling moves
        generateCastleMoves(board, &move_list, color);

        return move_list;
    }

    pub fn generatePawnMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, move_flag: bool) void {
        var bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Pawn)];
        var start_square: brd.Square = undefined;
        var end_square: isize = undefined;
        var attacks: Bitboard = undefined;

        var end_square_update: isize = undefined;
        var pawn_promo_1: brd.Square = undefined;
        var pawn_promo_2: brd.Square = undefined;

        if (color == brd.Color.White) {
            @branchHint(.unpredictable);
            end_square_update = 8;
            pawn_promo_1 = @intFromEnum(brd.Squares.a8);
            pawn_promo_2 = @intFromEnum(brd.Squares.h6);
        } else {
            @branchHint(.unpredictable);
            end_square_update = -8;
            pawn_promo_1 = @intFromEnum(brd.Squares.a3);
            pawn_promo_2 = @intFromEnum(brd.Squares.h1);
        }

        while (bb != 0) {
            start_square = brd.getLSB(bb);
            end_square = @as(isize, @intCast(start_square)) + end_square_update;

            // quite moves
            if (!move_flag and !(end_square < 0) and !(end_square > 63) and !brd.getBit(board.occupancy(), @as(u64, @intCast(end_square)))) {
                const esq: u64 = @as(u64, @intCast(end_square));
                //pawn promotion
                if (start_square < pawn_promo_1 and start_square > pawn_promo_2) {
                    @branchHint(.unlikely);
                    move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Queen, false, null, false, false, false);
                    move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Rook, false, null, false, false, false);
                    move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Bishop, false, null, false, false, false);
                    move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Knight, false, null, false, false, false);
                } else {
                    @branchHint(.likely);
                    // normal pawn move
                    move_list.addEasyMove(start_square, esq, brd.Pieces.Pawn, false, null);

                    // double pawn push
                    if (color == brd.Color.White) {
                        @branchHint(.unlikely);
                        if (start_square < @intFromEnum(brd.Squares.a3) and !brd.getBit(board.occupancy(), @as(u64, @intCast(end_square + end_square_update)))) {
                            move_list.addMove(start_square, @as(u64, @intCast(end_square + 8)), brd.Pieces.Pawn, null, false, null, true, false, false);
                        }
                    } else {
                        @branchHint(.unlikely);
                        if (start_square > @intFromEnum(brd.Squares.h6) and !brd.getBit(board.occupancy(), @as(u64, @intCast(end_square + end_square_update)))) {
                            move_list.addMove(start_square, @as(u64, @intCast(end_square - 8)), brd.Pieces.Pawn, null, false, null, true, false, false);
                        }
                    }
                }
            }

            // capture moves
            attacks = self.pawns[@as(usize, @intFromEnum(color)) * 64 + start_square] & board.color_bb[@intFromEnum(brd.flipColor(color))];
            while (attacks != 0) {
                end_square = brd.getLSB(attacks);
                const esq: u64 = @as(u64, @intCast(end_square));

                // get captured piece
                const captured_piece: ?brd.Pieces = board.getPieceFromSquare(esq);

                // promotion captures
                if (start_square < pawn_promo_1 and start_square > pawn_promo_2) {
                    @branchHint(.unlikely);
                    move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Queen, true, captured_piece, false, false, false);
                    move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Rook, true, captured_piece, false, false, false);
                    move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Bishop, true, captured_piece, false, false, false);
                    move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Knight, true, captured_piece, false, false, false);
                } else {
                    @branchHint(.likely);
                    move_list.addEasyMove(start_square, esq, brd.Pieces.Pawn, true, captured_piece);
                }
                brd.popBit(&attacks, esq);
            }

            if (board.game_state.en_passant_square != null) {
                const ep_square: brd.Square = board.game_state.en_passant_square orelse 0;
                const ep_attacks: Bitboard = self.pawns[@as(usize, @intFromEnum(color)) * 64 + start_square] & brd.getSquareBB(ep_square);

                if (ep_attacks != 0) {
                    @branchHint(.unlikely);
                    const captured_piece: ?brd.Pieces = board.getPieceFromSquare(ep_square);
                    move_list.addMove(start_square, ep_square, brd.Pieces.Pawn, null, true, captured_piece, false, true, false);
                }
            }
            brd.popBit(&bb, start_square);
        }
    }

    pub fn generateKingMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, move_flag: bool) void {
        var bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.King)];
        var start_square: brd.Square = undefined;
        var end_square: brd.Square = undefined;
        var attacks: Bitboard = undefined;

        while (bb != 0) {
            start_square = brd.getLSB(bb);
            attacks = self.kings[start_square] & ~board.color_bb[@intFromEnum(color)];

            while (attacks != 0) {
                end_square = brd.getLSB(attacks);

                // quite move
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(brd.flipColor(color))], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.King, false, null);
                } else {
                    // capture move
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.King, true, board.getPieceFromSquare(end_square));
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

        // Bishop moves
        bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Bishop)];
        while (bb != 0) {
            start_square = brd.getLSB(bb);
            attacks = getBishopAttacks(self, start_square, board.occupancy()) & ~board.color_bb[@intFromEnum(color)];
            while (attacks != 0) {
                end_square = brd.getLSB(attacks);
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(brd.flipColor(color))], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Bishop, false, null);
                } else {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Bishop, true, board.getPieceFromSquare(end_square));
                }
                brd.popBit(&attacks, end_square);
            }
            brd.popBit(&bb, start_square);
        }

        // Rook moves
        bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Rook)];
        while (bb != 0) {
            start_square = brd.getLSB(bb);
            attacks = getRookAttacks(self, start_square, board.occupancy()) & ~board.color_bb[@intFromEnum(color)];
            while (attacks != 0) {
                end_square = brd.getLSB(attacks);
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(brd.flipColor(color))], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Rook, false, null);
                } else {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Rook, true, board.getPieceFromSquare(end_square));
                }
                brd.popBit(&attacks, end_square);
            }
            brd.popBit(&bb, start_square);
        }

        // Queen moves
        bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Queen)];
        while (bb != 0) {
            start_square = brd.getLSB(bb);
            attacks = getQueenAttacks(self, start_square, board.occupancy()) & ~board.color_bb[@intFromEnum(color)];
            while (attacks != 0) {
                end_square = brd.getLSB(attacks);
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(brd.flipColor(color))], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Queen, false, null);
                } else {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Queen, true, board.getPieceFromSquare(end_square));
                }
                brd.popBit(&attacks, end_square);
            }
            brd.popBit(&bb, start_square);
        }
    }

    pub fn generateKnightMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, move_flag: bool) void {
        var bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Knight)];
        var start_square: brd.Square = undefined;
        var end_square: brd.Square = undefined;
        var attacks: Bitboard = undefined;

        while (bb != 0) {
            start_square = brd.getLSB(bb);
            attacks = self.knights[start_square] & ~board.color_bb[@intFromEnum(color)];

            while (attacks != 0) {
                end_square = brd.getLSB(attacks);

                // quite move
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(brd.flipColor(color))], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Knight, false, null);
                } else {
                    // capture move
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Knight, true, board.getPieceFromSquare(end_square));
                }

                brd.popBit(&attacks, end_square);
            }

            brd.popBit(&bb, start_square);
        }
    }

    pub inline fn isAttacked(self: *MoveGen, sq: brd.Square, color: brd.Color, board: *Board) bool {
        const op_color = brd.flipColor(color);

        if (self.knights[sq] & board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Knight)] != 0) {
            return true;
        }

        if (self.pawns[@as(usize, @intFromEnum(op_color)) * 64 + sq] & board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Pawn)] != 0) {
            return true;
        }

        if (self.getBishopAttacks(sq, board.occupancy()) & board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Bishop)] != 0) {
            return true;
        }

        if (self.getRookAttacks(sq, board.occupancy()) & board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Rook)] != 0) {
            return true;
        }

        if (self.getQueenAttacks(sq, board.occupancy()) & board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Queen)] != 0) {
            return true;
        }

        if (self.kings[sq] & board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.King)] != 0) {
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

    pub inline fn getBishopAttacks(self: *MoveGen, sq: brd.Square, occ: Bitboard) Bitboard {
        var mocc = occ;
        mocc &= self.bishop_masks[sq];
        mocc *%= magic.bishop_magics[sq];
        mocc >>= @as(u6, @truncate(64 - rad.bishop_relevant_bits[sq]));
        return self.bishops[sq][mocc];
    }

    pub inline fn getRookAttacks(self: *MoveGen, sq: brd.Square, occ: Bitboard) Bitboard {
        var mocc = occ;
        mocc &= self.rook_masks[sq];
        mocc *%= magic.rook_magics[sq];
        mocc >>= @as(u6, @truncate(64 - rad.rook_relevant_bits[sq]));
        return self.rooks[sq][mocc];
    }

    pub inline fn getQueenAttacks(self: *MoveGen, sq: brd.Square, occ: Bitboard) Bitboard {
        var queen_attacks: Bitboard = 0;

        var bishop_occ = occ;
        var rook_occ = occ;

        bishop_occ &= self.bishop_masks[sq];
        bishop_occ *%= magic.bishop_magics[sq];
        bishop_occ >>= @as(u6, @truncate(64 - rad.bishop_relevant_bits[sq]));

        queen_attacks = self.bishops[sq][bishop_occ];

        rook_occ &= self.rook_masks[sq];
        rook_occ *%= magic.rook_magics[sq];
        rook_occ >>= @as(u6, @truncate(64 - rad.rook_relevant_bits[sq]));

        queen_attacks |= self.rooks[sq][rook_occ];

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
            if ((b & not_h_file) != 0) {
                attacks |= b << 9;
            }
            if ((b & not_a_file) != 0) {
                attacks |= b << 7;
            }
        } else {
            if ((b & not_h_file) != 0) {
                attacks |= b >> 7;
            }
            if ((b & not_a_file) != 0) {
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
                const magic_index = (occ *% magic.bishop_magics[sq]) >>
                    @intCast(64 - relevant_bits_bishop);
                self.bishops[sq][magic_index] = rad.bishopAttacks(sq, occ);
            }

            for (0..occupancy_index_rook) |i| {
                const occ = rad.setOccupancy(i, @intCast(relevant_bits_rook), self.rook_masks[sq]);
                const magic_index = (occ *% magic.rook_magics[sq]) >>
                    @intCast(64 - relevant_bits_rook);
                self.rooks[sq][magic_index] = rad.rookAttacks(sq, occ);
            }
        }
    }
};

pub fn generateCastleMoves(board: *Board, move_list: *MoveList, color: brd.Color) void {
    if (color == brd.Color.White) {
        @branchHint(.unpredictable);
        if ((board.game_state.castling_rights) & @intFromEnum(brd.CastleRights.WhiteKingside) != 0) {
            if (!brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.f1)) and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.g1))) {
                @branchHint(.unlikely);
                move_list.addMove(@intFromEnum(brd.Squares.e1), @intFromEnum(brd.Squares.g1), brd.Pieces.King, null, false, null, false, false, true);
            }
        }

        if ((board.game_state.castling_rights) & @intFromEnum(brd.CastleRights.WhiteQueenside) != 0) {
            if (!brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.d1)) and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.c1)) and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.b1))) {
                @branchHint(.unlikely);
                move_list.addMove(@intFromEnum(brd.Squares.e1), @intFromEnum(brd.Squares.c1), brd.Pieces.King, null, false, null, false, false, true);
            }
        }
    } else {
        @branchHint(.unpredictable);
        if ((board.game_state.castling_rights) & @intFromEnum(brd.CastleRights.BlackKingside) != 0) {
            if (!brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.f8)) and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.g8))) {
                @branchHint(.unlikely);
                move_list.addMove(@intFromEnum(brd.Squares.e8), @intFromEnum(brd.Squares.g8), brd.Pieces.King, null, false, null, false, false, true);
            }
        }

        if ((board.game_state.castling_rights) & @intFromEnum(brd.CastleRights.BlackQueenside) != 0) {
            if (!brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.d8)) and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.c8)) and !brd.getBit(board.occupancy(), @intFromEnum(brd.Squares.b8))) {
                @branchHint(.unlikely);
                move_list.addMove(@intFromEnum(brd.Squares.e8), @intFromEnum(brd.Squares.c8), brd.Pieces.King, null, false, null, false, false, true);
            }
        }
    }
}

pub fn makeMove(board: *Board, move: EncodedMove) void {
    board.history.addToHistory(board.game_state);

    // Convert fields to appropriate types
    const from_square = @as(brd.Square, @intCast(move.start_square));
    const to_square = @as(brd.Square, @intCast(move.end_square));
    const piece_type = @as(brd.Pieces, @enumFromInt(move.piece));
    const moving_color = board.toMove();

    // Increment halfmove clock for non-capture, non-pawn moves
    if (piece_type != brd.Pieces.Pawn and move.capture == 0) {
        // @branchHint(.unpredictable);
        board.game_state.halfmove_clock += 1;
    } else {
        // Reset halfmove clock for captures and pawn moves
        board.game_state.halfmove_clock = 0;
    }

    // Handle castling moves
    if (move.castling == 1) {
        @branchHint(.unlikely);
        board.movePiece(moving_color, brd.Pieces.King, from_square, to_square);

        if (to_square > from_square) {
            // Kingside castling
            const rook_from = if (moving_color == brd.Color.White) @as(brd.Square, 7) else @as(brd.Square, 63);
            const rook_to = if (moving_color == brd.Color.White) @as(brd.Square, 5) else @as(brd.Square, 61);
            board.movePiece(moving_color, brd.Pieces.Rook, rook_from, rook_to);
        } else {
            // Queenside castling
            const rook_from = if (moving_color == brd.Color.White) @as(brd.Square, 0) else @as(brd.Square, 56);
            const rook_to = if (moving_color == brd.Color.White) @as(brd.Square, 3) else @as(brd.Square, 59);
            board.movePiece(moving_color, brd.Pieces.Rook, rook_from, rook_to);
        }

        // Update castling rights
        if (moving_color == brd.Color.White) {
            @branchHint(.unpredictable);
            // @branchHint(.unpredictable);
            board.updateCastlingRights(@as(brd.CastleRights, @enumFromInt((board.game_state.castling_rights) & ~(@intFromEnum(brd.CastleRights.WhiteKingside) | @intFromEnum(brd.CastleRights.WhiteQueenside)))));
        } else {
            // @branchHint(.unpredictable);
            board.updateCastlingRights(@as(brd.CastleRights, @enumFromInt((board.game_state.castling_rights) & ~(@intFromEnum(brd.CastleRights.BlackKingside) | @intFromEnum(brd.CastleRights.BlackQueenside)))));
        }
    }
    // Handle double pawn push
    else if (move.double_pawn_push == 1) {
        board.movePiece(moving_color, piece_type, from_square, to_square);

        // Set en passant square
        const ep_square = if (moving_color == brd.Color.White) to_square - 8 else to_square + 8;
        board.setEnPassantSquare(@intCast(ep_square));
    }
    // Handle en passant capture
    else if (move.en_passant == 1) {
        @branchHint(.unlikely);
        board.movePiece(moving_color, brd.Pieces.Pawn, from_square, to_square);

        const captured_pawn_square = if (moving_color == brd.Color.White) to_square - 8 else to_square + 8;
        board.removePiece(brd.flipColor(moving_color), brd.Pieces.Pawn, captured_pawn_square);

        board.clearEnPassantSquare();
    }
    // Handle promotion
    else if (move.promoted_piece != 0) {
        @branchHint(.unlikely);
        board.removePiece(moving_color, brd.Pieces.Pawn, from_square);
        const promoted_piece_type = @as(brd.Pieces, @enumFromInt(move.promoted_piece));

        // Handle capture during promotion
        if (move.capture == 1) {
            const captured_piece_type = @as(brd.Pieces, @enumFromInt(move.captured_piece));
            board.removePiece(brd.flipColor(moving_color), captured_piece_type, to_square);
        }

        board.addPiece(moving_color, promoted_piece_type, to_square);

        // Clear en passant square
        board.clearEnPassantSquare();
    }
    // Handle general move
    else {
        @branchHint(.likely);
        if (move.capture == 1) {
            const captured_piece_type = @as(brd.Pieces, @enumFromInt(move.captured_piece));
            board.removePiece(brd.flipColor(moving_color), captured_piece_type, to_square);
        }

        board.movePiece(moving_color, piece_type, from_square, to_square);

        // Update castling rights if rook or king moves
        if (piece_type == brd.Pieces.King) {
            if (moving_color == brd.Color.White) {
                @branchHint(.unpredictable);
                board.updateCastlingRights(@as(brd.CastleRights, @enumFromInt((board.game_state.castling_rights) & ~(@intFromEnum(brd.CastleRights.WhiteKingside) | @intFromEnum(brd.CastleRights.WhiteQueenside)))));
            } else {
                board.updateCastlingRights(@as(brd.CastleRights, @enumFromInt((board.game_state.castling_rights) & ~(@intFromEnum(brd.CastleRights.BlackKingside) | @intFromEnum(brd.CastleRights.BlackQueenside)))));
            }
        } else if (piece_type == brd.Pieces.Rook) {
            if (moving_color == brd.Color.White) {
                @branchHint(.unpredictable);
                if (from_square == @intFromEnum(brd.Squares.a1)) {
                    board.updateCastlingRights(@as(brd.CastleRights, @enumFromInt((board.game_state.castling_rights) & ~@intFromEnum(brd.CastleRights.WhiteQueenside))));
                } else if (from_square == @intFromEnum(brd.Squares.h1)) {
                    board.updateCastlingRights(@as(brd.CastleRights, @enumFromInt((board.game_state.castling_rights) & ~@intFromEnum(brd.CastleRights.WhiteKingside))));
                }
            } else {
                if (from_square == @intFromEnum(brd.Squares.a8)) {
                    board.updateCastlingRights(@as(brd.CastleRights, @enumFromInt((board.game_state.castling_rights) & ~@intFromEnum(brd.CastleRights.BlackQueenside))));
                } else if (from_square == @intFromEnum(brd.Squares.h8)) {
                    board.updateCastlingRights(@as(brd.CastleRights, @enumFromInt((board.game_state.castling_rights) & ~@intFromEnum(brd.CastleRights.BlackKingside))));
                }
            }
        }

        board.clearEnPassantSquare();
    }

    if (moving_color == brd.Color.Black) {
        @branchHint(.unpredictable);
        board.game_state.fullmove_number += 1;
    }

    board.flipSideToMove();
}

pub fn undoMove(board: *Board, move: EncodedMove) void {
    // Restore the previous game state
    if (board.history.history_count > 0) {
        board.history.history_count -= 1;
        const previous_state = board.history.history_list[board.history.history_count];
        board.game_state = previous_state;
    }

    const from_square = move.start_square;
    const to_square = move.end_square;
    const piece_type = @as(brd.Pieces, @enumFromInt(move.piece));
    const side_to_undo = brd.flipColor(board.justMoved());

    // Handle castling
    if (move.castling == 1) {
        @branchHint(.unlikely);
        // Move the king back
        board.movePiece(side_to_undo, brd.Pieces.King, to_square, from_square);

        // Move the rook back
        if (to_square > from_square) {
            // Kingside castling
            const rook_from = if (side_to_undo == brd.Color.White) @as(brd.Square, 5) else @as(brd.Square, 61);
            const rook_to = if (side_to_undo == brd.Color.White) @as(brd.Square, 7) else @as(brd.Square, 63);
            board.movePiece(side_to_undo, brd.Pieces.Rook, rook_from, rook_to);
        } else {
            // Queenside castling
            const rook_from = if (side_to_undo == brd.Color.White) @as(brd.Square, 3) else @as(brd.Square, 59);
            const rook_to = if (side_to_undo == brd.Color.White) @as(brd.Square, 0) else @as(brd.Square, 56);
            board.movePiece(side_to_undo, brd.Pieces.Rook, rook_from, rook_to);
        }
    }
    // Handle en passant
    else if (move.en_passant == 1) {
        @branchHint(.unlikely);
        // Move the pawn back
        board.movePiece(side_to_undo, brd.Pieces.Pawn, to_square, from_square);

        // Restore the captured pawn
        const captured_pawn_square = if (side_to_undo == brd.Color.White) to_square - 8 else to_square + 8;
        board.addPiece(brd.flipColor(side_to_undo), brd.Pieces.Pawn, captured_pawn_square);
    }
    // Handle promotion
    else if (move.promoted_piece != 0) {
        @branchHint(.unlikely);
        // Remove the promoted piece
        const promoted_piece_type = @as(brd.Pieces, @enumFromInt(move.promoted_piece));
        board.removePiece(side_to_undo, promoted_piece_type, to_square);

        // Add the pawn back
        board.addPiece(side_to_undo, brd.Pieces.Pawn, from_square);

        // Restore captured piece if there was one
        if (move.capture == 1) {
            const captured_piece_type = @as(brd.Pieces, @enumFromInt(move.captured_piece));
            board.addPiece(brd.flipColor(side_to_undo), captured_piece_type, to_square);
        }
    }
    // Handle regular moves and captures
    else {
        @branchHint(.likely);
        // Move the piece back
        board.movePiece(side_to_undo, piece_type, to_square, from_square);

        // Restore captured piece if there was one
        if (move.capture == 1) {
            // std.debug.print("Restoring captured piece\n", .{});
            const captured_piece_type = @as(brd.Pieces, @enumFromInt(move.captured_piece));
            board.addPiece(brd.flipColor(side_to_undo), captured_piece_type, to_square);
        }
    }
}
