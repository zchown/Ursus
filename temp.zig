fn evalPawnsForColor(board: *brd.Board, color: brd.Color, phase: i32) PawnEval {
    const c_idx = @intFromEnum(color);
    const opp_idx = 1 - c_idx;
    var result = PawnEval{ .mg = 0, .eg = 0 };

    const our_pawns = board.piece_bb[c_idx][@intFromEnum(brd.Pieces.Pawn)];
    const opp_pawns = board.piece_bb[opp_idx][@intFromEnum(brd.Pieces.Pawn)];
    
    // Count pawns per file for doubled pawn detection
    var file_counts = [_]u8{0} ** 8;
    var temp_bb = our_pawns;
    while (temp_bb != 0) {
        const sq = brd.getLSB(temp_bb);
        const file = @mod(sq, 8);
        file_counts[file] += 1;
        brd.popBit(&temp_bb, sq);
    }
    
    // Evaluate each pawn
    temp_bb = our_pawns;
    while (temp_bb != 0) {
        const sq = brd.getLSB(temp_bb);
        const file = @mod(sq, 8);
        const rank = @divTrunc(sq, 8);
        const relative_rank: usize = if (color == brd.Color.White) rank else 7 - rank;

        // Shared masks
        const left_mask: u64 = if (file > 0) @as(u64, 0x0101010101010101) << @intCast(file - 1) else 0;
        const right_mask: u64 = if (file < 7) @as(u64, 0x0101010101010101) << @intCast(file + 1) else 0;
        const adjacent_files = left_mask | right_mask;

        // [NEW] Connected Pawn Logic
        // Checks if there is a friendly pawn on an adjacent file on the same, previous, or next rank.
        const is_connected = blk: {
            const rank_mask: u64 = @as(u64, 0xFF) << @intCast(rank * 8);
            const prev_rank_mask: u64 = if (rank > 0) @as(u64, 0xFF) << @intCast((rank - 1) * 8) else 0;
            const next_rank_mask: u64 = if (rank < 7) @as(u64, 0xFF) << @intCast((rank + 1) * 8) else 0;
            const proximity_mask = rank_mask | prev_rank_mask | next_rank_mask;
            
            break :blk (our_pawns & adjacent_files & proximity_mask) != 0;
        };

        if (is_connected) {
            // Bonus increases slightly as pawns advance
            const bonus = connected_pawn_bonus + @as(i32, @intCast(relative_rank)); 
            result.mg += bonus;
            result.eg += bonus * 2; // Connected pawns are stronger in endgame
        }

        // [NEW] Backward Pawn Logic
        // 1. No friendly pawns behind or on the same rank on adjacent files (cannot be supported).
        // 2. Stop square is controlled by an enemy pawn.
        const is_backward = blk: {
            // Check for support availability
            const support_mask: u64 = if (color == brd.Color.White)
                // White: check ranks 0 through `rank`
                 ~(@as(u64, 0xFFFFFFFFFFFFFFFF) << @intCast((rank + 1) * 8))
            else
                // Black: check ranks `rank` through 7
                 ~(@as(u64, 0xFFFFFFFFFFFFFFFF) >> @intCast((8 - rank) * 8));
            
            const has_support = (our_pawns & adjacent_files & support_mask) != 0;
            if (has_support) break :blk false;

            // Check if stop square is controlled by enemy
            // White moves +8, Black moves -8
            const stop_sq = if (color == brd.Color.White) sq + 8 else sq - 8;
            if (stop_sq < 0 or stop_sq > 63) break :blk false;

            const stop_file = @mod(stop_sq, 8);
            const stop_rank = @divTrunc(stop_sq, 8);
            
            // Enemy pawn attacks on the stop square
            // White stop square attacked by Black pawns on (rank+1, file+/-1)
            // Black stop square attacked by White pawns on (rank-1, file+/-1)
            var enemy_control = false;
            
            if (color == brd.Color.White) {
                if (stop_rank < 7) { // Black pawns would be on rank above stop sq (which is rank+1+1 relative to pawn? No, stop_sq is rank+1)
                     // Actually: Stop square is at (rank+1). Enemy pawns attacking it are at (rank+2).
                     // But simpler: just check if an enemy pawn CAN capture on stop_sq.
                     // A black pawn captures on (sq - 9) or (sq - 7).
                     // So if we are at stop_sq, we check if a black pawn is at stop_sq + 7 or + 9.
                     if (stop_sq + 7 < 64 and (opp_pawns & (@as(u64, 1) << @intCast(stop_sq + 7))) != 0 and stop_file > 0) enemy_control = true;
                     if (stop_sq + 9 < 64 and (opp_pawns & (@as(u64, 1) << @intCast(stop_sq + 9))) != 0 and stop_file < 7) enemy_control = true;
                }
            } else {
                 // Black stop square is (rank-1). White pawns attacking it are at (rank-2).
                 // White pawn captures on (sq + 7) or (sq + 9).
                 // If we are at stop_sq, we check if white pawn is at stop_sq - 7 or - 9.
                 if (stop_sq >= 7 and (opp_pawns & (@as(u64, 1) << @intCast(stop_sq - 7))) != 0 and stop_file < 7) enemy_control = true;
                 if (stop_sq >= 9 and (opp_pawns & (@as(u64, 1) << @intCast(stop_sq - 9))) != 0 and stop_file > 0) enemy_control = true;
            }

            break :blk enemy_control;
        };

        if (is_backward) {
            result.mg += backward_pawn_penalty;
            result.eg += backward_pawn_penalty;
        }

        // [EXISTING] Passed Pawn Logic
        const is_passed = blk: {
            const file_mask: u64 = @as(u64, 0x0101010101010101) << @intCast(file);
            const forward_mask = file_mask | adjacent_files; // Use shared adjacent_files
            
            const blocking_pawns = if (color == brd.Color.White) blk2: {
                const rank_mask: u64 = (@as(u64, 0xFFFFFFFFFFFFFFFF) << @intCast((rank + 1) * 8));
                break :blk2 opp_pawns & forward_mask & rank_mask;
            } else blk2: {
                const rank_mask: u64 = if (rank > 0) (@as(u64, 0xFFFFFFFFFFFFFFFF) >> @intCast((8 - rank) * 8)) else 0;
                break :blk2 opp_pawns & forward_mask & rank_mask;
            };
            break :blk blocking_pawns == 0;
        };

        if (is_passed) {
            const mg_bonus = mg_passed_bonus[relative_rank];
            const eg_bonus = passed_pawn_bonus[relative_rank];
            const advancement_bonus = if (relative_rank >= 5) 
                @divTrunc((total_phase - phase) * @as(i32, @intCast(relative_rank)) * 3, total_phase)
            else 0;
            result.mg += mg_bonus;
            result.eg += eg_bonus + advancement_bonus;
        }
        
        // [EXISTING] Protected Pawn Logic
        // ... (Keep existing protected logic here, lines 124-136) ...
        const is_protected = blk: {
             // ... [Logic from original file] ...
             // For brevity, assuming original logic is retained here
             // It checks if our_pawns exist on capture squares behind this pawn
             var protected = false;
             if (color == brd.Color.White) {
                if (sq >= 9 and file > 0 and (our_pawns & (@as(u64, 1) << @intCast(sq - 9))) != 0) protected = true;
                if (sq >= 7 and file < 7 and (our_pawns & (@as(u64, 1) << @intCast(sq - 7))) != 0) protected = true;
             } else {
                if (sq <= 54 and file > 0 and (our_pawns & (@as(u64, 1) << @intCast(sq + 7))) != 0) protected = true;
                if (sq <= 56 and file < 7 and (our_pawns & (@as(u64, 1) << @intCast(sq + 9))) != 0) protected = true;
             }
             break :blk protected;
        };

        if (is_protected) {
            result.mg += protected_pawn_bonus;
            result.eg += protected_pawn_bonus;
        }
        
        // [EXISTING] Isolated Pawn Logic
        const is_isolated = (our_pawns & adjacent_files) == 0;
        if (is_isolated) {
            result.mg += isolated_pawn_penalty;
            result.eg += isolated_pawn_penalty;
        }
        
        // [EXISTING] Doubled Pawn Logic
        if (file_counts[file] > 1) {
            result.mg += doubled_pawn_penalty;
            result.eg += doubled_pawn_penalty;
        }
        
        brd.popBit(&temp_bb, sq);
    }
    
    return result;
}
