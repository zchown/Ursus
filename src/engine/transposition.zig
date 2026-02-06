const std = @import("std");
const zob = @import("zobrist");
const brd = @import("board");
const mv = @import("moves");

pub const default_tt_size_mb = 64; // 64 MB
pub const kb = 1 << 10;
pub const mb = 1 << 20;

pub const EstimationType = enum(u2) {
    None,
    Under,
    Over,
    Exact,
};

pub const Entry = struct {
    hash: zob.ZobristKey = 0,
    eval: i32 = 0.0,
    move: mv.EncodedMove = mv.EncodedMove.fromU32(0),
    flag: EstimationType = .None,
    depth: u8 = 0,
    age: u6 = 0,
};

pub var tt_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

pub var global_tt_initialized: bool = false;
pub var global_tt_size_mb: usize = default_tt_size_mb;
pub var global_tt_needs_reset: bool = false;
pub var global_tt: *TranspositionTable = undefined;

pub const TranspositionTable = struct {
    items: std.ArrayList(Entry),
    size: usize,
    age: u6,

    pub fn initGlobal(size_in_mb: usize) !void {
        const raw_num_entries = (size_in_mb * mb) / @sizeOf(Entry);
        // Round down to the nearest power of two
        const num_entries:usize = std.math.floorPowerOfTwo(usize, raw_num_entries);

        global_tt = try tt_arena.allocator().create(TranspositionTable);
        global_tt.* = TranspositionTable{
            .items = try std.ArrayList(Entry).initCapacity(tt_arena.allocator(), num_entries),
            .size = num_entries,
            .age = 0,
        };
        global_tt.items.expandToCapacity();
        global_tt_initialized = true;
     }

    pub inline fn clear(self: *TranspositionTable) void {
        self.items.clearRetainingCapacity();
    }

    pub fn resize(self: *TranspositionTable, new_size_in_mb: usize) !void {
        const raw_num_entries = (new_size_in_mb * mb) / @sizeOf(Entry);
        const new_num_entries: usize = std.math.floorPowerOfTwo(usize, raw_num_entries);

        self.items.deinit(tt_arena.allocator());
        self.items = try std.ArrayList(Entry).initCapacity(tt_arena.allocator(), new_num_entries);
        self.size = new_num_entries;
        self.age = 0;
    }

    pub inline fn reset(self: *TranspositionTable) void {
        self.clear();
        self.age = 0;
    }

    pub inline fn index(self: *TranspositionTable, hash: zob.ZobristKey) usize {
        return @as(usize, hash & (@as(zob.ZobristKey, self.size) - 1));
    }

    pub inline fn incrememtAge(self: *TranspositionTable) void {
        self.age +%= 1;
    }

    pub inline fn set(self: *TranspositionTable, entry: Entry) void {
        const idx = self.index(entry.hash);
        const cur_entry = self.items.items[idx];

        if (entry.flag == .Exact or cur_entry.hash != entry.hash or cur_entry.depth <= entry.depth + 4 or cur_entry.age != self.age) {
            self.items.items[idx] = entry;
        }
    }

    pub inline fn prefetch(self: *TranspositionTable, hash: zob.ZobristKey) void {
        @prefetch(&self.items.items[self.index(hash)], .{
            .rw = .read,
            .locality = 1,
            .cache = .data,
        });
    }

    pub fn get(self: *TranspositionTable, hash: zob.ZobristKey) ?Entry {
        const idx = self.index(hash);
        const entry = self.items.items[idx];

        if (entry.hash == hash and entry.flag != .None ) {
            return entry;
        } else {
            return null;
        }
    }
};
