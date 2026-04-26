const std = @import("std");
const brd = @import("board");
const Board = brd.Board;
const Bitboard = brd.Bitboard;
const GameState = brd.GameState;
const magic = @import("magic");
const rad = @import("radagast");

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

    pub inline fn toTTKey(self: EncodedMove) u16 {
        var key: u16 = 0;
        key |= @as(u16, self.start_square);
        key |= @as(u16, self.end_square) << 6;

        if (self.castling == 1) {
            key |= @as(u16, 3) << 14;
        } else if (self.en_passant == 1) {
            key |= @as(u16, 2) << 14;
        } else if (self.promoted_piece != 0) {
            key |= @as(u16, @as(u2, @intCast(self.promoted_piece - 1))) << 12;
            key |= @as(u16, 1) << 14;
        }
        return key;
    }

    pub inline fn fromTTKey(key: u16) EncodedMove {
        const from: u6 = @truncate(key);
        const to: u6 = @truncate(key >> 6);
        const promo: u2 = @truncate(key >> 12);
        const mtype: u2 = @truncate(key >> 14);

        var m = EncodedMove{};
        m.start_square = from;
        m.end_square = to;

        switch (mtype) {
            3 => { m.castling = 1; },
            2 => { m.en_passant = 1; m.capture = 1; },
            1 => { m.promoted_piece = @as(u4, promo) + 1; },
            0 => {},
        }

        return m;
    }

    pub inline fn matchesTTKey(self: EncodedMove, other: EncodedMove) bool {
        return self.toTTKey() == other.toTTKey();
    }

    pub fn fromU32(value: u32) EncodedMove {
        return @bitCast(value);
    }

    pub fn toU32(self: EncodedMove) u32 {
        return @bitCast(self);
    }

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

    pub fn uciToString(self: EncodedMove, allocator: std.mem.Allocator) ![]const u8 {
        const start_file: u8 = self.start_square % 8;
        const end_file: u8 = self.end_square % 8;
        const start_rank: u8 = @as(u8, @intCast((self.start_square / 8) + 1));
        const end_rank: u8 = @as(u8, @intCast((self.end_square / 8) + 1));
        const start_file_letter: u8 = 'a' + start_file;
        const end_file_letter: u8 = 'a' + end_file;

        if (self.promoted_piece != 0) {
            const promo = switch (self.promoted_piece) {
                1 => "n",
                2 => "b",
                3 => "r",
                4 => "q",
                else => unreachable,
            };
            return std.fmt.allocPrint(allocator, "{c}{d}{c}{d}{s}", .{ start_file_letter, start_rank, end_file_letter, end_rank, promo });
        }

        return std.fmt.allocPrint(allocator, "{c}{d}{c}{d}", .{ start_file_letter, start_rank, end_file_letter, end_rank });
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
            std.debug.print("={s}", .{promoAbbrev});
        }

        if (self.en_passant == 1) {
            std.debug.print(" e.p.", .{});
        }

        std.debug.print("\n", .{});
    }
};

pub const MoveList = struct {
    items: [218]EncodedMove,
    len: usize = 0,

    pub fn init() MoveList {
        return MoveList{
            .items = undefined,
            .len = 0,
        };
    }

    pub inline fn addEncodedMove(self: *MoveList, move: EncodedMove) void {
        self.items[self.len] = move;
        self.len += 1;
    }

    pub inline fn addMove(self: *MoveList, start: brd.Square, end: brd.Square, piece: brd.Pieces, promoted_piece: ?brd.Pieces, capture: bool, captured_piece: ?brd.Pieces, double_pawn_push: bool, en_passant: bool, castling: bool) void {
        const move = EncodedMove.encode(start, end, piece, promoted_piece, capture, captured_piece, double_pawn_push, en_passant, castling);

        self.items[self.len] = move;
        self.len += 1;
    }

    pub inline fn addEasyMove(self: *MoveList, start: brd.Square, end: brd.Square, piece: brd.Pieces, capture: bool, captured_piece: ?brd.Pieces) void {
        self.addMove(start, end, piece, null, capture, captured_piece, false, false, false);
    }

    pub fn print(self: *MoveList) void {
        for (0..self.len) |i| {
            self.items[i].print();
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
    pinned_by_us: Bitboard = 0,
    pinned_by_them: Bitboard = 0,

    const MoveGenInfo = struct {
        king_sq: brd.Square,
        checkers: Bitboard, 
        check_mask: Bitboard, 
        pin_rays: [64]Bitboard, 
    };

    pub fn init(self: *MoveGen) void {
        self.kings = undefined;
        self.knights = undefined;
        self.pawns = undefined;
        self.bishops = undefined;
        self.rooks = undefined;
        self.bishop_masks = undefined;
        self.rook_masks = undefined;

        self.initKings();
        self.initKnights();
        self.initPawns();
        self.initSliders();
    }

    pub fn generateMoves(self: *MoveGen, board: *Board, comptime move_flag: bool) MoveList {
        var move_list = MoveList.init();
        const color = board.game_state.side_to_move;
        var info = self.computeMoveGenInfo(board);

        self.generateKingMoves(board, &move_list, color, move_flag, &info);

        if (@popCount(info.checkers) < 2) {
            if (color == .White) {
            self.generatePawnMoves(board, &move_list, .White, move_flag, &info);
            }
            else {
                self.generatePawnMoves(board, &move_list, .Black, move_flag, &info);
            }
            self.generateKnightMoves(board, &move_list, color, move_flag, &info);
            self.generateSlideMoves(board, &move_list, color, move_flag, &info);

            if (info.checkers == 0) {
                if (color == .White) {
                    self.generateCastleMoves(board, &move_list, .White);
                }
                else {
                    self.generateCastleMoves(board, &move_list, .Black);
                }
            }
        }

        return move_list;
    }

    pub fn isInCheck(self: *MoveGen, board: *Board, color: brd.Color) bool {
        const king_bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.King)];
        if (king_bb == 0) {
            return false;
        }
        const king_square = brd.getLSB(king_bb);
        if (color == .White) {
            return self.isAttacked(king_square, brd.Color.Black, board);
        }
        else {
            return self.isAttacked(king_square, brd.Color.White, board);
        }
    }

    pub fn generateCaptureMoves(self: *MoveGen, board: *Board, color: brd.Color) MoveList {
        _ = color;
        return self.generateMoves(board, onlyCaptures);
    }

    pub fn generatePawnMoves(self: *MoveGen, board: *Board, move_list: *MoveList, comptime color: brd.Color, comptime move_flag: bool, info: *MoveGenInfo) void {
        const enemy = brd.flipColor(color);
        var bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Pawn)];

        const end_square_update = comptime if (color == .White) @as(isize, 8) else -8;
        const pawn_promo_1 = comptime if (color == .White) @intFromEnum(brd.Squares.a8) else @intFromEnum(brd.Squares.a3);
        const pawn_promo_2 = comptime if (color == .White) @intFromEnum(brd.Squares.h6) else @intFromEnum(brd.Squares.h1);

        while (bb != 0) {
            const start_square = brd.getLSB(bb);
            const pin_ray = info.pin_rays[start_square];
            const legal_mask = info.check_mask & pin_ray;

            const end_sq_signed: isize = @as(isize, @intCast(start_square)) + end_square_update;
            if (!move_flag and end_sq_signed >= 0 and end_sq_signed <= 63) {
                const esq: u64 = @intCast(end_sq_signed);

                if (!brd.getBit(board.occupancy(), esq)) {

                    if (brd.getBit(legal_mask, esq)) {
                        if (start_square < pawn_promo_1 and start_square > pawn_promo_2) {
                            move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Queen, false, null, false, false, false);
                            move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Rook, false, null, false, false, false);
                            move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Bishop, false, null, false, false, false);
                            move_list.addMove(start_square, esq, brd.Pieces.Pawn, brd.Pieces.Knight, false, null, false, false, false);
                        } else {
                            move_list.addEasyMove(start_square, esq, brd.Pieces.Pawn, false, null);
                        }
                    }

                    if (color == brd.Color.White) {
                        if (start_square < @intFromEnum(brd.Squares.a3)) {
                            const dbl: u64 = @intCast(end_sq_signed + 8);
                            if (!brd.getBit(board.occupancy(), dbl) and brd.getBit(legal_mask, dbl)) {
                                move_list.addMove(start_square, dbl, brd.Pieces.Pawn, null, false, null, true, false, false);
                            }
                        }
                    } else {
                        if (start_square > @intFromEnum(brd.Squares.h6)) {
                            const dbl: u64 = @intCast(end_sq_signed - 8);
                            if (!brd.getBit(board.occupancy(), dbl) and brd.getBit(legal_mask, dbl)) {
                                move_list.addMove(start_square, dbl, brd.Pieces.Pawn, null, false, null, true, false, false);
                            }
                        }
                    }
                }
            }

            var attacks = self.pawns[@as(usize, @intFromEnum(color)) * 64 + start_square] &
            board.color_bb[@intFromEnum(enemy)] &
            legal_mask;

            while (attacks != 0) {
                const end_square: brd.Square = brd.getLSB(attacks);
                const captured_piece: ?brd.Pieces = board.getPieceFromSquare(end_square);

                if (start_square < pawn_promo_1 and start_square > pawn_promo_2) {
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Queen, true, captured_piece, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Rook, true, captured_piece, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Bishop, true, captured_piece, false, false, false);
                    move_list.addMove(start_square, end_square, brd.Pieces.Pawn, brd.Pieces.Knight, true, captured_piece, false, false, false);
                } else {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Pawn, true, captured_piece);
                }
                brd.popBit(&attacks, end_square);
            }

            if (board.game_state.en_passant_square != null) {
                const ep_square: brd.Square = board.game_state.en_passant_square.?;
                const ep_attacks = self.pawns[@as(usize, @intFromEnum(color)) * 64 + start_square] &
                brd.getSquareBB(ep_square);

                if (ep_attacks != 0) {
                    const captured_sq: brd.Square = if (color == brd.Color.White) ep_square - 8 else ep_square + 8;

                    const ep_resolves_check = (brd.getSquareBB(ep_square) & info.check_mask != 0) or
                (brd.getSquareBB(captured_sq) & info.check_mask != 0);

                    const ep_respects_pin = brd.getSquareBB(ep_square) & pin_ray != 0;

                    if (ep_resolves_check and ep_respects_pin and
                    self.isEpLegal(board, info.king_sq, start_square, ep_square, color))
                {
                        move_list.addMove(start_square, ep_square, brd.Pieces.Pawn, null, true, brd.Pieces.Pawn, false, true, false);
                    }
                }
            }
            brd.popBit(&bb, start_square);
        }
    }

    pub fn generateKingMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, comptime move_flag: bool, info: *MoveGenInfo) void {
        const enemy = brd.flipColor(color);
        const king_sq = info.king_sq;
        var attacks = self.kings[king_sq] & ~board.color_bb[@intFromEnum(color)];

        const occ_without_king = board.occupancy() ^ brd.getSquareBB(king_sq);

        while (attacks != 0) {
            const end_square = brd.getLSB(attacks);

            if (!self.isAttackedOcc(end_square, enemy, board, occ_without_king)) {
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
                    move_list.addEasyMove(king_sq, end_square, brd.Pieces.King, false, null);
                } else if (brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
                    move_list.addEasyMove(king_sq, end_square, brd.Pieces.King, true, board.getPieceFromSquare(end_square));
                }
            }

            brd.popBit(&attacks, end_square);
        }
    }

    pub fn generateSlideMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, comptime move_flag: bool, info: *MoveGenInfo) void {
        const enemy = brd.flipColor(color);
        var bb: Bitboard = undefined;
        var start_square: brd.Square = undefined;
        var end_square: brd.Square = undefined;
        var attacks: Bitboard = undefined;

        // Bishop moves
        bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Bishop)];
        while (bb != 0) {
            start_square = brd.getLSB(bb);
            attacks = self.getBishopAttacks(start_square, board.occupancy()) &
            ~board.color_bb[@intFromEnum(color)] &
            info.check_mask &
            info.pin_rays[start_square];
            while (attacks != 0) {
                end_square = brd.getLSB(attacks);
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Bishop, false, null);
                } else if (brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
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
            attacks = self.getRookAttacks(start_square, board.occupancy()) &
            ~board.color_bb[@intFromEnum(color)] &
            info.check_mask &
            info.pin_rays[start_square];
            while (attacks != 0) {
                end_square = brd.getLSB(attacks);
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Rook, false, null);
                } else if (brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
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
            attacks = self.getQueenAttacks(start_square, board.occupancy()) &
            ~board.color_bb[@intFromEnum(color)] &
            info.check_mask &
            info.pin_rays[start_square];
            while (attacks != 0) {
                end_square = brd.getLSB(attacks);
                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Queen, false, null);
                } else if (brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Queen, true, board.getPieceFromSquare(end_square));
                }
                brd.popBit(&attacks, end_square);
            }
            brd.popBit(&bb, start_square);
        }
    }

    pub fn generateKnightMoves(self: *MoveGen, board: *Board, move_list: *MoveList, color: brd.Color, comptime move_flag: bool, info: *MoveGenInfo) void {
        const enemy = brd.flipColor(color);
        var bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.Knight)];

        while (bb != 0) {
            const start_square = brd.getLSB(bb);

            if (info.pin_rays[start_square] != ~@as(Bitboard, 0)) {
                brd.popBit(&bb, start_square);
                continue;
            }

            var attacks = self.knights[start_square] & ~board.color_bb[@intFromEnum(color)] & info.check_mask;

            while (attacks != 0) {
                const end_square = brd.getLSB(attacks);

                if (!move_flag and !brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Knight, false, null);
                } else if (brd.getBit(board.color_bb[@intFromEnum(enemy)], end_square)) {
                    move_list.addEasyMove(start_square, end_square, brd.Pieces.Knight, true, board.getPieceFromSquare(end_square));
                }

                brd.popBit(&attacks, end_square);
            }

            brd.popBit(&bb, start_square);
        }
    }

    pub fn generateCastleMoves(self: *MoveGen, board: *Board, move_list: *MoveList, comptime color: brd.Color) void {
        const gs = &board.game_state;
        const king_bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.King)];
        if (king_bb == 0) return;
        const king_sq = brd.getLSB(king_bb);
        const enemy = comptime brd.flipColor(color);
        const occ = board.occupancy();
        // Remove king from occupancy for attack-through-king checks.
        const occ_no_king = occ ^ king_bb;

        // Kingside
        const ks_right = comptime if (color == .White) brd.CastleRights.WhiteKingside else brd.CastleRights.BlackKingside;
        if ((gs.castling_rights & @intFromEnum(ks_right)) != 0) {
            const rook_sq  = gs.rookSquare(color, true);
            const king_dest = brd.GameState.kingCastleDest(color, true);
            const rook_dest = brd.GameState.rookCastleDest(color, true);
            if (self.isCastleLegal(board, king_sq, rook_sq, king_dest, rook_dest, enemy, occ_no_king)) {
                move_list.addMove(king_sq, king_dest, brd.Pieces.King, null, false, null, false, false, true);
            }
        }

        // Queenside
        const qs_right = comptime if (color == .White) brd.CastleRights.WhiteQueenside else brd.CastleRights.BlackQueenside;
        if ((gs.castling_rights & @intFromEnum(qs_right)) != 0) {
            const rook_sq  = gs.rookSquare(color, false);
            const king_dest = brd.GameState.kingCastleDest(color, false);
            const rook_dest = brd.GameState.rookCastleDest(color, false);
            if (self.isCastleLegal(board, king_sq, rook_sq, king_dest, rook_dest, enemy, occ_no_king)) {
                move_list.addMove(king_sq, king_dest, brd.Pieces.King, null, false, null, false, false, true);
            }
        }
    }

    fn isCastleLegal(
        self: *MoveGen,
        board: *Board,
        king_sq: brd.Square,
        rook_sq: brd.Square,
        king_dest: brd.Square,
        rook_dest: brd.Square,
        enemy: brd.Color,
        occ_no_king: Bitboard,
    ) bool {
        const king_bb = brd.getSquareBB(king_sq);
        const rook_bb = brd.getSquareBB(rook_sq);

        const span_kr    = rankSpan(king_sq, rook_sq);
        const span_rdest = rankSpan(rook_sq, rook_dest);
        const dests      = brd.getSquareBB(king_dest) | brd.getSquareBB(rook_dest);
        const must_be_empty = (span_kr | span_rdest | dests) & ~king_bb & ~rook_bb;

        // Check those squares against occupancy (excluding both king and rook).
        const occ_no_king_rook = occ_no_king & ~rook_bb;
        if (must_be_empty & occ_no_king_rook != 0) return false;

        // King must not pass through, or land on, an attacked square.
        var king_path = rankSpan(king_sq, king_dest);
        while (king_path != 0) {
            const sq = brd.getLSB(king_path);
            if (self.isAttackedOcc(sq, enemy, board, occ_no_king)) return false;
            brd.popBit(&king_path, sq);
        }

        return true;
    }

    /// Returns a bitboard covering every square from lo to hi (inclusive) on the same rank.
    inline fn rankSpan(sq1: brd.Square, sq2: brd.Square) Bitboard {
        const lo = @min(sq1, sq2);
        const hi = @max(sq1, sq2);
        return ((@as(Bitboard, 2) << @intCast(hi)) -% 1) & ~((@as(Bitboard, 1) << @intCast(lo)) -% 1);
    }

    pub inline fn isAttacked(self: *MoveGen, sq: brd.Square, comptime color: brd.Color, board: *Board) bool {
        if (sq > 63) {
            return false;
        }

        const op_color = comptime brd.flipColor(color);

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

    pub inline fn isAttackedOcc(self: *MoveGen, sq: brd.Square, by_color: brd.Color, board: *Board, occ: Bitboard) bool {
        if (sq > 63) return false;
        const op_color = brd.flipColor(by_color);

        if (self.knights[sq] & board.piece_bb[@intFromEnum(by_color)][@intFromEnum(brd.Pieces.Knight)] != 0)
        return true;
        if (self.pawns[@as(usize, @intFromEnum(op_color)) * 64 + sq] & board.piece_bb[@intFromEnum(by_color)][@intFromEnum(brd.Pieces.Pawn)] != 0)
        return true;

        const enemy_bq = board.piece_bb[@intFromEnum(by_color)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(by_color)][@intFromEnum(brd.Pieces.Queen)];
        if (self.getBishopAttacks(sq, occ) & enemy_bq != 0)
        return true;

        const enemy_rq = board.piece_bb[@intFromEnum(by_color)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(by_color)][@intFromEnum(brd.Pieces.Queen)];
        if (self.getRookAttacks(sq, occ) & enemy_rq != 0)
        return true;

        if (self.kings[sq] & board.piece_bb[@intFromEnum(by_color)][@intFromEnum(brd.Pieces.King)] != 0)
        return true;

        return false;
    }

    pub inline fn betweenSquares(self: *MoveGen, sq1: brd.Square, sq2: brd.Square) Bitboard {
        const b1 = brd.getSquareBB(sq1);
        const b2 = brd.getSquareBB(sq2);

        const r1 = sq1 / 8;
        const f1 = sq1 % 8;
        const r2 = sq2 / 8;
        const f2 = sq2 % 8;

        if (r1 == r2 or f1 == f2) {
            return self.getRookAttacks(sq1, b2) & self.getRookAttacks(sq2, b1);
        }

        const rd: usize = if (r1 > r2) r1 - r2 else r2 - r1;
        const fd: usize = if (f1 > f2) f1 - f2 else f2 - f1;
        if (rd == fd) {
            return self.getBishopAttacks(sq1, b2) & self.getBishopAttacks(sq2, b1);
        }

        return 0;
    }

    fn isEpLegal(self: *MoveGen, board: *Board, king_sq: brd.Square, from: brd.Square, ep_sq: brd.Square, color: brd.Color) bool {
        const enemy = brd.flipColor(color);
        const captured_sq: brd.Square = if (color == brd.Color.White)
            ep_sq - 8
            else
            ep_sq + 8;

        var occ = board.occupancy();
        occ ^= brd.getSquareBB(from); 
        occ ^= brd.getSquareBB(captured_sq); 
        occ |= brd.getSquareBB(ep_sq); 

        const enemy_bq = board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Queen)];
        const enemy_rq = board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Queen)];

        if (self.getBishopAttacks(king_sq, occ) & enemy_bq != 0) return false;
        if (self.getRookAttacks(king_sq, occ) & enemy_rq != 0) return false;
        return true;
    }

    fn computeMoveGenInfo(self: *MoveGen, board: *Board) MoveGenInfo {
        const color = board.game_state.side_to_move;
        const enemy = brd.flipColor(color);
        const king_bb = board.piece_bb[@intFromEnum(color)][@intFromEnum(brd.Pieces.King)];
        const king_sq = brd.getLSB(king_bb);
        const occ = board.occupancy();
        const our_pieces = board.color_bb[@intFromEnum(color)];

        if (king_bb == 0) {
            return MoveGenInfo{
                .king_sq = 0,
                .checkers = 0,
                .check_mask = 0,
                .pin_rays = [_]Bitboard{~@as(Bitboard, 0)} ** 64,
            };
        }

        var checkers: Bitboard = 0;
        checkers |= self.knights[king_sq] &
        board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Knight)];
        checkers |= self.pawns[@as(usize, @intFromEnum(color)) * 64 + king_sq] &
        board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Pawn)];

        const enemy_bq = board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Queen)];
        const enemy_rq = board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(enemy)][@intFromEnum(brd.Pieces.Queen)];

        checkers |= self.getBishopAttacks(king_sq, occ) & enemy_bq;
        checkers |= self.getRookAttacks(king_sq, occ) & enemy_rq;

        var check_mask: Bitboard = ~@as(Bitboard, 0); 
        const num_checkers = @popCount(checkers);

        if (num_checkers == 0) {
            check_mask = ~@as(Bitboard, 0); 
        } else if (num_checkers == 1) {
            const checker_sq = brd.getLSB(checkers);
            check_mask = brd.getSquareBB(checker_sq);
            if (brd.getSquareBB(checker_sq) & (enemy_bq | enemy_rq) != 0) {
                check_mask |= self.betweenSquares(king_sq, checker_sq);
            }
        } else {
            check_mask = 0;
        }

        var pin_rays = [_]Bitboard{~@as(Bitboard, 0)} ** 64;

        const our_on_rook_ray = our_pieces & self.getRookAttacks(king_sq, occ);
        const rook_xray = self.getRookAttacks(king_sq, occ ^ our_on_rook_ray);
        var pinners_hv = rook_xray & enemy_rq;
        while (pinners_hv != 0) {
            const pinner_sq = brd.getLSB(pinners_hv);
            const ray = self.betweenSquares(king_sq, pinner_sq);
            const pinned = ray & our_pieces;
            if (@popCount(pinned) == 1) {
                const pinned_sq = brd.getLSB(pinned);
                pin_rays[pinned_sq] = ray | brd.getSquareBB(pinner_sq);
            }
            brd.popBit(&pinners_hv, pinner_sq);
        }

        const our_on_bishop_ray = our_pieces & self.getBishopAttacks(king_sq, occ);
        const bishop_xray = self.getBishopAttacks(king_sq, occ ^ our_on_bishop_ray);
        var pinners_d = bishop_xray & enemy_bq;
        while (pinners_d != 0) {
            const pinner_sq = brd.getLSB(pinners_d);
            const ray = self.betweenSquares(king_sq, pinner_sq);
            const pinned = ray & our_pieces;
            if (@popCount(pinned) == 1) {
                const pinned_sq = brd.getLSB(pinned);
                pin_rays[pinned_sq] = ray | brd.getSquareBB(pinner_sq);
            }
            brd.popBit(&pinners_d, pinner_sq);
        }

        return MoveGenInfo{
            .king_sq = king_sq,
            .checkers = checkers,
            .check_mask = check_mask,
            .pin_rays = pin_rays,
        };
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
            self.pawns[sq] = pawnAttacks(sq, brd.Color.White);
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

pub fn makeMove(board: *Board, move: EncodedMove) void {
    board.nnue_stack.pushAndUpdate(board, move);

    board.history.addToHistory(board.game_state);

    const from_square = @as(brd.Square, @intCast(move.start_square));
    const to_square = @as(brd.Square, @intCast(move.end_square));
    const piece_type = @as(brd.Pieces, @enumFromInt(move.piece));
    const moving_color = board.toMove();

    if (piece_type != brd.Pieces.Pawn and move.capture == 0) {
        board.game_state.halfmove_clock += 1;
    } else {
        board.game_state.halfmove_clock = 0;
    }

    if (move.castling == 1) {
        // to_square is the king's destination (g-file=6 for KS, c-file=2 for QS).
        const kingside = (to_square % 8) == 6;
        const rook_sq   = board.game_state.rookSquare(moving_color, kingside);
        const rook_dest = brd.GameState.rookCastleDest(moving_color, kingside);

        // Remove both pieces first to avoid overlap issues (Chess960 safe).
        board.removePiece(moving_color, brd.Pieces.King, from_square);
        board.removePiece(moving_color, brd.Pieces.Rook, rook_sq);
        board.addPiece(moving_color, brd.Pieces.King, to_square);
        board.addPiece(moving_color, brd.Pieces.Rook, rook_dest);

        if (moving_color == brd.Color.White) {
            board.removeCastlingRights(brd.CastleRights.WhiteKingside);
            board.removeCastlingRights(brd.CastleRights.WhiteQueenside);
        } else {
            board.removeCastlingRights(brd.CastleRights.BlackKingside);
            board.removeCastlingRights(brd.CastleRights.BlackQueenside);
        }
        board.clearEnPassantSquare();
    }
    else if (move.double_pawn_push == 1) {
        board.movePiece(moving_color, piece_type, from_square, to_square);

        var enemy_adjacent = false;
        const enemy_color = brd.flipColor(moving_color);
        const enemy_pawns = board.piece_bb[@intFromEnum(enemy_color)][@intFromEnum(brd.Pieces.Pawn)];
        const file = to_square % 8;

        if (file > 0 and brd.getBit(enemy_pawns, to_square - 1)) {
            enemy_adjacent = true;
        }
        if (file < 7 and brd.getBit(enemy_pawns, to_square + 1)) {
            enemy_adjacent = true;
        }

        if (enemy_adjacent) {
            const ep_square = if (moving_color == brd.Color.White) to_square - 8 else to_square + 8;
            board.setEnPassantSquare(@intCast(ep_square));
        } else {
            board.clearEnPassantSquare();
        }
    }
    else if (move.en_passant == 1) {
        board.movePiece(moving_color, brd.Pieces.Pawn, from_square, to_square);

        const captured_pawn_square = if (moving_color == brd.Color.White) to_square - 8 else to_square + 8;
        board.removePiece(brd.flipColor(moving_color), brd.Pieces.Pawn, captured_pawn_square);

        board.clearEnPassantSquare();
    }
    else if (move.promoted_piece != 0) {
        board.removePiece(moving_color, brd.Pieces.Pawn, from_square);
        const promoted_piece_type = @as(brd.Pieces, @enumFromInt(move.promoted_piece));

        if (move.capture == 1) {
            const captured_piece_type = @as(brd.Pieces, @enumFromInt(move.captured_piece));
            board.removePiece(brd.flipColor(moving_color), captured_piece_type, to_square);
        }

        board.addPiece(moving_color, promoted_piece_type, to_square);

        board.clearEnPassantSquare();
    }
    else {
        if (move.capture == 1) {
            const captured_piece_type = @as(brd.Pieces, @enumFromInt(move.captured_piece));
            board.removePiece(brd.flipColor(moving_color), captured_piece_type, to_square);
        }

        board.movePiece(moving_color, piece_type, from_square, to_square);

        if (piece_type == brd.Pieces.King) {
            if (moving_color == brd.Color.White) {
                board.removeCastlingRights(brd.CastleRights.WhiteKingside);
                board.removeCastlingRights(brd.CastleRights.WhiteQueenside);
            } else {
                board.removeCastlingRights(brd.CastleRights.BlackKingside);
                board.removeCastlingRights(brd.CastleRights.BlackQueenside);
            }
        } else if (piece_type == brd.Pieces.Rook) {
            if (moving_color == brd.Color.White) {
                if (from_square == board.game_state.rookSquare(.White, false)) {
                    board.removeCastlingRights(brd.CastleRights.WhiteQueenside);
                } else if (from_square == board.game_state.rookSquare(.White, true)) {
                    board.removeCastlingRights(brd.CastleRights.WhiteKingside);
                }
            } else {
                if (from_square == board.game_state.rookSquare(.Black, false)) {
                    board.removeCastlingRights(brd.CastleRights.BlackQueenside);
                } else if (from_square == board.game_state.rookSquare(.Black, true)) {
                    board.removeCastlingRights(brd.CastleRights.BlackKingside);
                }
            }
        }

        board.clearEnPassantSquare();
    }

    if (to_square == board.game_state.rookSquare(.White, false)) {
        board.removeCastlingRights(brd.CastleRights.WhiteQueenside);
    } else if (to_square == board.game_state.rookSquare(.White, true)) {
        board.removeCastlingRights(brd.CastleRights.WhiteKingside);
    } else if (to_square == board.game_state.rookSquare(.Black, false)) {
        board.removeCastlingRights(brd.CastleRights.BlackQueenside);
    } else if (to_square == board.game_state.rookSquare(.Black, true)) {
        board.removeCastlingRights(brd.CastleRights.BlackKingside);
    }

    if (moving_color == brd.Color.Black) {
        board.game_state.fullmove_number += 1;
    }

    board.flipSideToMove();
}

pub fn undoMove(board: *Board, move: EncodedMove) void {
    board.nnue_stack.pop();

    const from_square = move.start_square;
    const to_square = move.end_square;
    const piece_type = @as(brd.Pieces, @enumFromInt(move.piece));
    const side_to_undo = board.justMoved();

    if (move.castling == 1) {
        // to_square is the king's castled destination.
        const kingside = (to_square % 8) == 6;
        const rook_sq   = board.game_state.rookSquare(side_to_undo, kingside);
        const rook_dest = brd.GameState.rookCastleDest(side_to_undo, kingside);

        // Remove both pieces first (safe for Chess960 overlapping squares).
        board.removePiece(side_to_undo, brd.Pieces.King, to_square);
        board.removePiece(side_to_undo, brd.Pieces.Rook, rook_dest);
        board.addPiece(side_to_undo, brd.Pieces.King, from_square);
        board.addPiece(side_to_undo, brd.Pieces.Rook, rook_sq);
    }
    else if (move.en_passant == 1) {
        board.movePiece(side_to_undo, brd.Pieces.Pawn, to_square, from_square);

        const captured_pawn_square = if (side_to_undo == brd.Color.White) to_square - 8 else to_square + 8;
        board.addPiece(brd.flipColor(side_to_undo), brd.Pieces.Pawn, captured_pawn_square);
    }
    else if (move.promoted_piece != 0) {
        const promoted_piece_type = @as(brd.Pieces, @enumFromInt(move.promoted_piece));
        board.removePiece(side_to_undo, promoted_piece_type, to_square);

        board.addPiece(side_to_undo, brd.Pieces.Pawn, from_square);

        if (move.capture == 1) {
            const captured_piece_type = @as(brd.Pieces, @enumFromInt(move.captured_piece));
            board.addPiece(brd.flipColor(side_to_undo), captured_piece_type, to_square);
        }
    }
    else {
        board.movePiece(side_to_undo, piece_type, to_square, from_square);

        if (move.capture == 1) {
            const captured_piece_type = @as(brd.Pieces, @enumFromInt(move.captured_piece));
            board.addPiece(brd.flipColor(side_to_undo), captured_piece_type, to_square);
        }
    }

    if (board.history.history_count > 0) {
        board.history.history_count -= 1;
        const previous_state = board.history.history_list[board.history.history_count];
        board.game_state = previous_state;
    }
}

pub fn parseMove(board: *brd.Board, moveStr: []const u8) ?EncodedMove {
    if (moveStr.len < 4) return null;

    const from = parseSquare(moveStr[0..2]) orelse return null;
    const to = parseSquare(moveStr[2..4]) orelse return null;

    const color = board.game_state.side_to_move;
    const fromBB = brd.getSquareBB(from);
    var piece: usize = undefined;
    inline for (0..6) |i| {
        if (board.piece_bb[@intFromEnum(color)][i] & fromBB != 0) {
            piece = i;
            break;
        }
    } else return null;

    const op_color = brd.flipColor(color);
    const toBB = brd.getSquareBB(to);
    var capture = (board.color_bb[@intFromEnum(op_color)] & toBB) != 0;
    var captured_piece: u4 = 0;

    const en_passant = (piece == 0) and
(board.game_state.en_passant_square != null) and
(to == board.game_state.en_passant_square.?);
    if (en_passant) {
        capture = true;
        captured_piece = 0;
    }

    if (capture and !en_passant) {
        inline for (0..6) |i| {
            if (board.piece_bb[@intFromEnum(op_color)][i] & toBB != 0) {
                captured_piece = @intCast(i);
                break;
            }
        } else return null;
    }

    var promoted_piece: u4 = 0;
    if (moveStr.len == 5) {
        promoted_piece = switch (moveStr[4]) {
            'q' => 4,
            'r' => 3,
            'b' => 2,
            'n' => 1,
            else => return null,
        };
    }

    var actual_to = to;
    const king_sq_val = from; 
    _ = king_sq_val;

    const ks_right: brd.CastleRights = if (color == .White) brd.CastleRights.WhiteKingside else brd.CastleRights.BlackKingside;
    const qs_right: brd.CastleRights = if (color == .White) brd.CastleRights.WhiteQueenside else brd.CastleRights.BlackQueenside;
    const has_ks = (board.game_state.castling_rights & @intFromEnum(ks_right)) != 0;
    const has_qs = (board.game_state.castling_rights & @intFromEnum(qs_right)) != 0;

    // Check if king is moving to a friendly rook square (UCI_Chess960 encoding).
    const rook_sq_ks = board.game_state.rookSquare(color, true);
    const rook_sq_qs = board.game_state.rookSquare(color, false);
    if (piece == 5 and has_ks and to == rook_sq_ks) {
        actual_to = brd.GameState.kingCastleDest(color, true);
    } else if (piece == 5 and has_qs and to == rook_sq_qs) {
        actual_to = brd.GameState.kingCastleDest(color, false);
    }

    const king_dest_ks = brd.GameState.kingCastleDest(color, true);
    const king_dest_qs = brd.GameState.kingCastleDest(color, false);
    const castling = (piece == 5) and
        ((has_ks and actual_to == king_dest_ks) or (has_qs and actual_to == king_dest_qs));

    const rank_from = (from) / 8;
    const double_pawn_push = (piece == 0) and
((color == .White and rank_from == 1 and (to) / 8 == 3) or
(color == .Black and rank_from == 6 and (to) / 8 == 4));

    return EncodedMove{
        .start_square = @intCast(from),
        .end_square = @intCast(actual_to),
        .piece = @intCast(piece),
        .promoted_piece = promoted_piece,
        .capture = @intFromBool(capture),
        .captured_piece = captured_piece,
        .double_pawn_push = @intFromBool(double_pawn_push),
        .en_passant = @intFromBool(en_passant),
        .castling = @intFromBool(castling),
    };
}

fn parseSquare(squareStr: []const u8) ?brd.Square {
    if (squareStr.len != 2) {
        return null;
    }

    const file = squareStr[0];
    const rank = squareStr[1];

    if (file < 'a' or file > 'h' or rank < '1' or rank > '8') {
        return null;
    }

    return (file - 'a') + (rank - '1') * 8;
}
