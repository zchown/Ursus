# Ursus Chess Engine

Ursus is a UCI-compatible chess engine written in [Zig](https://ziglang.org/). It uses a bitboard-based board representation, a heavily pruned alpha-beta search with parallel iterative deepening, and an Efficiently Updatable Neural Network (NNUE) for its evaluation function.

Play against it on Lichess: [`Ursus_bot`](https://lichess.org/@/Ursus_bot)

[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=bullet)](https://lichess.org/@/Ursus_bot/perf/bullet)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=blitz)](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=blitz)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=rapid)](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=rapid)

---

## Building

Ursus requires a [Zig](https://ziglang.org/) compiler. To build:

```bash
zig build

```

For maximum playing strength, build with optimizations targeting your native architecture:

```bash
zig build -Doptimize=ReleaseFast -Dtarget=native

```

The resulting binary communicates over standard input/output using the UCI protocol and is compatible with any UCI chess GUI (Arena, CuteChess, etc.).

---

## UCI Protocol Support

Ursus implements the core UCI protocol. The table below summarizes supported commands.

| Command | Status |
| --- | --- |
| `uci` | Supported |
| `isready` | Supported |
| `ucinewgame` | Supported -- resets the board and clears the TT |
| `position startpos [moves ...]` | Supported |
| `position fen <fen> [moves ...]` | Supported |
| `go` | Supported -- accepts `wtime`, `btime`, `winc`, `binc`, `movestogo`, `depth`, `nodes`, `mate`, `movetime`, `infinite`, `ponder` |
| `stop` | Supported |
| `ponderhit` | Supported |
| `quit` | Supported |
| `debug` | Supported -- turns debug mode on/off or prints current board FEN |
| `d` | Supported -- pretty-prints the current board |
| `register` | Accepted |
| `setoption name Hash` | Supported |
| `setoption name Clear Hash` | Supported |
| `setoption name Ponder` | Supported |
| `setoption name Threads` | Supported -- enables multi-threaded search |
| `datagen` | Supported -- runs the internal self-play data generator |
| `eval` / `hce` | Supported -- prints the current static NNUE or legacy HCE evaluation |

---

## Search

Ursus uses negamax with alpha-beta pruning and iterative deepening. The search has been upgraded to support multithreading via Parallel Iterative Deepening, utilizing helper threads that share a common transposition table and work together to explore the search tree more efficiently.

### Iterative Deepening and Aspiration Windows

The engine searches from depth 1 upward. Starting at depth 2, aspiration windows are applied around the previous iteration's score, with the delta widening dynamically on fail-high or fail-low.

### Move Ordering

Moves are scored and selected using a partial selection sort (lazy move ordering) in the following priority:

1. Hash move from the transposition table
2. Winning captures (SEE > 0), scaled by SEE value
3. Queen promotions
4. Equal captures (SEE = 0)
5. Killer moves (up to 2 per ply)
6. Counter moves
7. Quiet moves scored by history heuristic and continuation history (plies 1, 2, 4)
8. Losing captures (SEE < 0)

### Pruning and Reductions

* **Reverse Futility Pruning (RFP):** Prunes if the static eval minus a depth-scaled margin exceeds beta. The margin is tightened when the position is improving.
* **Null Move Pruning (NMP):** At depth >= 3 with non-pawn material, a null move search is performed at a reduced depth.
* **Razoring:** At depth <= 4, drops directly into quiescence search based on a static threshold.
* **Late Move Pruning (LMP):** Quiet moves beyond a depth-dependent threshold are skipped.
* **Late Move Reductions (LMR):** Non-PV quiet moves are reduced according to a precomputed log-based table. Reductions are adjusted based on history, counter moves, and improving status.
* **Singular Extensions:** If a TT move appears singular (verified by a reduced-depth search with a narrowed window), it is extended by up to 3 plies.
* **Check Extensions:** Depth is extended by 1 when the side to move is in check.
* **Internal Iterative Deepening (IID):** At depth >= 3 without a TT hit, a reduced depth search populates the transposition table before the full search.

### Quiescence Search

Beyond the main search horizon, a quiescence search evaluates captures and check evasions under the same alpha-beta framework with SEE-based move scoring and delta pruning.

---

## Evaluation

Ursus has transitioned from a hand-crafted evaluation function to a highly optimized Neural Network (NNUE).

### Architecture and Inference

* **Structure:** The network utilizes a `768 -> 1024x2 -> 1` architecture (`2 * num_pieces * num_squares` input features into a hidden size of 1024).
* **Accumulator Stack:** The engine maintains an `NNUEStack` to incrementally update network activations. Instead of re-evaluating the board from scratch, it efficiently updates the accumulator during `makeMove` and `unmakeMove` by selectively activating and deactivating features based on the pieces moving, captured, or promoted.
* **Legacy HCE:** The previous hand-crafted evaluation (and pawn transposition table) is preserved for reference and can be accessed via the `hce` UCI command.

### Data Generation

Ursus includes a built-in, multi-threaded self-play data generator used for training its neural networks.

* Generates data via self-play games between the current engine and itself, using the same search and evaluation as in normal play.
* Uses static evaluation and quiescence search checks to filter out highly tactical or strictly won/lost opening positions.
* Outputs a bullet-compatible text format: `fen | score | result`.
* Activated via the `datagen` UCI command with configurable nodes, games, threads, and output paths.

---

## Board Representation

The board is represented using bitboards, with one 64-bit integer per piece type per color. Move make/unmake is fully implemented with an irreversible state history (Zobrist hash, castling rights, en passant square, halfmove clock) stored in a fixed-size history array.

### Move Encoding

Each move is currently packed into a `u32` (`EncodedMove`) containing the source and destination squares, moving and promoted piece types, a capture flag with captured piece type, and special flags for double pawn pushes, en passant, and castling.

---

## Roadmap

* **Move encoding migration to `u16`:** The current `EncodedMove` uses a packed `u32`. Migrating to a compact `u16` (storing only from/to squares and special flags) would halve memory usage across move lists, killer tables, history tables, and the PV array.

