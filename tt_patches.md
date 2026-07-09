# Why 4-slot buckets lose ~2 Elo, and what to test

## TL;DR

The premise "4th slot is free real estate" is correct on the *memory* side — `@sizeOf(Bucket)` stays 64, `num_buckets` is identical, you get +33% entries in the same footprint, alignment is preserved by `alignedAlloc(..., .@"64", ...)`. The cost is on the *instruction* side: both `get()` and `set()` scan every slot on the common paths, each slot touch is an `std.atomic.Value(u128)` operation, and your replacement/aging policy suppresses most of the retention benefit the 4th slot would otherwise buy. Measured on a faithful replica of your hot path, the 4th slot adds **+13% to the TT path on an AVX build and +20% on an x86-64-v2 build** in the cache-hot (post-prefetch) regime. At a typical 10–15% TT share of node time, that is ~1–3% NPS, which at 8+0.08 is ~1–3 Elo. That is your regression.

Secondary finding: `std.atomic.Value(u128)` does not compile at baseline `x86_64` (no `cx16`), and at `x86_64_v2` every load and store compiles to `lock cmpxchg16b` — a full locked RMW, so even *probes* dirty the cache line. Only at v3+/AVX does it become a plain `vmovdqa`. Check what your test workers actually build with (see Appendix B).

---

## 1. Measured evidence

Microbenchmark replicating your exact `PackedEntry` layout, `get()` scan, and `set()` scoring scan (Zig 0.16, `-O ReleaseFast`, one probe + one store per "node", ~45% probe hit rate, mixed ages). Variant A is your current `atomic.Value(u128)` scheme; variant B is the same 128-bit layout split into two `u64` halves with an XOR tear-guard (Patch 1 below).

Cache-resident table (1 MB — models the realistic case since you prefetch one node ahead at search.zig:1021/1317):

| Build tier | A: u128, 3 slots | A: u128, 4 slots | Δ | B: 2×u64, 3 slots | B: 2×u64, 4 slots | Δ |
|---|---|---|---|---|---|---|
| x86-64-v2 (`lock cmpxchg16b`) | 90.2 ns | 108.5 ns | **+20.3%** | 39.4 ns | 41.8 ns | +6.1% |
| x86-64-v3 (`vmovdqa`) | 40.5 ns | 45.9 ns | **+13.3%** | 40.4 ns | 42.6 ns | +5.4% |

DRAM-bound configs (64 MB / 16 MB tables, uniform random buckets, no prefetch) show the same ordering with smaller relative deltas (+4–12%) because memory latency masks instruction cost; your engine's prefetching puts you closer to the cache-resident row.

Three things to read off this table:

1. The 4th slot is not free in instruction count. `get()` on a miss loads all slots; `set()` *always* loads all slots and runs the scoring chain (`getDepth`/`getAge`/`getIsPv`/`getFlag` — each a 128-bit shift+truncate) on every non-matching one. Stores happen at nearly every node (main search + every qsearch node), so per node you pay up to 8 slot touches at 4 slots vs 6 at 3.
2. On a v2-tier build the situation is much worse: 25 `lock cmpxchg16b` sites in the binary; a locked RMW per slot touch, ~5× the cost of the split-u64 scheme.
3. The split-u64 scheme makes the marginal slot nearly free (+2.4 ns at v2, +2.2 ns at v3), which is what makes a 4th slot viable at all.

Instruction audit: `objdump -d` shows `cmpxchg16b` count 25 at v2, 0 at v3/native. Baseline `x86_64` fails to compile (`error: expected 64-bit integer type or smaller`), which at least rules out the silent libcall-spinlock tier.

### Why the capacity gain doesn't pay for it at 8+0.08

At this TC you search on the order of 10⁵–10⁶ nodes per move against 3.1M entries (64 MB, 3 slots). Occupancy pressure within one move's search is low, so the marginal value of +33% entries is small to begin with — and three policy choices in the current code actively discard what extra retention would preserve:

- `incrementAge()` runs after **every** `go` (search.zig:500), and `set()` scores any non-current-age entry at `depth − 256`. The entire previous move's tree — the single most reusable data you have — becomes the designated eviction victim on the very next move. A depth-0 qsearch entry from the current search outranks a depth-40 PV entry from one move ago.
- `get()` never refreshes age, and the TT-cutoff path (search.zig:613–623) returns without re-storing. So the hottest entries — the ones serving cutoffs — keep stale ages and are first against the wall.
- On a key match, `set()` overwrites unconditionally. Every qsearch store (depth 0, flag from a stand-pat or capture-only scan) stomps a deep main-search entry for the same position. Razoring (search.zig:739) drops main-search positions straight into qsearch, so this is common, not exotic.

Net: with 3 slots the policy damage is masked because eviction pressure destroys entries anyway; with 4 slots you pay the scan cost immediately while the policy prevents the retention benefit from materializing. Cost real, benefit suppressed → −2 Elo.

### Second-order search couplings (smaller, worth knowing)

Higher hit rates are not purely positive in this search. `tt_hit` gates IIR (search.zig:712) — more hits, fewer reductions, bigger tree per depth. `tt_is_pv` grants `reduction -= 1` (search.zig:1059), and since qsearch always stores `is_pv=false` and match-stomps, the `is_pv` signal is noisy; retaining more of it slightly inflates NonPV trees. These don't explain −2 Elo alone but they shave the upside of extra retention.

---

## 2. Genuine bugs found along the way

**B1 — qsearch returns TT mate scores without un-adjusting for ply.** Stores go through `scoreToTT(score, ply)` (adds ply to mate scores), and the negamax probe undoes it (search.zig:600–604), but the qsearch cutoff (search.zig:1197–1203) returns `e.eval` raw. Mate distances near the tips are off by up to the storing node's ply; the `±20` fudge in `formatScore` looks like a symptom of this. Fix in Patch 6.

**B2 — boundary mismatch in mate adjustment.** `scoreToTT` triggers at `score >= mate_score − 256`; the probe un-adjusts at `tt_eval > mate_score − 256`. Harmless in practice but the pair should be one shared helper (Patch 6).

**B3 — `compareAndSwap` is dead and broken-by-design.** No call sites in search.zig, and it packs the *expected* entry with `current_age`, so it can never match an entry stored under a previous age. Delete it (grep the rest of the codebase first), or port it to the new slot format if something else uses it.

**B4 — LMP suppresses TT stores entirely.** The end-of-node store is gated on `!skip_quiet` (search.zig:1133). Every node where LMP fired stores nothing, so a large class of shallow NonPV nodes gets fully re-expanded on revisit. Standard practice is to store the fail-low anyway. Patch 5.

---

## 3. Patch set

Each patch is independent and SPRT-able on its own. Suggested order and bounds are in §4.

### Patch 1 — split each slot into two `u64` halves with an XOR tear-guard

Replaces `atomic.Value(u128)` with two relaxed `u64`s per slot. Same 128-bit bit layout, same 64-byte bucket. `lo` holds bits 0–63, and the second word stores `hi ^ lo`; a torn read reconstructs garbage in the key bits (which deliberately live in *both* halves: hash-upper in bits 0–31, hash-lower in bits 101–127), so `verify()` rejects it at ~2⁻²⁷ — comfortably below the 2⁻³⁹ effective-key collision rate you already tolerate. This is the Hyatt lockless-hashing scheme; Stockfish gets by with even weaker guarantees (racy 10-byte entries + key16).

Effect: kills `cmpxchg16b` on v2 targets (~2.3× faster TT path there), makes each slot touch two plain 8-byte movs everywhere, and drops the marginal cost of a 4th slot to ~2 ns/node. This is the patch that makes 4 slots winnable.

```zig
pub const TT_BUCKET_SLOTS = 3; // revisit 4 after this lands — see §4

const Slot = struct {
    lo: std.atomic.Value(u64),
    hi_x: std.atomic.Value(u64), // stores (hi ^ lo)

    inline fn loadPacked(self: *Slot) u128 {
        const lo = self.lo.load(.monotonic);
        const hi = self.hi_x.load(.monotonic) ^ lo;
        return (@as(u128, hi) << 64) | @as(u128, lo);
    }

    inline fn storePacked(self: *Slot, d: u128) void {
        const lo: u64 = @truncate(d);
        const hi: u64 = @truncate(d >> 64);
        self.lo.store(lo, .monotonic);
        self.hi_x.store(hi ^ lo, .monotonic);
    }

    inline fn clearSlot(self: *Slot) void {
        self.lo.store(0, .monotonic);
        self.hi_x.store(0, .monotonic);
    }
};

pub const Bucket = struct {
    entries: [TT_BUCKET_SLOTS]Slot,
    _pad: [(64 - TT_BUCKET_SLOTS * 16) % 64]u8, // 16B at 3 slots, 0B at 4

    pub fn init() Bucket {
        var b: Bucket = undefined;
        for (&b.entries) |*e| e.clearSlot();
        b._pad = @splat(0);
        return b;
    }
};
```

`get` and `set` change only at the load/store sites:

```zig
    pub fn get(self: *TranspositionTable, hash: zob.ZobristKey) ?Entry {
        const bucket = &self.buckets[self.index(hash)];
        for (&bucket.entries) |*slot| {
            const packed_entry = PackedEntry{ .data = slot.loadPacked() };
            // verify first: on the common miss path this rejects on two
            // 64-bit compares without touching the flag bits
            if (packed_entry.verify(hash) and packed_entry.getFlag() != .None) {
                return packed_entry.unpack(hash);
            }
        }
        return null;
    }
```

and in `set`, `atomic_entry.load(.acquire)` → `slot.loadPacked()`, final `bucket.entries[target_idx].store(new_packed.data, .release)` → `bucket.entries[target_idx].storePacked(new_packed.data)`. `clear()` uses `clearSlot()`. Update the comptime block: keep `@sizeOf(Bucket) == 64`, drop the "PackedEntry must be 16 bytes for atomic operations" wording (the layout stays 16 bytes regardless). Delete `compareAndSwap` (see B3).

Caveat: this trades hard atomicity for probabilistic tear detection. That is the standard engine trade; if you keep a strict-correctness debug mode, keep the u128 path behind a build flag.

### Patch 2 — graded aging instead of the −256 nuke

Make the age penalty proportional so last-move deep entries outrank current-move shallow junk, while genuinely old entries still die fast. `age` is a wrapping u8, so use wrapping subtraction.

```zig
            // 2. Score the entry to find the weakest link for collision handling
            var score: i32 = packed_entry.getDepth();
            const rel_age: u8 = current_age -% packed_entry.getAge();
            score -= 8 * @as(i32, @min(rel_age, 28)); // was: -256 for any age mismatch
            if (packed_entry.getIsPv()) score += 2;
            if (flag == .Exact) score += 1;
```

The `8` is the interesting tunable (try 4–12). One age step = one game move; at 8, a previous-move entry needs depth ≥ 8 more than a current-move rival to survive, which preserves exactly the deep reusable stuff.

### Patch 3 — refresh age on probe hit

Hot entries that serve cutoffs currently never get their age updated (the cutoff path returns without storing). Refresh in `get()`, only when the age actually differs, so the common case adds zero stores:

```zig
            if (packed_entry.verify(hash) and packed_entry.getFlag() != .None) {
                const current_age = self.getAge();
                if (packed_entry.getAge() != current_age) {
                    const age_mask: u128 = @as(u128, 0xFF) << 90;
                    const refreshed = (packed_entry.data & ~age_mask) |
                        (@as(u128, current_age) << 90);
                    slot.storePacked(refreshed); // benign race; TT-tolerable
                }
                return packed_entry.unpack(hash);
            }
```

Synergizes with Patch 2 (graded aging decides *how much* protection; refresh decides *who* gets it). SMP caveat: extra stores on probe increase cache-line invalidation across threads — fine at 1–2 threads; re-verify at your SMP config before shipping.

### Patch 4 — depth guard on same-key overwrite

Stop depth-0 qsearch stores from stomping deep entries for the same position. Stockfish-style: overwrite on match only if the new bound is exact, the new depth is close, or the old entry is from a previous age.

```zig
        // 3. Determine the write target: Match > Empty > Worst
        const target_idx = match_idx orelse empty_idx orelse worst_idx;

        if (match_idx != null) {
            const old = PackedEntry{ .data = bucket.entries[target_idx].loadPacked() };
            const keep_old = entry.flag != .Exact and
                old.getAge() == current_age and
                @as(i32, old.getDepth()) >= @as(i32, entry.depth) + 4;
            if (keep_old) return; // deep data survives; move was already merged above
        }
```

The `+4` margin is tunable (2–6). Note the existing move-merge (`best_move`) already runs before this point, so the hash move still benefits from the newer search when the old entry is kept — if you want that, write back `old` with the merged move instead of plain `return`; test both, the plain `return` is simpler and usually enough.

### Patch 5 — store at LMP-skipped nodes

search.zig:1133, drop the `!skip_quiet` gate:

```zig
        if (self.excluded_moves[self.ply].toU32() == 0) {
            var tt_flag = tt.EstimationType.Over;
            ...
```

The stored `Over` bound is heuristic (unsearched moves are assumed ≤ alpha), which is exactly the assumption LMP already made. Keep the `searched_moves == 0 → return alpha` early-out above it unchanged.

### Patch 6 — mate-score symmetry between store and probe (correctness)

Add the inverse helper next to `scoreToTT` and use it at both probe sites:

```zig
inline fn scoreFromTT(score: i32, ply: usize) i32 {
    if (score >= eval.mate_score - 256) return score - @as(i32, @intCast(ply));
    if (score <= -eval.mate_score + 256) return score + @as(i32, @intCast(ply));
    return score;
}
```

In negamax replace the hand-rolled block at search.zig:600–604 with `tt_eval = scoreFromTT(tt_eval, self.ply)` (also fixes the `>` vs `>=` boundary mismatch, B2). In qsearch, adjust before use:

```zig
        if (entry) |e| {
            qs_tt_hit = true;
            hash_move = e.move;
            qs_tt_in_check = e.in_check;
            qs_tt_static_eval = e.static_eval;
            qs_tt_static_eval_valid = e.static_eval_valid;
            const tt_score = scoreFromTT(e.eval, self.ply);
            if (e.flag == .Exact) {
                return tt_score;
            } else if (e.flag == .Under and tt_score >= beta) {
                return tt_score;
            } else if (e.flag == .Over and tt_score <= alpha) {
                return tt_score;
            }
        }
```

Roughly Elo-neutral; removes corrupted mate distances and should let you delete the `±20` fudge in `formatScore` eventually.

### Patch 7 — OR-merge `is_pv` on match (small)

Since `tt_is_pv` feeds an LMR reduction, don't let qsearch/NonPV stores erase the PV flag on a matched key. In `set`, where the match is found:

```zig
            if (packed_entry.verify(entry.hash)) {
                match_idx = i;
                if (best_move.isNull() and !packed_entry.getMove().isNull()) {
                    best_move = packed_entry.getMove();
                }
                if (packed_entry.getIsPv()) is_pv_merged = true; // OR with entry.is_pv
                break;
            }
```

(introduce `var is_pv_merged = entry.is_pv;` before the loop and pass it to `pack`). Test bundled with Patch 4 if you want to save SPRT slots.

---

## 4. Test plan

Order matters because Patch 1 changes the cost model that everything else is judged against.

1. **P0 (no SPRT, one afternoon):** confirm your workers' build tier: `objdump -d ./engine | grep -c cmpxchg16b`. If nonzero, add `-Dcpu=x86_64_v3` (or `native` for homogeneous workers) to the test build and re-measure NPS before anything else — this alone may recover the 2 Elo and more.
2. **Patch 1** as a non-regression / small-gain test, e.g. SPRT [−1.5, 3.5] at STC. Expect neutral-to-positive at v3 builds, clearly positive at v2 builds. Measure NPS alongside (bench-to-bench NPS diff is the leading indicator here).
3. **Patch 2**, then **Patch 3** on top, standard gainer bounds [0, 4] or your usual. These are the highest-expected-value policy patches; graded aging alone has historically been worth a few Elo in engines that previously nuked old generations.
4. **Patch 4** (+7 optionally bundled) and **Patch 5** as separate gainers.
5. **Re-test 4 slots only after 1–3 are merged**, since that's when the marginal slot is cheap and retention actually persists. Run it three ways: default hash at STC, 16 MB hash at STC (capacity-bound — the 4th slot's best case), and one LTC confirmation. If 4 slots doesn't win at small-hash STC after these patches, keep 3 and the padding; that outcome would match the long-standing Stockfish result that 3×16 is the sweet spot when scan cost is nonzero.
6. **Patch 6** can merge on correctness grounds with a quick non-regression run.

One honesty note on the original observation: ~2 Elo at 8+0.08 needs on the order of 30–60k paired games to resolve outside noise, so if the individual runs were shorter, part of "keeps losing ~2" may be variance — but the mechanism above is real and measurable regardless, and fixing it is worth more than the 2 Elo either way.

---

## Appendix A — benchmark methodology

`bench.zig` (shipped alongside this document) replicates `PackedEntry`'s exact bit layout, `get()`'s scan (flag + 59-bit verify) and `set()`'s full scoring scan, parameterized over slot count and slot representation. Workload: 20M iterations of one probe + one store, 45% of probes against a 64K-entry ring of recently stored keys, mixed ages in the prefill to exercise the age branch, min-of-3 timing, `doNotOptimizeAway` on results. Build/run:

```
zig build-exe bench.zig -O ReleaseFast -mcpu=x86_64_v2 -femit-bin=bench_v2
zig build-exe bench.zig -O ReleaseFast -mcpu=x86_64_v3 -femit-bin=bench_v3
./bench_v2 && ./bench_v3
```

The 64/16 MB configs are DRAM-latency-bound (uniform random buckets, no prefetch) and understate instruction-cost differences; the 1 MB config models the cache-hot post-prefetch case your engine mostly operates in. Absolute ns/node numbers are not comparable to in-engine costs — only the relative deltas between variants are load-bearing.

## Appendix B — checking a build's atomic tier

```
objdump -d engine | grep -c cmpxchg16b     # >0  → v2 tier: every TT slot touch is a locked RMW
objdump -d engine | grep -c vmovdqa        # AVX loads present → v3+ tier
```

Baseline `x86_64` (no `cx16`) refuses to compile `atomic.Value(u128)` in Zig 0.16, so any binary you have is at least v2 — the question is only v2 vs v3+.
