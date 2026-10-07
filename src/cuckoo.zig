pub const std = @import("std");
pub const root = @import("root.zig");
pub const brd = root.brd;
pub const mvs = root.moves;
pub const zob = root.zob;

pub var cuckoo: Cuckoo = Cuckoo{};

pub const Cuckoo = struct {
    keys: [8192]u64 = @splat(0),
    moves: [8192]mvs.Move = @splat(mvs.Move.none),

    pub inline fn h1(k: u64) usize { return @intCast(k & 0x1fff); }
    pub inline fn h2(k: u64) usize { return @intCast((k >> 16) & 0x1fff); }

    pub fn init(self: *Cuckoo, mg: *const mvs.MoveGen) void {
        const side = zob.ZobristKeys.sideKeys(.White) ^ zob.ZobristKeys.sideKeys(.Black);
        var count: usize = 0;
        for ([_]brd.Color{ .White, .Black }) |c| {
            for ([_]brd.Pieces{ .Knight, .Bishop, .Rook, .Queen, .King }) |pc| {
                for (0..64) |a| {
                    for (a + 1..64) |b| {
                        const sa: brd.Square = @intCast(a);
                        const sb: brd.Square = @intCast(b);
                        const att: u64 = switch (pc) {
                            .Knight => mg.knights[sa],
                            .Bishop => mg.getBishopAttacks(sa, 0),
                            .Rook => mg.getRookAttacks(sa, 0),
                            .Queen => mg.getQueenAttacks(sa, 0),
                            else => mg.kings[sa],
                        };
                        if (att & brd.getSquareBB(sb) == 0) continue;

                        var key = zob.ZobristKeys.pieceKeys(c, pc, sa) ^ zob.ZobristKeys.pieceKeys(c, pc, sb) ^ side;
                        var mv = mvs.Move.quiet(sa, sb);
                        var i = h1(key);
                        while (true) {
                            std.mem.swap(u64, &self.keys[i], &key);
                            std.mem.swap(mvs.Move, &self.moves[i], &mv);
                            if (mv.isNull()) break;
                            i = if (i == h1(key)) h2(key) else h1(key);
                        }
                        count += 1;
                    }
                }
            }
        }
        std.debug.assert(count == 3668);
    }
};

