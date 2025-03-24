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
    depth: isize,
    score: f64,
    zobrist: zob.ZobristKey,
};

pub const TranspositionTableStats = struct {
    hits: usize,
    misses: usize,
    collisions: usize,
    depth_rewrites: usize,
    current_fill: usize,
    update_count: usize,
    lookup_count: usize,

    pub fn init() TranspositionTableStats {
        return TranspositionTableStats{
            .hits = 0,
            .misses = 0,
            .collisions = 0,
            .depth_rewrites = 0,
            .current_fill = 0,
            .update_count = 0,
            .lookup_count = 0,
        };
    }

    pub fn print(self: TranspositionTableStats) void {
        std.debug.print("TranspositionTableStats:\n", .{});
        std.debug.print("  Hits: {}\n", .{self.hits});
        std.debug.print("  Misses: {}\n", .{self.misses});
        std.debug.print("  Collisions: {}\n", .{self.collisions});
        std.debug.print("  Depth Rewrites: {}\n", .{self.depth_rewrites});
        std.debug.print("  Current Fill: {}\n", .{self.current_fill});
        std.debug.print("  Update Count: {}\n", .{self.update_count});
        std.debug.print("  Lookup Count: {}\n", .{self.lookup_count});
    }
};

pub const TranspositionTable = struct {
    entries: []TranspositionEntry,
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
        self.stats.lookup_count += 1;
        const index = self.zobristToIndex(zobrist);

        for (0..self.retries) |i| {
            const probe_index = (index + i) % self.capacity;
            const entry = self.entries[probe_index];

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

    pub fn set(self: *TranspositionTable, estimation: EstimationType, move: mv.EncodedMove, depth: isize, score: f64, zobrist: zob.ZobristKey) void {
        self.stats.update_count += 1;
        const index = self.zobristToIndex(zobrist);

        const new_entry = TranspositionEntry{
            .estimation = estimation,
            .move = move,
            .depth = depth,
            .score = score,
            .zobrist = zobrist,
        };

        var lowest_depth_index = index;
        var lowest_depth = self.entries[index].depth;

        for (0..self.retries) |i| {
            const probe_index = (index + i) & (self.capacity - 1);

            if (self.entries[probe_index].zobrist == 0) {
                self.stats.current_fill += 1;
                self.entries[probe_index] = new_entry;
                return;
            } else if ((self.entries[probe_index].zobrist == zobrist) and (self.entries[probe_index].depth < depth)) {
                self.stats.depth_rewrites += 1;
                self.entries[probe_index] = new_entry;
                return;
            } else {
                if (self.entries[probe_index].depth < lowest_depth) {
                    lowest_depth = self.entries[probe_index].depth;
                    lowest_depth_index = probe_index;
                }
            }
        }
        self.stats.collisions += 1;
        if (lowest_depth < depth) {
            self.stats.depth_rewrites += 1;
            self.entries[lowest_depth_index] = new_entry;
        }
    }
};
