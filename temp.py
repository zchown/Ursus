#!/usr/bin/env python3
"""
compute_branching_factor.py

Parses UCI 'info depth ... nodes ...' engine output (e.g. a Stockfish bench
log containing many back-to-back iterative-deepening searches, one per
position) and computes the engine's effective branching factor (EBF).

Two EBF definitions are computed for each search:

1. Ratio EBF   : nodes(d) / nodes(d-1), averaged over all depth transitions.
                 This is the simple, commonly-used definition.

2. Asymptotic EBF: solves b* + b*^2 + ... + b*^d = N_total for b*, the
                 classic Russell & Norvig / Knuth definition of the branching
                 factor a uniform tree of depth d would need to produce the
                 same total node count. More stable when node counts are noisy.

Usage:
    python compute_branching_factor.py engine_log.txt
    cat engine_log.txt | python compute_branching_factor.py -
"""

import re
import sys
import statistics
from dataclasses import dataclass, field

INFO_RE = re.compile(r"\bdepth (\d+)\b.*?\bnodes (\d+)\b")


@dataclass
class Search:
    """One iterative-deepening search (i.e. one position/'go' command)."""
    depths: list = field(default_factory=list)
    nodes: list = field(default_factory=list)


def parse_log(lines):
    """Group consecutive 'info depth' lines into separate searches.

    A new search is started whenever depth does not strictly increase
    relative to the previous line -- that's how iterative deepening resets
    to depth 1 for the next position.
    """
    searches = []
    current = None
    last_depth = None

    for line in lines:
        m = INFO_RE.search(line)
        if not m:
            continue
        depth, nodes = int(m.group(1)), int(m.group(2))

        if current is None or depth <= last_depth:
            current = Search()
            searches.append(current)

        current.depths.append(depth)
        current.nodes.append(nodes)
        last_depth = depth

    return searches


def ratio_ebf(search):
    """nodes(d) / nodes(d-1) for each consecutive depth pair."""
    ratios = []
    for i in range(1, len(search.nodes)):
        prev, cur = search.nodes[i - 1], search.nodes[i]
        if prev > 0:
            ratios.append(cur / prev)
    return ratios


def asymptotic_ebf(search, tol=1e-9, max_iter=200):
    """Solve b* + b*^2 + ... + b*^d = N_total for b* via bisection."""
    d = search.depths[-1]
    n_total = search.nodes[-1]
    if d < 1 or n_total <= 0:
        return None

    def f(b):
        return sum(b ** i for i in range(1, d + 1)) - n_total

    lo, hi = 1.0, 100.0
    while f(hi) < 0 and hi < 1e6:
        hi *= 2
    if f(lo) > 0:
        return 1.0

    for _ in range(max_iter):
        mid = (lo + hi) / 2
        if f(mid) > 0:
            hi = mid
        else:
            lo = mid
        if hi - lo < tol:
            break

    return (lo + hi) / 2


def main():
    if len(sys.argv) < 2:
        print("Usage: python compute_branching_factor.py <logfile>   (use - for stdin)")
        sys.exit(1)

    src = sys.argv[1]
    if src == "-":
        lines = sys.stdin.readlines()
    else:
        with open(src, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

    searches = parse_log(lines)
    if not searches:
        print("No 'info depth ... nodes ...' lines found in the input.")
        sys.exit(1)

    all_ratio_ebfs = []
    all_asymp_ebfs = []

    print(f"{'#':>4} {'depths':>8} {'final nodes':>12} {'ratio EBF':>10} {'asymp EBF':>10}")
    print("-" * 50)

    for i, s in enumerate(searches, 1):
        ratios = ratio_ebf(s)
        avg_ratio = statistics.mean(ratios) if ratios else float("nan")
        asymp = asymptotic_ebf(s)

        if ratios:
            all_ratio_ebfs.append(avg_ratio)
        if asymp is not None:
            all_asymp_ebfs.append(asymp)

        asymp_str = f"{asymp:.3f}" if asymp is not None else "n/a"
        print(f"{i:>4} {len(s.depths):>8} {s.nodes[-1]:>12} {avg_ratio:>10.3f} {asymp_str:>10}")

    print("-" * 50)
    print(f"Positions analyzed:      {len(searches)}")
    print(f"Mean ratio EBF:          {statistics.mean(all_ratio_ebfs):.4f}")
    print(f"Median ratio EBF:        {statistics.median(all_ratio_ebfs):.4f}")
    if len(all_ratio_ebfs) > 1:
        print(f"Std dev (ratio EBF):     {statistics.stdev(all_ratio_ebfs):.4f}")
    print(f"Mean asymptotic EBF:     {statistics.mean(all_asymp_ebfs):.4f}")
    print(f"Median asymptotic EBF:   {statistics.median(all_asymp_ebfs):.4f}")


if __name__ == "__main__":
    main()
