const brd = @import("board");
const mvs = @import("moves");
const std = @import("std");

pub const see_values = [_]i32{
    93, // Pawn
    308, // Knight
    346, // Bishop
    521, // Rook
    994, // Queen
    20000, // King
    0,
};

fn seeSwap(
    board: *brd.Board,
    move_gen: *mvs.MoveGen,
    target_sq: usize,
    attacker_sq: usize,
    attacker_piece: brd.Pieces,
    color_: brd.Color,
    initial_gain: i32,
) i32 {
    var gain: [32]i32 = @splat(0);
    var depth: usize = 0;

    var from_sq = attacker_sq;
    var piece = attacker_piece;
    var color = color_;

    gain[0] = initial_gain;

    var occupied = board.occupancy();
    var attackers = getAllAttackers(board, move_gen, target_sq, occupied);

    while (true) {
        depth += 1;
        if (depth >= 32) break;

        gain[depth] = see_values[@intFromEnum(piece)] - gain[depth - 1];

        // Pruning: if both sides can't improve, stop early
        if (@max(-gain[depth - 1], gain[depth]) < 0) break;

        occupied ^= (@as(u64, 1) << @intCast(from_sq));

        // Discover x-ray attackers behind the piece we just removed
        if (piece == .Pawn or piece == .Bishop or piece == .Queen) {
            attackers |= getBishopXrays(board, move_gen, target_sq, occupied);
        }
        if (piece == .Rook or piece == .Queen) {
            attackers |= getRookXrays(board, move_gen, target_sq, occupied);
        }

        attackers &= occupied;

        color = brd.flipColor(color);

        const next_attacker = getLeastValuableAttacker(board, attackers, color);
        if (next_attacker) |na| {
            from_sq = na.square;
            piece = na.piece;
        } else {
            break;
        }
    }

    var i = depth - 1;
    while (i > 0) : (i -= 1) {
        gain[i - 1] = -@max(-gain[i - 1], gain[i]);
    }

    return gain[0];
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Original capture-only SEE. Kept for backward compatibility with existing
/// call sites (move ordering, qsearch pruning).  Identical behaviour to
/// the old `seeCapture`.
pub fn seeCapture(board: *brd.Board, move_gen: *mvs.MoveGen, move: mvs.EncodedMove) i32 {
    const attacker = board.getPieceFromSquare(move.start_square) orelse return 0;
    const attacker_color = board.getColorFromSquare(move.start_square) orelse return 0;

    // En passant: captured pawn is not on end_square
    if (move.en_passant == 1) {
        return seeSwap(
            board,
            move_gen,
            move.end_square,
            move.start_square,
            attacker,
            attacker_color,
            see_values[@intFromEnum(brd.Pieces.Pawn)],
        );
    }

    const target_piece = board.getPieceFromSquare(move.end_square) orelse return 0;

    return seeSwap(
        board,
        move_gen,
        move.end_square,
        move.start_square,
        attacker,
        attacker_color,
        see_values[@intFromEnum(target_piece)],
    );
}

/// General-purpose SEE for any move (captures AND quiets).
///
/// For captures:  returns the exchange value (same as seeCapture).
/// For quiets:    returns <= 0.  A negative value means the opponent can
///                profitably capture our piece after it lands on end_square.
///                Zero means the square is safe or defended.
///
/// Use this in the main search for SEE pruning of quiet moves:
///   if (see.seeMove(board, move_gen, move) < threshold) continue;
pub fn seeMove(board: *brd.Board, move_gen: *mvs.MoveGen, move: mvs.EncodedMove) i32 {
    const attacker = board.getPieceFromSquare(move.start_square) orelse return 0;
    const attacker_color = board.getColorFromSquare(move.start_square) orelse return 0;

    // En passant
    if (move.en_passant == 1) {
        return seeSwap(
            board,
            move_gen,
            move.end_square,
            move.start_square,
            attacker,
            attacker_color,
            see_values[@intFromEnum(brd.Pieces.Pawn)],
        );
    }

    // Capture: initial gain = value of captured piece
    const target_piece = board.getPieceFromSquare(move.end_square);
    if (target_piece) |tp| {
        return seeSwap(
            board,
            move_gen,
            move.end_square,
            move.start_square,
            attacker,
            attacker_color,
            see_values[@intFromEnum(tp)],
        );
    }

    // Quiet move: initial gain = 0 (we captured nothing).
    // The swap loop will figure out if the opponent can profitably
    // capture our piece on the destination square.
    return seeSwap(
        board,
        move_gen,
        move.end_square,
        move.start_square,
        attacker,
        attacker_color,
        0,
    );
}

/// Threshold-based SEE: returns true if see(move) >= threshold.
///
/// This is functionally equivalent to `seeMove(...) >= threshold` but
/// faster because it can bail out of the swap loop early once it knows
/// the threshold can or cannot be met, without computing the exact value.
///
/// Typical usage in main search:
///   // Prune quiet moves that lose material
///   if (!see.seeAtLeast(board, move_gen, move, -depth * 20)) continue;
///
///   // Prune bad captures
///   if (!see.seeAtLeast(board, move_gen, move, -100)) continue;
pub fn seeAtLeast(board: *brd.Board, move_gen: *mvs.MoveGen, move: mvs.EncodedMove, threshold: i32) bool {
    const attacker = board.getPieceFromSquare(move.start_square) orelse return false;
    const attacker_color = board.getColorFromSquare(move.start_square) orelse return false;

    // Determine initial gain
    var initial_gain: i32 = 0;
    if (move.en_passant == 1) {
        initial_gain = see_values[@intFromEnum(brd.Pieces.Pawn)];
    } else if (board.getPieceFromSquare(move.end_square)) |tp| {
        initial_gain = see_values[@intFromEnum(tp)];
    }

    // After our initial move: we gained initial_gain, and our piece is on
    // target_sq exposed to recapture.  "balance" tracks the running score
    // from the perspective of the initial attacker.
    var balance = initial_gain - threshold;

    // Best case: we captured and opponent can't do better than taking our piece
    // Even if they take our piece, if balance is still >= 0, we pass.
    // (Not needed, but a quick early-out before the loop.)
    if (balance < 0) return false;

    // Worst case: opponent recaptures our piece
    balance -= see_values[@intFromEnum(attacker)];
    // If even after losing our piece we still meet threshold, we pass.
    if (balance >= 0) return true;

    // Now run the swap loop for the remaining attackers
    var occupied = board.occupancy();
    occupied ^= (@as(u64, 1) << @intCast(move.start_square));
    // For en passant, also remove the captured pawn
    if (move.en_passant == 1) {
        // The captured pawn is on the same file as end_square, same rank as start_square
        const ep_sq = @as(usize, move.end_square) ^ 8; // flip rank by 1
        occupied ^= (@as(u64, 1) << @intCast(ep_sq));
    }

    var attackers = getAllAttackers(board, move_gen, move.end_square, occupied);
    attackers &= occupied;
    // Remove the initial attacker (already moved)
    attackers &= ~(@as(u64, 1) << @intCast(move.start_square));

    // Discover x-rays from the initial attacker's removal
    if (attacker == .Pawn or attacker == .Bishop or attacker == .Queen) {
        attackers |= getBishopXrays(board, move_gen, move.end_square, occupied);
        attackers &= occupied;
    }
    if (attacker == .Rook or attacker == .Queen) {
        attackers |= getRookXrays(board, move_gen, move.end_square, occupied);
        attackers &= occupied;
    }

    var color = brd.flipColor(attacker_color); // opponent moves next

    while (true) {
        const next = getLeastValuableAttacker(board, attackers, color);
        if (next == null) break;

        const na = next.?;

        // Remove this attacker from occupied
        occupied ^= (@as(u64, 1) << @intCast(na.square));

        // Discover x-rays
        if (na.piece == .Pawn or na.piece == .Bishop or na.piece == .Queen) {
            attackers |= getBishopXrays(board, move_gen, move.end_square, occupied);
        }
        if (na.piece == .Rook or na.piece == .Queen) {
            attackers |= getRookXrays(board, move_gen, move.end_square, occupied);
        }
        attackers &= occupied;

        color = brd.flipColor(color);

        // Flip perspective: negate and add the value of the piece just captured
        balance = -balance - 1 - see_values[@intFromEnum(na.piece)];

        // If balance >= 0 from the opponent's perspective after this capture,
        // the current side-to-move can stop (stand pat).
        // Since we flipped, balance >= 0 means current mover is happy.
        if (balance >= 0) {
            // The side that just captured "wins" the exchange from here.
            // If that side is the original attacker, threshold is met.
            // If that side is the opponent, threshold is not met.
            // After flipping color, `color` is now the side that would
            // move next, so the side that just captured is `flipColor(color)`.
            // If flipColor(color) == attacker_color, we meet threshold.
            if (brd.flipColor(color) == attacker_color) {
                return true;
            } else {
                return false;
            }
        }
    }

    // Ran out of attackers.  The side that was supposed to move next couldn't
    // recapture.  That means the *previous* capturer wins from here.
    // `color` is the side that ran out of attackers.
    // So flipColor(color) made the last capture and "wins".
    return (brd.flipColor(color) != attacker_color);
}

// ---------------------------------------------------------------------------
// Legacy wrapper — kept so old call sites still compile.
// Prefer seeMove or seeAtLeast for new code.
// ---------------------------------------------------------------------------
pub fn see(board: *brd.Board, move_gen: *mvs.MoveGen, target_sq: usize, attacker_sq: usize, attacker_piece: brd.Pieces) i32 {
    const target_piece = board.getPieceFromSquare(target_sq) orelse return 0;
    const attacker_color = board.getColorFromSquare(attacker_sq) orelse return 0;

    return seeSwap(
        board,
        move_gen,
        target_sq,
        attacker_sq,
        attacker_piece,
        attacker_color,
        see_values[@intFromEnum(target_piece)],
    );
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

const AttackerInfo = struct {
    square: usize,
    piece: brd.Pieces,
};

fn getLeastValuableAttacker(board: *brd.Board, attackers: u64, color: brd.Color) ?AttackerInfo {
    const c_idx = @intFromEnum(color);

    const pieces = [_]brd.Pieces{ .Pawn, .Knight, .Bishop, .Rook, .Queen, .King };

    for (pieces) |piece| {
        const piece_attackers = attackers & board.piece_bb[c_idx][@intFromEnum(piece)];
        if (piece_attackers != 0) {
            return AttackerInfo{
                .square = brd.getLSB(piece_attackers),
                .piece = piece,
            };
        }
    }

    return null;
}

fn getAllAttackers(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64) u64 {
    var attackers: u64 = 0;

    const white_pawn_attacks = if (sq >= 16)
        ((@as(u64, 1) << @intCast(sq - 7)) & ~@as(u64, 0x0101010101010101)) | // left diagonal
            ((@as(u64, 1) << @intCast(sq - 9)) & ~@as(u64, 0x8080808080808080)) // right diagonal
    else
        0;

    const black_pawn_attacks = if (sq < 48)
        ((@as(u64, 1) << @intCast(sq + 7)) & ~@as(u64, 0x8080808080808080)) | // left diagonal
            ((@as(u64, 1) << @intCast(sq + 9)) & ~@as(u64, 0x0101010101010101)) // right diagonal
    else
        0;

    attackers |= white_pawn_attacks & board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Pawn)];
    attackers |= black_pawn_attacks & board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Pawn)];

    // Knight attackers
    const knight_attacks = move_gen.knights[sq];
    attackers |= knight_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Knight)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Knight)]);

    // King attackers
    const king_attacks = move_gen.kings[sq];
    attackers |= king_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.King)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.King)]);

    // Sliding piece attackers
    const bishop_attacks = move_gen.getBishopAttacks(sq, occupied);
    attackers |= bishop_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);

    const rook_attacks = move_gen.getRookAttacks(sq, occupied);
    attackers |= rook_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);

    return attackers;
}

fn getBishopXrays(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64) u64 {
    const bishop_attacks = move_gen.getBishopAttacks(sq, occupied);
    return bishop_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Bishop)] |
        board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);
}

fn getRookXrays(board: *brd.Board, move_gen: *mvs.MoveGen, sq: usize, occupied: u64) u64 {
    const rook_attacks = move_gen.getRookAttacks(sq, occupied);
    return rook_attacks & (board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Rook)] |
        board.piece_bb[@intFromEnum(brd.Color.White)][@intFromEnum(brd.Pieces.Queen)] |
        board.piece_bb[@intFromEnum(brd.Color.Black)][@intFromEnum(brd.Pieces.Queen)]);
}
