const std = @import("std");
const root = @import("root.zig");
const brd = root.brd;

const GameState = brd.GameState;
const Position = brd.Position;
const Color = brd.Color;
const Square = brd.Square;

pub const start_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

pub fn parseFEN(gs: *GameState, fen: []const u8) !void {
    var it = std.mem.tokenizeAny(u8, fen, " \t\r\n");

    gs.initInPlace();
    const p = &gs.cur_position;

    const piece_placement = it.next() orelse return error.InvalidFEN;
    try parsePiecePlacement(p, piece_placement);

    for ([_]Color{ .White, .Black }) |c| {
        if (@popCount(p.getPieceColorBoard(.King, c)) != 1) return error.InvalidFEN;
    }
    if (@popCount(p.getOccupancy()) > brd.max_pieces) return error.InvalidFEN;

    const side_to_move = it.next() orelse return error.InvalidFEN;
    if (side_to_move.len != 1) return error.InvalidFEN;
    gs.to_move = switch (side_to_move[0]) {
        'w' => .White,
        'b' => .Black,
        else => return error.InvalidFEN,
    };

    const castling_rights = it.next() orelse return error.InvalidFEN;
    try parseCastlingRights(gs, castling_rights);

    const en_passant = it.next() orelse return error.InvalidFEN;
    try parseEnPassant(p, gs.to_move, en_passant);

    if (it.next()) |halfmove_str| {
        p.halfmove = try std.fmt.parseInt(u8, halfmove_str, 10);
    }
    if (it.next()) |fullmove_str| {
        gs.fullmove = try std.fmt.parseInt(u16, fullmove_str, 10);
    }

    p.reinitZobrist(gs.to_move);
    gs.refreshNNUE();
}

fn parsePiecePlacement(p: *Position, piece_placement: []const u8) !void {
    var rank: u3 = 7;
    var file: u4 = 0;

    for (piece_placement) |char| {
        switch (char) {
            '/' => {
                if (file != 8 or rank == 0) return error.InvalidFEN;
                rank -= 1;
                file = 0;
            },
            '1'...'8' => {
                file += @intCast(char - '0');
                if (file > 8) return error.InvalidFEN;
            },
            else => {
                const pc = brd.Piece.fromChar(char) orelse return error.InvalidFEN;
                if (file >= 8) return error.InvalidFEN;
                p.addPiece(pc.color, pc.piece, brd.squareFromFileRank(@intCast(file), rank));
                file += 1;
            },
        }
    }

    if (rank != 0 or file != 8) return error.InvalidFEN;
}

fn backRank(c: Color) u3 {
    return if (c == .White) 0 else 7;
}

fn setRookFile(gs: *GameState, c: Color, kingside: bool, file: u3) void {
    switch (c) {
        .White => if (kingside) {
            gs.white_ks_rook_file = file;
        } else {
            gs.white_qs_rook_file = file;
        },
        .Black => if (kingside) {
            gs.black_ks_rook_file = file;
        } else {
            gs.black_qs_rook_file = file;
        },
    }
}

fn parseCastlingRights(gs: *GameState, castling_rights: []const u8) !void {
    const p = &gs.cur_position;
    p.castle = 0;

    if (std.mem.eql(u8, castling_rights, "-")) return;

    for (castling_rights) |char| {
        const lower = std.ascii.toLower(char);
        if (lower != 'k' and lower != 'q' and (lower < 'a' or lower > 'h')) return error.InvalidFEN;

        const c: Color = if (std.ascii.isUpper(char)) .White else .Black;
        const king_sq = p.kingSquare(c);
        if (brd.rankOf(king_sq) != backRank(c)) continue;
        const king_file = brd.fileOf(king_sq);

        var kingside: bool = undefined;
        var rook_file: u3 = undefined;
        if (lower == 'k' or lower == 'q') {
            kingside = lower == 'k';
            rook_file = findOuterRookFile(p, c, king_file, kingside) orelse continue;
        } else {
            rook_file = @intCast(lower - 'a');
            if (rook_file == king_file) continue;
            const rook = p.getFromSquare(brd.squareFromFileRank(rook_file, backRank(c)));
            if (rook.piece != .Rook or rook.color != c) continue;
            kingside = rook_file > king_file;
        }

        setRookFile(gs, c, kingside, rook_file);
        p.castle |= @intFromEnum(brd.castleRight(c, kingside));
    }
}

fn findOuterRookFile(p: *const Position, c: Color, king_file: u3, kingside: bool) ?u3 {
    const rank = backRank(c);
    if (kingside) {
        var f: u3 = 7;
        while (f > king_file) : (f -= 1) {
            const pc = p.getFromSquare(brd.squareFromFileRank(f, rank));
            if (pc.piece == .Rook and pc.color == c) return f;
        }
    } else {
        var f: u3 = 0;
        while (f < king_file) : (f += 1) {
            const pc = p.getFromSquare(brd.squareFromFileRank(f, rank));
            if (pc.piece == .Rook and pc.color == c) return f;
        }
    }
    return null;
}

fn parseEnPassant(p: *Position, us: Color, en_passant: []const u8) !void {
    p.ep_sq = null;
    if (std.mem.eql(u8, en_passant, "-")) return;

    const sq = brd.parseSquare(en_passant) orelse return error.InvalidFEN;
    const them = us.opposite();
    if (brd.rankOf(sq) != (if (us == .White) @as(u3, 5) else 2)) return;

    const pushed: Square = if (us == .White) sq - 8 else sq + 8;
    const origin: Square = if (us == .White) sq + 8 else sq - 8;
    const pc = p.getFromSquare(pushed);
    if (pc.piece != .Pawn or pc.color != them) return;
    if (!p.getFromSquare(sq).isNone() or !p.getFromSquare(origin).isNone()) return;

    const pushed_bb = brd.getSquareBB(pushed);
    if (((brd.eastOne(pushed_bb) | brd.westOne(pushed_bb)) & p.getPieceColorBoard(.Pawn, us)) == 0) return;
    p.ep_sq = sq;
}

pub fn toFEN(gs: *const GameState, allocator: std.mem.Allocator) ![]u8 {
    const p = &gs.cur_position;
    var fen = try std.ArrayList(u8).initCapacity(allocator, 96);
    errdefer fen.deinit(allocator);

    var rank: u3 = 7;
    while (true) : (rank -= 1) {
        var empty_count: u8 = 0;
        for (0..brd.num_files) |f| {
            const pc = p.getFromSquare(brd.squareFromFileRank(@intCast(f), rank));
            if (pc.isNone()) {
                empty_count += 1;
                continue;
            }
            if (empty_count > 0) {
                try fen.append(allocator, '0' + empty_count);
                empty_count = 0;
            }
            try fen.append(allocator, pc.toChar());
        }
        if (empty_count > 0) try fen.append(allocator, '0' + empty_count);
        if (rank == 0) break;
        try fen.append(allocator, '/');
    }

    try fen.append(allocator, ' ');
    try fen.append(allocator, if (gs.to_move == .White) 'w' else 'b');

    try fen.append(allocator, ' ');
    if (p.castle == 0) {
        try fen.append(allocator, '-');
    } else {
        for ([_]Color{ .White, .Black }) |c| {
            for ([_]bool{ true, false }) |kingside| {
                if (!brd.hasCastleRight(p.castle, brd.castleRight(c, kingside))) continue;
                const king_file = brd.fileOf(p.kingSquare(c));
                const rook_file = brd.fileOf(gs.rookSquare(c, kingside));
                const standard = king_file == 4 and rook_file == (if (kingside) @as(u3, 7) else 0);
                var ch: u8 = if (standard) (if (kingside) 'k' else 'q') else 'a' + @as(u8, rook_file);
                if (c == .White) ch = std.ascii.toUpper(ch);
                try fen.append(allocator, ch);
            }
        }
    }

    try fen.append(allocator, ' ');
    if (p.ep_sq) |sq| {
        var sq_buf: [2]u8 = undefined;
        try fen.appendSlice(allocator, brd.squareToString(sq, &sq_buf));
    } else {
        try fen.append(allocator, '-');
    }

    var num_buf: [16]u8 = undefined;
    try fen.appendSlice(allocator, try std.fmt.bufPrint(&num_buf, " {d} {d}", .{ p.halfmove, gs.fullmove }));

    return fen.toOwnedSlice(allocator);
}

pub fn setupStartingPosition(gs: *GameState) void {
    parseFEN(gs, start_fen) catch unreachable;
}

pub fn debugPrintBoard(gs: *const GameState) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    var rank: u3 = 7;
    while (true) : (rank -= 1) {
        try stdout.print("{d} ", .{@as(u8, rank) + 1});
        for (0..brd.num_files) |f| {
            const pc = gs.cur_position.getFromSquare(brd.squareFromFileRank(@intCast(f), rank));
            try stdout.print("{c} ", .{pc.toChar()});
        }
        try stdout.print("\n", .{});
        if (rank == 0) break;
    }

    try stdout.print("  a b c d e f g h\n", .{});
    try stdout.print("FEN: ", .{});

    const fen = toFEN(gs, std.heap.page_allocator) catch {
        try stdout.print("<error generating FEN>\n", .{});
        try stdout.flush();
        return;
    };
    defer std.heap.page_allocator.free(fen);

    try stdout.print("{s}\n", .{fen});
    try stdout.flush();
}

pub fn compareFEN(f1: []const u8, f2: []const u8) bool {
    const n = @min(f1.len, f2.len);
    for (0..n) |i| {
        if (f1[i] != f2[i]) {
            std.debug.print("FEN mismatch at index {d}: {c} != {c}\n", .{ i, f1[i], f2[i] });
            return true;
        }
    }
    if (f1.len != f2.len) {
        std.debug.print("FEN length mismatch: {d} != {d}\n", .{ f1.len, f2.len });
        return true;
    }
    return false;
}
