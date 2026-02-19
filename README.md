# Ursus Chess Engine

Ursus is a UCI-compatible chess engine written in [Zig](https://ziglang.org/). It uses a bitboard-based board representation and a heavily pruned alpha-beta search with a hand-crafted evaluation function.

[![lichess-bullet](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=bullet)](https://lichess.org/@/Ursus_bot/perf/bullet)
[![lichess-blitz](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=blitz)](https://lichess.org/@/Ursus_bot/perf/blitz)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=rapid)](https://lichess.org/@/Ursus_bot/perf/rapid)

---

## Table of Contents

- [Play Against Ursus](#play-against-ursus)
- [Building](#building)
- [UCI Support](#uci-support)
- [Implementation](#implementation)
  - [Board Representation](#board-representation)
  - [Move Generation](#move-generation)
  - [Search](#search)
  - [Transposition Table](#transposition-table)
  - [Evaluation](#evaluation)
  - [Static Exchange Evaluation (SEE)](#static-exchange-evaluation-see)
- [Tooling](#tooling)
- [Search Tuner](#search-tuner)
- [Roadmap](#roadmap)

---

## Play Against Ursus

Ursus runs live on Lichess as [`Ursus_bot`](https://lichess.org/@/Ursus_bot). Challenge it to a game in bullet, blitz, or rapid!

---

## Building

Ursus is written in Zig. Clone the repo and build with:

```sh
git clone https://github.com/zchown/Ursus.git
cd Ursus
zig build
```

For maximum performance (strongly recommended), build with optimizations and native CPU targeting:

```sh
zig build -Doptimize=ReleaseFast -Dtarget=native
```

The resulting binary communicates over standard input/output using the UCI protocol and can be dropped into any UCI-compatible chess GUI (e.g. [Cutechess](https://cutechess.com/), [Arena](http://www.playwitharena.de/), [En Croissant](https://encroissant.org/)).

---

## UCI Support

Ursus implements the core UCI protocol. The following commands are supported:

| Command | Status | Notes |
|---|---|---|
| `uci` | ✅ | Returns `id name Ursus`, `id author Zander`, and `uciok` |
| `isready` | ✅ | Returns `readyok` |
| `ucinewgame` | ✅ | Resets the board to the starting position |
| `position startpos [moves ...]` | ✅ | |
| `position fen <fen> [moves ...]` | ✅ | |
| `go` | ✅ | Supports `wtime`, `btime`, `winc`, `binc`, `movestogo`, `depth`, `nodes`, `mate`, `movetime`, `infinite`, `ponder` |
| `stop` | ✅ | |
| `ponderhit` | ✅ | |
| `quit` | ✅ | |
| `setoption name Hash` | ✅ | |
| `setoption name Clear Hash` | ✅ | |
| `setoption name Ponder` | ✅ | |
| `searchmoves` | ⚠️ | Parsed but not yet implemented |
| `debug` | ✅ | Prints current board |
| `register` | ✅ | Accepted (returns `registration checking`) |

After each new depth in the search, Ursus outputs a standard `info` line containing `depth`, `seldepth`, `time`, `nodes`, `pv`, and `score cp`, followed by `bestmove`.

### Time Management

- **`movetime`:** Both the soft and hard limit are set to the full allotted time with no additional scaling.
- **`wtime`/`btime`:** Assumes **25 moves remaining** when `movestogo` is unspecified. The total budget is the remaining clock (minus a 30 ms network overhead) plus the increment times the remaining moves minus one. The ideal time per move is 90% of that per-move share, capped at `remaining − 50 ms`. The hard limit is 3× the ideal, further capped at 40% of the remaining clock. Both limits are floored at 1 ms.
- **`infinite` / `ponder`:** No time limit applied; the search runs until `stop` or `ponderhit` is received.

### Pondering

When `go ponder` is received, Ursus begins searching the expected opponent reply immediately with `force_think` set — the search ignores normal time limits and runs indefinitely. The limits and side to move are saved so the budget can be reconstructed later.

When `ponderhit` arrives (the opponent played the expected move), Ursus calculates the normal time allocation for the position and **adds the time already spent pondering** to both the ideal and hard limits. This means every millisecond spent thinking on the opponent's turn translates directly into extra thinking time on Ursus's own turn, giving pondering a concrete Elo benefit on time controls where the GUI supports it.

When the search concludes, `bestmove` is followed by a `ponder` move whenever the PV contains at least two moves, allowing the GUI to immediately start the next ponder search.

---

## Implementation

### Board Representation

The board is represented using bitboards — one 64-bit integer per piece type per color. Make/unmake is fully implemented with an irreversible state history (Zobrist hash, castling rights, en passant square, halfmove clock) stored in a fixed-size history array.

### Move Generation

Moves are generated using **magic bitboards** for sliding pieces (bishops, rooks, queens) and precomputed attack tables for knights and kings. The move generator produces a `MoveList` (up to 218 moves per position) and can generate either all moves or captures only (for quiescence search).

### Search

Ursus uses negamax with alpha-beta pruning and iterative deepening. The following techniques are implemented:

**Iterative Deepening & Aspiration Windows**
Searches run from depth 1 upward. From depth 2 onward, aspiration windows of ±32 centipawns are used around the previous score, with delta widening on fail-high or fail-low.

**Multithreaded Search (Lazy SMP)**
Ursus runs multiple threads in parallel, each performing their own iterative deepening search on a shared transposition table. The main thread collects results and reports the best move.

**Move Ordering**
Moves are scored and sorted lazily (partial selection sort) in this priority order:

1. Hash move from the transposition table
2. Winning captures (SEE > 0), scaled by SEE value + capture history
3. Queen promotions
4. Equal captures (SEE = 0), ordered by capture history
5. Killer moves (2 per ply)
6. Counter moves
7. Quiet moves scored by butterfly history + continuation history at plies 1, 2, and 4
8. Losing captures (SEE < 0)

**Pruning & Reductions**

| Technique | Details |
|---|---|
| Reverse Futility Pruning (RFP) | At depth ≤ 7, prune if `static_eval − depth × 90 ≥ β` (margin reduced by 41 cp when improving) |
| Null Move Pruning (NMP) | At depth ≥ 3 with non-pawn material; `r = 4 + depth/5 + min(4, (static_eval − β) / 155)`, with a 31 cp improvement bonus |
| Razoring | At depth ≤ 2, if `static_eval + 286 + depth × 84 < α`, drop directly into quiescence search |
| Futility Pruning | At low depths, prune quiet moves where `static_eval + depth × 137 ≤ α` |
| Late Move Reductions (LMR) | Non-PV quiet moves reduced by `7.3 + 4.1 × ln(depth) × ln(move_index)`, precomputed at startup; minimum reduction of 7 plies on PV nodes, 4 on non-PV |
| Check Extension | Depth extended by 1 when the side to move is in check |
| Singular Extensions | A reduced-depth search with a narrowed window tests for singular moves; singular moves extended by 1 ply (`se_reduction = 4`) |
| Internal Iterative Deepening (IID) | On PV nodes without a TT hit, a reduced search populates the TT before the main search |
| Mate Distance Pruning | Alpha and beta tightened based on distance from root |

**Quiescence Search**
After reaching depth 0, a quiescence search evaluates captures and check evasions using the same alpha-beta framework. Captures losing more than `q_see_margin` (−27 cp) are pruned, and delta pruning applies when `static_eval + captured_value + 192` fails to exceed alpha.

**Draw Detection**
- Fifty-move rule (halfmove clock ≥ 100)
- Threefold repetition (Zobrist hash comparison against history)
- Insufficient material: KvK, K+minor vs K, KBvKB same-color bishops

### Transposition Table

A fixed-size hash table with a **64 MB** default size. Each entry stores the Zobrist hash, best move, depth, search flag (Exact / Lower / Upper), and a static eval. An aging mechanism prefers replacing entries from older searches.

A separate **8 MB pawn transposition table** caches pawn structure evaluations.

### Evaluation

The evaluation is hand-crafted and tapered between middlegame and endgame scores using a phase value calculated from remaining material (queen = 4, rook = 2, bishop/knight = 1, max phase = 24).

Before evaluation begins, an **`AttackCache`** is populated with precomputed bitboards covering pawn, knight, bishop, rook, and queen attacks for both sides along with aggregated defense maps. This avoids redundant attack generation across the many evaluation terms that query the same data.

**Evaluation Terms**

| Term | Description |
|---|---|
| Material | Separate MG/EG piece values (pawn: 82/94 cp, knight: 337/281 cp, bishop: 365/297 cp, rook: 477/512 cp, queen: 1025/936 cp) |
| Piece-Square Tables | MG and EG PSTs for all six piece types |
| Pawn Structure | Passed pawns (rank-scaled: 15/25/40/65/115/175 cp), isolated (−12 cp), doubled (−25 cp), protected (+8 cp), connected (+10 cp), backward (−15 cp) — cached in the pawn TT |
| King Safety | Castling bonus (+50 cp), pawn shield (+15 cp per pawn), open file penalty (−30 cp), semi-open file penalty (−15 cp); attack units from knights (+2), bishops (+2), rooks (+3), queens (+5) indexed into a 16-entry nonlinear safety table |
| Piece Activity | Mobility for bishops/rooks/queens; rook on open (+45 cp) or semi-open (+20 cp) file; rook on 7th rank (+20 cp); rook behind passer (+60 cp); trapped rook penalty (−50 cp); bad bishop penalty (−35 cp); bishop pair (+30 cp); knight outpost (+30 cp); alignment bonuses for bishops/rooks/queens targeting the opponent's king and queen |
| Threats | Hanging piece penalty (−40 cp); attacked-by-pawn penalty (−35 cp, halved if defended); attacked-by-minor penalty (−25 cp for undefended rooks/queens); attacked-by-rook penalty (−20 cp for undefended queens) |
| Exchange Avoidance | The winning side is rewarded for keeping more pieces on the board (~5 cp per piece) when the material difference exceeds 100 cp |
| Space & Center | Controlled squares in own half (+2 cp each); center squares (+10 cp each); extended center (+5 cp each); pawn advancement bonus |
| Endgame Adjustments | King proximity to passed pawns (+4 cp scaling); rook-behind-passer bonus |
| Miscellaneous | Tempo bonus (+10 cp for side to move) |
| Lazy Evaluation | Full evaluation skipped when raw material score is already outside α/β by more than 813 cp |
| Correction History | A 16K-entry per-side table corrects the static eval based on past prediction errors, updated after each search node |

### Static Exchange Evaluation (SEE)

A full SEE implementation determines whether a capture sequence on a given square wins or loses material. SEE is used in move ordering (winning/equal/losing capture classification) and in pruning decisions in both the main search and quiescence search.

---

## Tooling

The repository includes several utility scripts:

| File | Purpose |
|---|---|
| `tactics.py` | Runs the engine against a set of tactical puzzles to measure puzzle accuracy |
| `tuner.py` | SPSA search parameter tuner (see below) |
| `engine_test.sh` | Automated engine testing script |
| `run_tournament.sh` | Runs a local tournament between engine versions using Cutechess-cli |

Profiling support via [Tracy](https://github.com/wolfpld/tracy) is included in the `Tracy/` directory.

---

## Search Tuner

`tuner.py` is a Python-based [SPSA](https://www.chessprogramming.org/SPSA) tuner that optimizes Ursus's search parameters through self-play.

### How it works

SPSA (Simultaneous Perturbation Stochastic Approximation) is a gradient-free optimization algorithm well-suited to chess engine tuning, where the objective function — game outcome — is inherently noisy. Rather than perturbing parameters one at a time, SPSA simultaneously perturbs the entire parameter vector in a random ±1 direction, runs two short matches (θ+ vs θ−), and estimates the gradient from just those two results regardless of how many parameters are being tuned. This makes it dramatically more efficient than coordinate-wise search for large parameter sets.

Each iteration plays **20 games at TC 1+0.05** via `cutechess-cli`. Learning rate and perturbation size both decay over time following the standard SPSA schedules (α = 0.602, γ = 0.101, A = 100). A **150-iteration warmup phase** holds the perturbation size fixed at 2.5 to allow free exploration before committing to a finer-grained search. A hard floor of `ck ≥ 0.3` prevents the gradient denominator from shrinking into noise.

On top of vanilla SPSA, the tuner applies **Adam momentum** (β₁ = 0.9, β₂ = 0.999) to smooth gradient estimates and accelerate convergence — particularly helpful given the high variance of short match results. Checkpoints are saved every 10 iterations, and a convergence report is printed every 50 iterations, tracking each parameter's range of variation as a fraction of its allowed span and assigning a status of ✓ CONVERGED, → CONVERGING, or ✗ STILL EXPLORING.

### Parameters

All 23 tunable parameters are search heuristics with explicit bounds and perturbation step sizes:

| Parameter | Default | Range | Description |
|---|---|---|---|
| `aspiration_window` | 31 | 10–200 | Initial aspiration window size (cp) |
| `lazy_margin` | 813 | 50–1250 | Lazy evaluation threshold (cp) |
| `futility_mul` | 137 | 25–250 | Futility pruning depth multiplier |
| `iid_depth` | 1 | 1–4 | IID minimum depth |
| `razoring_base` | 286 | 50–500 | Razoring base margin (cp) |
| `razoring_mul` | 84 | 10–300 | Razoring depth multiplier |
| `lmr_base` | 73 | 25–125 | LMR base constant (×0.1) |
| `lmr_mul` | 41 | 10–100 | LMR log-product multiplier (×0.1) |
| `lmr_pv_min` | 7 | 1–10 | Minimum LMR reduction on PV nodes |
| `lmr_non_pv_min` | 4 | 1–10 | Minimum LMR reduction on non-PV nodes |
| `se_reduction` | 4 | 0–10 | Singular extension depth reduction |
| `nmp_improvement` | 31 | 10–100 | NMP improvement bonus (cp) |
| `nmp_base` | 4 | 1–8 | NMP base reduction depth |
| `nmp_depth_div` | 5 | 1–8 | NMP depth divisor |
| `nmp_beta_div` | 155 | 50–300 | NMP beta-score divisor |
| `q_see_margin` | −27 | −200–0 | QSearch SEE pruning threshold (cp) |
| `q_delta_margin` | 192 | 0–400 | QSearch delta pruning margin (cp) |
| `rfp_depth` | 7 | 1–12 | Maximum depth for RFP |
| `rfp_mul` | 90 | 10–150 | RFP depth multiplier (cp) |
| `rfp_improvement` | 41 | 10–150 | RFP improvement reduction (cp) |
| `history_div` | 6229 | 0–16384 | History score divisor for move ordering |

### Staged tuning pipeline

Rather than tuning all parameters at once, the tuner runs 8 sequential stages ordered by inter-parameter dependencies. Each stage focuses on a parameter subset and carries its results forward into the next stage.

| Stage | Focus | Target Iters | Rationale |
|---|---|---|---|
| 1 | LMR + Singular Extensions | 1500 | LMR shapes effective depth across the whole tree; SE fires on exactly the moves LMR would reduce, so they are tuned together first |
| 2 | Null Move Pruning | 800 | High Elo impact, but NMP reduction depth is calibrated against effective depths set by LMR |
| 3 | Quiescent Search | 500 | Produces the leaf scores all pruning margins are measured against — must be stable before tuning RFP|
| 4 | Reverse Futility Pruning | 800 | Depth-based forward pruning; requires stable LMR effective depths and stable QSearch leaf scores |
| 6 | History | 200 | Move ordering quality affects how many moves receive LMR reductions and how often NMP fails high |
| 7 | Independent parameters | 1200 | Low cross-stage coupling: aspiration window, lazy margin, futility multiplier, IID depth, razoring |
| 8 | Full refinement | 5000 | Joint fine-tune of all parameters together |

### Usage

```sh
# Run all stages from the beginning
python tuner.py

# Run a single stage
python tuner.py --stage stage2_nmp

# Resume the pipeline from a specific stage (loads checkpoints for skipped stages)
python tuner.py --from stage4_rfp

# List all stages and their parameters
python tuner.py --list
```

Results are written to `tuning_results/` as both JSON checkpoints and human-readable `.txt` files after every 10 iterations. The final values from stage 8 can be pasted directly back into `search.zig`.

---

## Roadmap

**NNUE Evaluation**
The long-term goal is to replace the hand-crafted evaluation with an NNUE (Efficiently Updatable Neural Network) — a shallow neural network whose input features can be incrementally updated as moves are made and unmade, keeping inference cost comparable to the current HCE. This would allow Ursus to learn positional patterns that are difficult to capture with hand-tuned terms while remaining fast enough for deep search.

**Staged Move Generation**
The current move generator produces all pseudo-legal moves in a single pass before any are searched. Staged generation would instead yield moves in priority batches — hash move first, then winning captures, then quiets — deferring each batch until the previous one fails to produce a cutoff. This avoids generating, scoring, and sorting moves that are never visited, which is particularly valuable at high depths where a beta cutoff typically occurs within the first few moves.
