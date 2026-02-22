# Ursus Chess Engine

Ursus is a UCI-compatible chess engine written in [Zig](https://ziglang.org/). It uses a bitboard-based board representation, a heavily pruned alpha-beta search with iterative deepening, and a hand-crafted evaluation function whose parameters are optimized via Texel tuning.

Play against it on Lichess: [`Ursus_bot`](https://lichess.org/@/Ursus_bot)

[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=bullet)](https://lichess.org/@/Ursus_bot/perf/bullet)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=blitz)](https://lichess.org/@/Ursus_bot/perf/blitz)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=rapid)](https://lichess.org/@/Ursus_bot/perf/rapid)

---

## Building

Ursus requires a [Zig](https://ziglang.org/) compiler. To build:

```
zig build
```

For maximum playing strength, build with optimizations targeting your native architecture:

```
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
| `ucinewgame` | Supported -- resets the board to the starting position |
| `position startpos [moves ...]` | Supported |
| `position fen <fen> [moves ...]` | Supported |
| `go` | Supported -- accepts `wtime`, `btime`, `winc`, `binc`, `movestogo`, `depth`, `nodes`, `mate`, `movetime`, `infinite`, `ponder` |
| `stop` | Supported |
| `ponderhit` | Supported |
| `quit` | Supported |
| `debug` | Supported -- prints current board FEN |
| `d` | Supported -- pretty-prints the current board |
| `register` | Accepted |
| `setoption name Hash` | Supported |
| `setoption name Clear Hash` | Supported |
| `setoption name Ponder` | Supported |
| `setoption name Threads` | Supported |
| `searchmoves` | Parsed, not yet implemented |

After each search, Ursus emits a standard `info` line (`depth`, `seldepth`, `time`, `nodes`, `pv`, `score cp`) followed by `bestmove`.

### Time Management

When given `movetime`, Ursus sets a soft limit at 80% and a hard limit at 90% of the allotted time. When given `wtime`/`btime`, it assumes 25 moves remaining if `movestogo` is not specified. The ideal allocation is 90% of the per-move share; the hard limit allows up to 3x the ideal, capped at 40% of the remaining clock, with a 100ms safety buffer always preserved. Under `infinite` or `ponder` mode, no time limit is applied.

---

## Search

Ursus uses negamax with alpha-beta pruning and iterative deepening. The following techniques are employed.

### Iterative Deepening and Aspiration Windows

The engine searches from depth 1 upward. Starting at depth 2, aspiration windows of +/-25 centipawns are applied around the previous iteration's score, with the delta widening on fail-high or fail-low.

### Move Ordering

Moves are scored and selected using a partial selection sort (lazy move ordering) in the following priority:

1. Hash move from the transposition table
2. Winning captures (SEE > 0), scaled by SEE value
3. Queen promotions
4. Equal captures (SEE = 0)
5. Killer moves (up to 4 per ply)
6. Counter moves
7. Quiet moves scored by history heuristic and continuation history (plies 1, 2, 4)
8. Losing captures (SEE < 0)

### Pruning and Reductions

- **Reverse Futility Pruning (RFP):** At depths <= 6, prune if the static eval minus a depth-scaled margin exceeds beta. The margin is reduced by 75cp when the position is improving.
- **Null Move Pruning (NMP):** At depth >= 3 with non-pawn material, a null move search is performed at a reduced depth calculated as `3 + depth/3 + min(4, (static_eval - beta) / 150)`.
- **Razoring:** At depth <= 2, if the static eval plus 300cp is still below alpha, the engine drops directly into quiescence search.
- **Late Move Pruning (LMP):** Quiet moves beyond a depth-dependent threshold are skipped. The threshold starts at 8 moves at depth 1 and increases by 4 per depth level, relaxed slightly when improving.
- **Late Move Reductions (LMR):** Non-PV quiet moves are reduced according to a compile-time table derived from `0.5 * ln(depth) * ln(move_index) + 0.75`.
- **Probcut:** At depth >= 4, a reduced-depth capture search prunes moves unlikely to beat `beta + 200`.
- **Singular Extensions:** If a TT move appears singular (verified by a reduced-depth search with a narrowed window), it is extended by 1 ply.
- **Check Extensions:** Depth is extended by 1 when the side to move is in check.
- **Internal Iterative Deepening (IID):** At depth >= 8 on PV nodes without a TT hit, a shallow 1-ply search populates the transposition table before the full search.
- **Mate Distance Pruning:** Alpha and beta are tightened based on distance from the root to avoid searching lines longer than a known mate.

### Quiescence Search

Beyond the main search horizon, a quiescence search evaluates captures and check evasions under the same alpha-beta framework with SEE-based move scoring.

### Draw Detection

The engine recognizes draws by the fifty-move rule (halfmove clock >= 100), threefold repetition (via Zobrist hash comparison), and insufficient material (KvK, K+minor vs K, KBvKB with same-color bishops).

---

## Evaluation

The evaluation function is hand-crafted and uses a tapered score that interpolates between middlegame and endgame values based on a phase computed from remaining material (queen = 4, rook = 2, bishop/knight = 1, max phase = 24).

### Evaluation Terms

- **Material:** Separate middlegame and endgame piece values (e.g., pawn: 82/94cp, queen: 1025/936cp).
- **Piece-Square Tables (PSTs):** Per-piece middlegame and endgame tables encoding positional value by square.
- **Pawn Structure:** Passed pawns with rank-scaled bonuses, isolated pawns, doubled pawns, protected pawns. Pawn structure evaluation is cached in a dedicated pawn transposition table.
- **King Safety:** Castling bonus, pawn shield evaluation, penalties for open and semi-open files near the king, and an attack unit table aggregating threats from minor and major pieces.
- **Piece Activity:** Mobility counts for bishops, rooks, and queens. Bonuses for rooks on open/semi-open files, rooks on the 7th rank, rooks behind passed pawns. Penalties for trapped rooks and bad bishops. Bonus for the bishop pair. Knight outpost bonus.
- **Threats:** Penalties for hanging pieces and pieces attacked by lower-value attackers.
- **Endgame-Specific:** King proximity to passed pawns, rook-behind-passer bonus.
- **Miscellaneous:** Tempo bonus (10cp for the side to move), space evaluation, center control.
- **Lazy Evaluation:** If the raw material score already exceeds the search window by more than 800cp, the full evaluation is skipped.
- **Correction History:** A 16K-entry per-side table adjusts the static evaluation based on accumulated prediction errors from previous search nodes.

### Texel Tuning

Ursus uses Texel's tuning method to optimize its evaluation parameters. The tuner (implemented in `texel_tuner.zig`) works by minimizing the mean squared error between the engine's static evaluation (mapped through a sigmoid) and the actual game outcomes from a large dataset of positions with known results.

The process works as follows. A dataset of positions is collected from real games, each annotated with the game result (1.0 for white win, 0.5 for draw, 0.0 for black win). For each position, the engine's static evaluation score is converted to a win probability using a sigmoid function: `1 / (1 + 10^(-K * score / 400))`, where K is a scaling constant tuned to minimize the overall error. The optimizer then iteratively adjusts evaluation parameters -- material values, piece-square table entries, pawn structure bonuses, king safety weights, and other terms -- to reduce the mean squared error between predicted and actual outcomes across the entire dataset.

This approach allows simultaneous optimization of hundreds of evaluation parameters in a principled way, grounding the evaluation weights in empirical game data rather than relying solely on manual tuning and intuition. The tuned parameters feed directly back into the engine's evaluation tables.

---

## Board Representation

The board is represented using bitboards, with one 64-bit integer per piece type per color. Move make/unmake is fully implemented with an irreversible state history (Zobrist hash, castling rights, en passant square, halfmove clock) stored in a fixed-size history array.

### Move Generation

Sliding piece attacks (bishops, rooks, queens) are computed using magic bitboards. Knights and kings use precomputed attack tables. The move generator produces a `MoveList` (capacity 218) and supports generating all legal moves or captures only (for quiescence search).

### Move Encoding

Each move is packed into a `u32` (`EncodedMove`) containing the source and destination squares (6 bits each), moving and promoted piece types (4 bits each), a capture flag with captured piece type, and special flags for double pawn pushes, en passant, and castling.

### Transposition Table

The main transposition table defaults to 64 MB. Each entry stores the Zobrist hash, best move, search depth, node type (exact, upper bound, lower bound), and a static evaluation score. An aging mechanism prioritizes replacing entries from older searches. A separate 8 MB pawn transposition table caches pawn structure evaluation.

### Static Exchange Evaluation (SEE)

A full SEE implementation determines whether a capture sequence on a given square wins or loses material. SEE is used both for move ordering (classifying captures as winning, equal, or losing) and for pruning decisions in the search.

---

## Roadmap

- **Move encoding migration to `u16`:** The current `EncodedMove` uses a packed `u32` with 4 bits of padding. Migrating to a compact `u16` (storing only from/to squares and special flags) would halve memory usage across move lists, killer tables, history tables, and the PV array. More importantly, it would enable atomic storage of transposition table entries, allowing a lock-free design for concurrent access from multiple threads.
- **Multithreaded search (Lazy SMP):** The `Searcher` struct already includes a `thread_id` field in preparation for a Lazy SMP implementation. The plan is to run multiple threads, each performing independent iterative deepening searches on a shared transposition table, with the main thread collecting and reporting the best result.
