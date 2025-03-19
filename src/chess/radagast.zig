const std = @import("std");
const brd = @import("board.zig");
const Bitboard = brd.Bitboard;

pub const bishop_relevant_bits = [_]usize{
    6, 5, 5, 5, 5, 5, 5, 6,
    5, 5, 5, 5, 5, 5, 5, 5,
    5, 5, 7, 7, 7, 7, 5, 5,
    5, 5, 7, 9, 9, 7, 5, 5,
    5, 5, 7, 9, 9, 7, 5, 5,
    5, 5, 7, 7, 7, 7, 5, 5,
    5, 5, 5, 5, 5, 5, 5, 5,
    6, 5, 5, 5, 5, 5, 5, 6,
};

pub const rook_relevant_bits = [_]usize{
    12, 11, 11, 11, 11, 11, 11, 12,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    11, 10, 10, 10, 10, 10, 10, 11,
    12, 11, 11, 11, 11, 11, 11, 12,
};

pub const Istari = struct {
    state: u32,
    bishop_magics: [64]u64,
    rook_magics: [64]u64,

    pub fn new() Istari {
        return .{
            .state = 1804289383,
            .bishop_magics = [_]u64{0} ** 64,
            .rook_magics = [_]u64{0} ** 64,
        };
    }

    fn randomU32(self: *Istari) u32 {
        var x = self.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.state = x;
        return x;
    }

    fn randomU64(self: *Istari) u64 {
        const x: u64 = @as(u64, self.randomU32()) & 0xFFFF;
        const y: u64 = @as(u64, self.randomU32()) & 0xFFFF;
        const z: u64 = @as(u64, self.randomU32()) & 0xFFFF;
        const w: u64 = @as(u64, self.randomU32()) & 0xFFFF;
        return x | (y << 16) | (z << 32) | (w << 48);
    }

    pub fn generateMagicNum(self: *Istari) u64 {
        return self.randomU64() & self.randomU64() & self.randomU64();
    }

    pub fn findMagicNums(self: *Istari, sq: brd.Square, relevant_bits: i32, bishop: bool) u64 {
        var occupancies = [_]Bitboard{0} ** 4096;
        var attacks = [_]Bitboard{0} ** 4096;

        const attack_mask: Bitboard = if (bishop)
            maskBishopAttacks(sq)
        else
            maskRookAttacks(sq);

        const occupancy_index: u64 = @as(u64, 1) << @intCast(relevant_bits);

        for (0..@intCast(occupancy_index)) |index| {
            occupancies[index] = setOccupancy(@intCast(index), relevant_bits, attack_mask);
            attacks[index] = if (bishop)
                bishopAttacks(sq, occupancies[index])
            else
                rookAttacks(sq, occupancies[index]);
        }

        for (0..100000000) |_| {
            const magic: u64 = self.generateMagicNum();

            if (brd.countBits((attack_mask *% magic) & 0xFF00000000000000) < 6) {
                continue;
            }

            var fail: bool = false;
            var used_attacks: [4096]Bitboard = [_]Bitboard{0} ** 4096;

            for (0..@intCast(occupancy_index)) |i| {
                const index = ((occupancies[i] *% magic) >> @as(u6, @intCast(64 - relevant_bits)));
                if (used_attacks[index] == 0) {
                    used_attacks[index] = attacks[i];
                } else if (used_attacks[index] != attacks[i]) {
                    fail = true;
                    break;
                }
            }

            if (!fail) {
                return magic;
            }
        } else {
            std.debug.print("Failed to find magic number for square {d}\n", .{sq});
            return 0;
        }
    }
    pub fn initMagicNumbers(self: *Istari) void {
        for (0..64) |sq| {
            self.rook_magics[sq] = self.findMagicNums(sq, @as(i32, @intCast(rook_relevant_bits[sq])), false);
            std.debug.print("0x{x},\n ", .{self.rook_magics[sq]});
        }
        std.debug.print("\n\n\n", .{});
        for (0..64) |sq| {
            self.bishop_magics[sq] = self.findMagicNums(sq, @as(i32, @intCast(bishop_relevant_bits[sq])), true);
            std.debug.print("0x{x}, \n", .{self.bishop_magics[sq]});
        }
    }
};

pub fn maskBishopAttacks(sq: brd.Square) Bitboard {
    var attacks: Bitboard = 0;

    const target_rank: isize = @intCast(sq / 8);
    const target_file: isize = @intCast(sq % 8);

    calculateAttacks(1, 1, target_rank, target_file, &attacks);
    calculateAttacks(1, -1, target_rank, target_file, &attacks);
    calculateAttacks(-1, 1, target_rank, target_file, &attacks);
    calculateAttacks(-1, -1, target_rank, target_file, &attacks);

    return attacks;
}

pub fn maskRookAttacks(sq: brd.Square) Bitboard {
    var attacks: Bitboard = 0;

    const target_rank: isize = @intCast(sq / 8);
    const target_file: isize = @intCast(sq % 8);

    calculateAttacks(1, 0, target_rank, target_file, &attacks);
    calculateAttacks(-1, 0, target_rank, target_file, &attacks);
    calculateAttacks(0, 1, target_rank, target_file, &attacks);
    calculateAttacks(0, -1, target_rank, target_file, &attacks);

    return attacks;
}

fn calculateAttacks(rank_dir: isize, file_dir: isize, target_rank: isize, target_file: isize, attacks: *Bitboard) void {
    var rank = target_rank + rank_dir;
    var file = target_file + file_dir;
    while ((rank_dir == 0 or (rank >= 1 and rank <= 6)) and
        (file_dir == 0 or (file >= 1 and file <= 6)))
    {
        const sq = @as(usize, @intCast(rank)) * 8 + @as(usize, @intCast(file));
        attacks.* |= brd.getSquareBB(sq);
        rank += rank_dir;
        file += file_dir;
    }
}

fn calculateAttacksWithBlocks(rank_dir: isize, file_dir: isize, target_rank: isize, target_file: isize, attacks: *Bitboard, blockers: Bitboard) void {
    var rank = target_rank + rank_dir;
    var file = target_file + file_dir;
    while ((rank >= 0 and rank <= 7) and (file >= 0 and file <= 7)) {
        const sq = @as(usize, @intCast(rank)) * 8 + @as(usize, @intCast(file));
        attacks.* |= brd.getSquareBB(sq);
        if (brd.getBit(blockers, sq)) {
            break;
        }
        rank += rank_dir;
        file += file_dir;
    }
}

pub fn bishopAttacks(sq: brd.Square, blocks: Bitboard) Bitboard {
    var attacks: Bitboard = 0;
    const target_rank: isize = @intCast(sq / 8);
    const target_file: isize = @intCast(sq % 8);

    calculateAttacksWithBlocks(1, 1, target_rank, target_file, &attacks, blocks);
    calculateAttacksWithBlocks(1, -1, target_rank, target_file, &attacks, blocks);
    calculateAttacksWithBlocks(-1, 1, target_rank, target_file, &attacks, blocks);
    calculateAttacksWithBlocks(-1, -1, target_rank, target_file, &attacks, blocks);

    return attacks;
}

pub fn rookAttacks(sq: brd.Square, blocks: Bitboard) Bitboard {
    var attacks: Bitboard = 0;
    const target_rank: isize = @intCast(sq / 8);
    const target_file: isize = @intCast(sq % 8);

    calculateAttacksWithBlocks(1, 0, target_rank, target_file, &attacks, blocks);
    calculateAttacksWithBlocks(-1, 0, target_rank, target_file, &attacks, blocks);
    calculateAttacksWithBlocks(0, 1, target_rank, target_file, &attacks, blocks);
    calculateAttacksWithBlocks(0, -1, target_rank, target_file, &attacks, blocks);

    return attacks;
}

pub fn setOccupancy(index: Bitboard, bits: i32, attack_mask: Bitboard) Bitboard {
    var atm = attack_mask;
    var occupancy: Bitboard = 0;

    for (0..@intCast(bits)) |i| {
        const square = brd.getLSB(atm);
        brd.popBit(&atm, square);
        if (index & brd.getSquareBB(i) != 0) {
            occupancy |= brd.getSquareBB(square);
        }
    }
    return occupancy;
}
