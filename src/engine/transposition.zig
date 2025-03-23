const std = @import("std");
const zob = @import("../chess/zobrist.zig");
const brd = @import("../chess/board.zig");
const mv = @import("../chess/moves.zig");

pub const EstimationType = enum(u2) {
    Under = 0,
    Over = 1,
    Exact = 2,
};

pub const TranspositionEntry = struct {
    estimation: EstimationType,
    move: mv.EncodedMove,
    depth: usize,
    score: f64,
    zobrist: zob.ZobristKey,
};

pub const TranspositionTableStats = struct {
    hits: usize,
    misses: usize,
    collisions: usize,
    depthRewrites: usize,
    currentFill: usize,
    updateCount: usize,
    lookupCount: usize,

    pub fn init() TranspositionTableStats {
        return TranspositionTableStats{
            .hits = 0,
            .misses = 0,
            .collisions = 0,
            .depthRewrites = 0,
            .currentFill = 0,
            .updateCount = 0,
            .lookupCount = 0,
        };
    }
};

pub const TranspositionTable = struct {
    entries: [*]TranspositionEntry,
    capacity: u64,
    stats: TranspositionTableStats,
    retries: usize,

    pub fn init(allocator: std.mem.Allocator, capacity: u64, retries: ?usize) !TranspositionTable {
        const entries = try allocator.alloc(TranspositionEntry, capacity);
        return TranspositionTable{
            .entries = entries,
            .capacity = capacity,
            .stats = TranspositionTableStats.init(),
            .retries = retries orelse 8,
        };
    }

    pub fn deinit(self: *TranspositionTable, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
    }

    inline fn zobristToIndex(self: *TranspositionTable, zobrist: zob.ZobristKey) usize {
        return @as(usize, zobrist & (self.capacity - 1));
    }

    pub fn get(self: *TranspositionTable, zobrist: zob.ZobristKey) ?TranspositionEntry {
        self.stats.lookupCount += 1;
        const index = self.zobristToIndex(zobrist);

        for (0..self.retries) |i| {
            const probeIndex = (index + i) % self.capacity;
            const entry = self.entries[probeIndex];

            if (entry.zobrist == zobrist) {
                self.stats.hits += 1;
                return entry;
            } else if (entry.zobrist == 0) {
                self.stats.misses += 1;
                return null;
            } 
        }
        self.stats.misses += 1;
        return null;
    }

    pub fn set(self: *TranspositionTable, estimation: EstimationType, move: mv.EncodedMove, depth: usize, score: f64, zobrist: zob.ZobristKey) void {
        self.stats.updateCount += 1;
        const index = self.zobristToIndex(zobrist);

        const newEntry = TranspositionEntry{
            .estimation = estimation,
            .move = move,
            .depth = depth,
            .score = score,
            .zobrist = zobrist,
        };

        var lowestDepthIndex = index;
        var lowestDepth = self.entries[index].depth;

        for (0..self.retries) |i| {
            const probeIndex = (index + i) & (self.capcity - 1);

            if (self.entries[probeIndex].zobrist == 0) {
                self.stats.currentFill += 1;
                self.entries[probeIndex] = newEntry;
                return;
            }
            else if ((self.entries[probeIndex].zobrist == zobrist) and (self.entries[probeIndex].depth < depth)) {
                self.stats.depthRewrites += 1;
                self.entries[probeIndex] = newEntry;
                return;
            } else {
                if (self.entries[probeIndex].depth < lowestDepth) {
                    lowestDepth = self.entries[probeIndex].depth;
                    lowestDepthIndex = probeIndex;
                }
            }
        }
        self.stats.collisions += 1;
        if (lowestDepth < depth) {
            self.stats.depthRewrites += 1;
            self.entries[lowestDepthIndex] = newEntry;
        }
    }
};
