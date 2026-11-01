const std = @import("std");
const root = @import("root.zig");
const mvs = root.moves;
const brd = root.brd;
const zob = root.zob;
const utils = root.utils;

pub const ThreatInfo = struct {
    all: u64,
    pawn: u64,
    minor: u64,
    rook: u64,
};

pub inline fn threatIndex(threats: u64, sq: anytype) usize {
    return @intFromBool(threats & (@as(u64, 1) << @intCast(sq)) != 0);
}

pub fn computeThreatInfo(mg: *const mvs.MoveGen, gs: *const brd.GameState, by: brd.Color) ThreatInfo {
    const pos = &gs.cur_position;
    const occ = pos.getOccupancy();
    var ti: ThreatInfo = .{ .all = 0, .pawn = 0, .minor = 0, .rook = 0 };

    const pawns = pos.getPieceColorBoard(.Pawn, by);
    ti.pawn = if (by == .White)
        utils.northEastOne(pawns) | utils.northWestOne(pawns)
    else
        utils.southEastOne(pawns) | utils.southWestOne(pawns);

    var knights = pos.getPieceColorBoard(.Knight, by);
    while (knights != 0) ti.minor |= mg.knights[utils.popLsb(&knights)];

    var bishops = pos.getPieceColorBoard(.Bishop, by);
    while (bishops != 0) ti.minor |= mg.getBishopAttacks(utils.popLsb(&bishops), occ);

    var rooks = pos.getPieceColorBoard(.Rook, by);
    while (rooks != 0) ti.rook |= mg.getRookAttacks(utils.popLsb(&rooks), occ);

    var queen_att: u64 = 0;
    var queens = pos.getPieceColorBoard(.Queen, by);
    while (queens != 0) {
        const sq = utils.popLsb(&queens);
        queen_att |= mg.getBishopAttacks(sq, occ) | mg.getRookAttacks(sq, occ);
    }

    const king = pos.getPieceColorBoard(.King, by);
    const king_att: u64 = if (king != 0) mg.kings[utils.lsb(king)] else 0;

    ti.all = ti.pawn | ti.minor | ti.rook | queen_att | king_att;
    return ti;
}

pub fn computeThreats(mg: *const mvs.MoveGen, gs: *const brd.GameState, by: brd.Color) u64 {
    return computeThreatInfo(mg, gs, by).all;
}

pub fn threatCorrKey(pos: *const brd.Position, us: brd.Color, ti: ThreatInfo) u64 {
    const ours = pos.getColorBoard(us);
    const minors = (pos.getPieceBoard(.Knight) | pos.getPieceBoard(.Bishop)) & ours;
    const rooks = pos.getPieceBoard(.Rook) & ours;
    const queens = pos.getPieceBoard(.Queen) & ours;

    var hanging = (minors & ti.pawn) |
        (rooks & (ti.pawn | ti.minor)) |
        (queens & (ti.pawn | ti.minor | ti.rook));

    var key: u64 = 0;
    while (hanging != 0) {
        const sq = utils.popLsb(&hanging);
        key ^= zob.ZobristKeys.pieceKeys(us, pos.getPieceFromSquare(sq), sq);
    }
    return key;
}
