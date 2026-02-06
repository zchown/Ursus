const std = @import("std");
const zob = @import("zobrist");
const brd = @import("board");
const Board = brd.Board;

pub fn parseFEN(board: *Board, fen: []const u8) !void {
    var it = std.mem.tokenizeAny(u8, fen, " ");

    board.* = Board.init();

    const piece_placement = it.next() orelse return error.InvalidFEN;
    try parsePiecePlacement(board, piece_placement);

    const side_to_move = it.next() orelse return error.InvalidFEN;
    if (side_to_move.len != 1) return error.InvalidFEN;
    board.game_state.side_to_move = switch (side_to_move[0]) {
        'w' => brd.Color.White,
        'b' => brd.Color.Black,
        else => return error.InvalidFEN,
    };

    const castling_rights = it.next() orelse return error.InvalidFEN;
    try parseCastlingRights(board, castling_rights);

    const en_passant = it.next() orelse return error.InvalidFEN;
    try parseEnPassant(board, en_passant);

    const halfmove_str = it.next() orelse return error.InvalidFEN;
    board.game_state.halfmove_clock = try std.fmt.parseInt(u8, halfmove_str, 10);

    const fullmove_str = it.next() orelse return error.InvalidFEN;
    board.game_state.fullmove_number = try std.fmt.parseInt(u16, fullmove_str, 10);

    board.reinitZobrist();

    return;
}

fn parsePiecePlacement(board: *Board, piece_placement: []const u8) !void {
    var rank: usize = 7;
    var file: usize = 0;

    for (piece_placement) |char| {
        switch (char) {
            '/' => {
                if (file != 8) return error.InvalidFEN;
                rank -= 1;
                file = 0;
                if (rank >= 8) return error.InvalidFEN;
            },
            '1'...'8' => {
                const empty_squares = char - '0';
                file += empty_squares;
                if (file > 8) return error.InvalidFEN;
            },
            'P', 'N', 'B', 'R', 'Q', 'K', 'p', 'n', 'b', 'r', 'q', 'k' => {
                if (file >= 8 or rank >= 8) return error.InvalidFEN;

                const color = if (std.ascii.isUpper(char)) brd.Color.White else brd.Color.Black;
                const piece_char = if (std.ascii.isUpper(char)) char else std.ascii.toUpper(char);

                const piece = switch (piece_char) {
                    'P' => brd.Pieces.Pawn,
                    'N' => brd.Pieces.Knight,
                    'B' => brd.Pieces.Bishop,
                    'R' => brd.Pieces.Rook,
                    'Q' => brd.Pieces.Queen,
                    'K' => brd.Pieces.King,
                    else => unreachable,
                };

                const square: usize = rank * 8 + file;
                board.addPiece(color, piece, square);

                file += 1;
            },
            else => return error.InvalidFEN,
        }
    }

    if (rank != 0 or file != 8) return error.InvalidFEN;
}

fn parseCastlingRights(board: *Board, castling_rights: []const u8) !void {
    board.game_state.zobrist ^= zob.ZobristKeys.castleKeys(board.game_state.castling_rights);
    board.game_state.castling_rights = 0;

    if (std.mem.eql(u8, castling_rights, "-")) {
        return;
    }

    for (castling_rights) |char| {
        switch (char) {
            'K' => {
                board.addCastlingRights(brd.CastleRights.WhiteKingside);
            },
            'Q' => {
                board.addCastlingRights(brd.CastleRights.WhiteQueenside);
            },
            'k' => {
                board.addCastlingRights(brd.CastleRights.BlackKingside);
            },
            'q' => {
                board.addCastlingRights(brd.CastleRights.BlackQueenside);
            },
            else => return error.InvalidFEN,
        }
    }
}

fn parseEnPassant(board: *Board, en_passant: []const u8) !void {
    if (std.mem.eql(u8, en_passant, "-")) {
        board.setEnPassantSquare(null);
        return;
    }

    if (en_passant.len != 2) return error.InvalidFEN;

    const file = en_passant[0] - 'a';
    const rank = en_passant[1] - '1';

    if (file >= 8 or rank >= 8) return error.InvalidFEN;

    const square: brd.Square = @intCast(rank * 8 + file);
    board.setEnPassantSquare(@intCast(square));
}

pub fn toFEN(board: *Board, allocator: std.mem.Allocator) ![]u8 {
    var fen = try std.ArrayList(u8).initCapacity(allocator, 256);
    defer fen.deinit(allocator);

    for (0..8) |rank_idx| {
        const rank = 7 - rank_idx;
        var empty_count: u8 = 0;

        for (0..8) |file| {
            const square = rank * 8 + file;
            var found_piece = false;

            for (0..brd.num_colors) |color_idx| {
                const color: brd.Color = @enumFromInt(color_idx);
                for (0..brd.num_pieces) |piece_idx| {
                    const piece: brd.Pieces = @enumFromInt(piece_idx);
                    if ((board.getPieces(color, piece) & (@as(u64, 1) << @intCast(square))) != 0) {
                        if (empty_count > 0) {
                            try fen.append(allocator, '0' + empty_count);
                            empty_count = 0;
                        }

                        var piece_char: u8 = switch (piece) {
                            brd.Pieces.Pawn => 'P',
                            brd.Pieces.Knight => 'N',
                            brd.Pieces.Bishop => 'B',
                            brd.Pieces.Rook => 'R',
                            brd.Pieces.Queen => 'Q',
                            brd.Pieces.King => 'K',
                            brd.Pieces.None => '.',
                        };

                        if (color == brd.Color.Black) {
                            piece_char = std.ascii.toLower(piece_char);
                        }

                        if (piece != brd.Pieces.None) {
                            try fen.append(allocator, piece_char);
                        }
                        found_piece = true;
                        break;
                    }
                }
                if (found_piece) break;
            }

            if (!found_piece) {
                empty_count += 1;
            }
        }

        if (empty_count > 0) {
            try fen.append(allocator, '0' + empty_count);
        }

        if (rank_idx < 7) {
            try fen.append(allocator, '/');
        }
    }

    try fen.append(allocator, ' ');
    try fen.append(allocator, if (board.game_state.side_to_move == brd.Color.White) 'w' else 'b');

    try fen.append(allocator, ' ');
    var has_castling_rights = false;

    if ((board.game_state.castling_rights) &
        @intFromEnum(brd.CastleRights.WhiteKingside) != 0)
    {
        try fen.append(allocator, 'K');
        has_castling_rights = true;
    }
    if ((board.game_state.castling_rights) & @intFromEnum(brd.CastleRights.WhiteQueenside) != 0) {
        try fen.append(allocator, 'Q');
        has_castling_rights = true;
    }
    if ((board.game_state.castling_rights) & @intFromEnum(brd.CastleRights.BlackKingside) != 0) {
        try fen.append(allocator, 'k');
        has_castling_rights = true;
    }
    if ((board.game_state.castling_rights) & @intFromEnum(brd.CastleRights.BlackQueenside) != 0) {
        try fen.append(allocator, 'q');
        has_castling_rights = true;
    }

    if (!has_castling_rights) {
        try fen.append(allocator, '-');
    }

    try fen.append(allocator, ' ');
    if (board.game_state.en_passant_square) |square| {
        const file: u8 = square % 8;
        const rank: u8 = square / 8;
        try fen.append(allocator, 'a' + file);
        try fen.append(allocator, '1' + rank);
    } else {
        try fen.append(allocator, '-');
    }

    try fen.append(allocator, ' ');
    try std.fmt.format(fen.writer(allocator), "{d}", .{board.game_state.halfmove_clock});

    try fen.append(allocator, ' ');
    try std.fmt.format(fen.writer(allocator), "{d}", .{board.game_state.fullmove_number});

    return fen.toOwnedSlice(allocator);
}

pub fn setupStartingPosition(board: *Board) void {
    _ = parseFEN(board, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") catch {};
}

pub fn debugPrintBoard(board: *Board) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    for (0..8) |rank_idx| {
        const rank = 7 - rank_idx;
        try stdout.print("{d} ", .{rank + 1});

        for (0..8) |file| {
            const square = rank * 8 + file;
            var printed = false;

            for (0..brd.num_colors) |color_idx| {
                const color: brd.Color = @enumFromInt(color_idx);
                for (0..brd.num_pieces) |piece_idx| {
                    const piece: brd.Pieces = @enumFromInt(piece_idx);
                    if ((board.getPieces(color, piece) & (@as(u64, 1) << @intCast(square))) != 0) {
                        var piece_char: u8 = switch (piece) {
                            brd.Pieces.Pawn => 'P',
                            brd.Pieces.Knight => 'N',
                            brd.Pieces.Bishop => 'B',
                            brd.Pieces.Rook => 'R',
                            brd.Pieces.Queen => 'Q',
                            brd.Pieces.King => 'K',
                            brd.Pieces.None => '.',
                        };

                        if (color == brd.Color.Black) {
                            piece_char = std.ascii.toLower(piece_char);
                        }

                        if (piece != brd.Pieces.None) {
                            try stdout.print("{c} ", .{piece_char});
                            printed = true;
                        }
                        break;
                    }
                }
                if (printed) break;
            }

            if (!printed) {
                try stdout.print(". ", .{});
            }
        }

        try stdout.print("\n", .{});
    }

    try stdout.print("  a b c d e f g h\n", .{});
    try stdout.print("FEN: ", .{});

    const fen = toFEN(board, std.heap.page_allocator) catch {
        try stdout.print("<error generating FEN>\n", .{});
        try stdout_writer.interface.flush();
        return;
    };
    defer std.heap.page_allocator.free(fen);

    try stdout.print("{s}\n", .{fen});
    try stdout_writer.interface.flush();
}


pub fn compareFEN(f1: []u8, f2: []u8) bool {
    for (0..f1.len) |i| {
        if (i >= f2.len or f1[i] != f2[i]) {
            std.debug.print("FEN mismatch at index {d}: {c} != {c}\n", .{ i, f1[i], f2[i] });
            return true;
        }
    }
    return false;
}
