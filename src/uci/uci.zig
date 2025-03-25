const std = @import("std");
const brd = @import("../chess/board.zig");
const mvs = @import("../chess/moves.zig");
const fen = @import("../chess/fen.zig");
const srch = @import("../engine/search.zig");
const tt = @import("../engine/transposition.zig");

pub const UciState = struct {
    board: brd.Board,
    table: tt.TranspositionTable,
    move_gen: mvs.MoveGenerator,
};
