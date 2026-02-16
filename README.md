# Ursus Chess Engine

Ursus is a UCI-compatible chess engine written in [Zig](https://ziglang.org/). It uses a bitboard-based board representation and a heavily pruned alpha-beta search with a hand-crafted evaluation function.

---

# Lichess

It can also be found on Lichess as [`Ursus_bot`](https://lichess.org/@/Ursus_bot) where its ratings are:

[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=bullet)](https://lichess.org/@/Ursus_bot/perf/bullet)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=blitz)](https://lichess.org/@/Ursus_bot/perf/blitz)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=rapid)](https://lichess.org/@/Ursus_bot/perf/rapid)

---

## UCI Support

Ursus implements the core UCI protocol. The following commands are supported:

| Command | Status |
|---|---|
| `uci` | ✅ Returns `id name Ursus`, `id author Zander`, and `uciok` |
| `isready` | ✅ Returns `readyok` |
| `ucinewgame` | ✅ Resets the board to the starting position |
| `position startpos [moves ...]` | ✅ |
| `position fen <fen> [moves ...]` | ✅ |
| `go` | ✅ Supports `wtime`, `btime`, `winc`, `binc`, `movestogo`, `depth`, `nodes`, `mate`, `movetime`, `infinite`, `ponder` |
| `stop` | ✅ |
| `ponderhit` | ✅ |
| `quit` | ✅ |
| `setoption name Hash` | ⚠️ Parsed but not yet wired up |
| `setoption name Clear Hash` | ⚠️ Parsed but not yet wired up |
| `setoption name Ponder` | ⚠️ Parsed but not yet wired up |
| `debug` | ✅ Prints current board FEN |
| `d` | ✅ Prints the current board |
| `register` | ✅ Accepted (returns `registration checking`) |
| `searchmoves` | ⚠️ Parsed but not yet implemented |

After each search, Ursus outputs a standard `info` line containing `depth`, `seldepth`, `time`, `nodes`, `pv`, and `score cp`, followed by `bestmove`.

### Time Management

Time allocation uses a simple model:

- With `movetime`: hard limit at 90%, soft limit at 80% of the allotted time.
- With `wtime`/`btime`: assumes 40 moves remaining if `movestogo` is not specified. The ideal time is 90% of the per-move share; the hard limit allows up to 3× the ideal, capped at 40% of remaining clock. A 100ms safety buffer is always preserved.
- `infinite` and `ponder`: no time limit.

---

## Implementation

### Board Representation

The board is represented using bitboards — one 64-bit integer per piece type per color. Move make/unmake is fully implemented with an irreversible state history (Zobrist hash, castling rights, en passant square, halfmove clock) stored in a fixed-size history array.

### Move Generation

Moves are generated using magic bitboards for sliding pieces (bishops, rooks, queens) and precomputed attack tables for knights and kings. The move generator produces a `MoveList` (max 218 moves per position) and can generate either all moves or captures only (for quiescence search).

### Move Encoding

Each move is stored as a packed `u32` struct (`EncodedMove`) containing:

- Source and destination squares (6 bits each)
- Moving piece and promoted piece (4 bits each)
- Capture flag and captured piece type
- Special move flags: double pawn push, en passant, castling

> **TODO:** Migrate move encoding to `u16` to reduce memory usage across move lists, history tables, and the PV array.

### Search

Ursus uses negamax with alpha-beta pruning and iterative deepening. The search includes the following techniques:

**Iterative Deepening & Aspiration Windows**
Searches are run from depth 1 upward. From depth 2 onward, aspiration windows of ±25 centipawns are used around the previous score, with delta widening on a fail-high or fail-low.

**Move Ordering**
Moves are scored and sorted lazily (partial selection sort) in this priority order:
1. Hash move from the transposition table
2. Winning captures (SEE > 0), scaled by SEE value
3. Queen promotions
4. Equal captures (SEE = 0)
5. Killer moves (up to 4 per ply)
6. Counter moves
7. Quiet moves scored by history heuristic + continuation history (plies 1, 2, 4)
8. Losing captures (SEE < 0)

**Pruning & Reductions**
- **Reverse Futility Pruning (RFP):** At depths ≤ 6, prune if `static_eval - depth * 50` ≥ β (margin reduced by 75cp when improving).
- **Null Move Pruning (NMP):** At depth ≥ 3 with non-pawn material, make a null move and search at reduced depth `r = 3 + depth/3 + min(4, (static_eval - β) / 150)`.
- **Razoring:** At depth ≤ 2, if `static_eval + 300` < α, drop directly into quiescence search.
- **Late Move Pruning (LMP):** Skip quiet moves beyond a depth-dependent threshold (starting at 8 moves at depth 1, incrementing by 4 per depth level), relaxed slightly when the position is improving.
- **Late Move Reductions (LMR):** Non-PV quiet moves are reduced by `0.5 * ln(depth) * ln(move_index) + 0.75`, computed at startup into a compile-time table.
- **Probcut:** At depth ≥ 4, a reduced-depth capture search is used to prune moves unlikely to beat a threshold of `β + 200`.
- **Check Extension:** Depth is extended by 1 when the side to move is in check.
- **Singular Extensions:** Moves are tested for singularity via a reduced-depth search with a narrowed window; singular moves are extended by 1 ply.
- **Internal Iterative Deepening (IID):** At depth ≥ 8 on PV nodes without a TT hit, a 1-ply search is run first to populate the TT.
- **Mate Distance Pruning:** Alpha and beta are tightened based on the number of plies from root.

**Quiescence Search**
After reaching depth 0, a quiescence search evaluates captures and check evasions using the same alpha-beta framework with SEE-based move scoring.

**Draw Detection**
- Fifty-move rule (halfmove clock ≥ 100)
- Threefold repetition (Zobrist hash comparison against history)
- Insufficient material (KvK, K+minor vs K, KBvKB same-color bishops)

### Transposition Table

A fixed-size hash table with 64 MB default size. Each entry stores the Zobrist hash, best move, depth, search flag (Exact / Under / Over), and a static eval. The table uses an aging mechanism to prefer replacing entries from older searches. There is also a separate 8 MB **pawn transposition table** that caches the pawn structure evaluation.

### Evaluation

The evaluation function is hand-crafted and tapered between middlegame and endgame scores using a phase value calculated from the remaining material on the board (queen = 4, rook = 2, bishop/knight = 1, max phase = 24).

Evaluation terms include:

- **Material:** Separate middlegame and endgame piece values (e.g. pawn: 82/94cp, queen: 1025/936cp).
- **Piece-Square Tables:** Middlegame and endgame PSTs for all piece types.
- **Pawn Structure** (cached in the pawn TT): passed pawns (with bonuses scaling by rank), isolated pawns, doubled pawns, pawns, protected pawns.
- **King Safety:** Castling bonus, pawn shield, penalties for open/semi-open files near the king, and an attack unit table that aggregates threats from knights, bishops, rooks, and queens.
- **Piece Activity:** Mobility counts for bishops, rooks, and queens; rook on open/semi-open file bonuses; rook on the 7th rank; rooks behind passed pawns; trapped rook penalty; bad bishop penalty; bishop pair bonus; knight outpost bonus.
- **Threats:** Penalties for hanging pieces and pieces attacked by lower-value pieces.
- **Endgame:** King proximity to passed pawns; rook-behind-passer bonus.
- **Miscellaneous:** Tempo bonus (10cp for side to move), space counting, center control.
- **Lazy Evaluation:** If the raw material score is already outside the current α/β window by more than 800cp, the full evaluation is skipped.
- **Correction History:** A 16K-entry table per side corrects the static eval based on previous prediction errors, updated after each search node.

### Static Exchange Evaluation (SEE)

A full SEE implementation determines whether a capture sequence on a given square wins or loses material. This is used both in move ordering (to distinguish winning, equal, and losing captures) and in search pruning decisions.

---

## Roadmap / Known TODOs

- **Move encoding → `u16`:** The current `EncodedMove` is a packed `u32` with 4 bits of padding. Migrating to a compact `u16` encoding (storing only from/to squares and special flags) would halve the memory footprint of move lists, killer tables, history tables, and the PV array, improving cache efficiency throughout the search. Most importantly, it would allow the transposition table to use atomics to store entries allowing for a lock-free design and concurrent access from multiple threads.

- **Multithreaded search:** The `Searcher` struct already contains a `thread_id` field in anticipation of a Lazy SMP implementation. The plan is to spawn multiple threads each running their own iterative deepening search on a shared transposition table, with the main thread collecting and reporting the best result.

---

## Building

Ursus is written in Zig. Build with:

```sh
zig build
```

It is highly reccomended to build with optimizations enabled for maximum performance:

```sh
zig build -release-fast -Dtarget=native
```

The resulting binary accepts UCI commands on standard input/output and can be used with any UCI-compatible chess GUI
