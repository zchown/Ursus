const chess = @import("chess/chess.zig");
pub fn main() void {
    // var board = chess.Board.new();
    // chess.setupStartingPosition(&board);

    // chess.debugPrintBoard(&board);

    const mg = chess.MoveGen.new();
    chess.printBitboard(mg.pawns[28]);
}
