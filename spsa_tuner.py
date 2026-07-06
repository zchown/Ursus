#!/usr/bin/env python3
"""
Asynchronous SPSA tuner for UCI engines, driven by fastchess.

Design:
  - N worker threads. Each worker, in a loop:
      1. Takes the iteration counter k and a snapshot of theta (under a lock).
      2. Draws a Rademacher delta (+/-1 per parameter).
      3. Computes probe vectors theta+ = theta + c_k*delta, theta- = theta - c_k*delta.
      4. Plays ONE paired match (2 games, same opening, colors reversed) between
         theta+ and theta- via a single fastchess invocation.
      5. Applies theta += a_k * result / (c_k * delta) per-parameter (under the lock),
         where result = wins(theta+) - wins(theta-) in {-2..+2}.
  - Updates are asynchronous: theta may move while a pair is in flight. This staleness
    is standard (fishtest/OpenBench work the same way) and is well-tolerated by SPSA.

Schedules (OpenBench/fishtest conventions):
  alpha = 0.602, gamma = 0.101, A = 0.1 * total_pairs
  c_k = c_end * (N / k)^gamma            -> equals c_end at the final iteration
  a_k = a_end * ((A + N) / (A + k))^alpha, a_end = r_end * c_end^2

Usage:
  python3 spsa_tuner.py --config spsa_config.json
  python3 spsa_tuner.py --config spsa_config.json --resume state.json

Requires: Python 3.8+, no third-party packages. fastchess on PATH or configured.
"""

import argparse
import json
import math
import os
import random
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

# ----------------------------------------------------------------------------
# Config / state
# ----------------------------------------------------------------------------

class Param:
    __slots__ = ("name", "value", "min", "max", "c_end", "r_end", "start")

    def __init__(self, name, d):
        self.name = name
        self.value = float(d["start"])
        self.start = float(d["start"])
        self.min = float(d["min"])
        self.max = float(d["max"])
        self.c_end = float(d["c_end"])
        self.r_end = float(d.get("r_end", 0.002))
        if not (self.min <= self.value <= self.max):
            raise ValueError(f"{name}: start {self.value} outside [{self.min}, {self.max}]")


class Tuner:
    def __init__(self, cfg):
        self.cfg = cfg
        self.params = [Param(name, d) for name, d in cfg["parameters"].items()
                       if d.get("enabled", True)]
        if not self.params:
            sys.exit("No enabled parameters in config.")
        self.N = int(cfg["spsa"]["pairs"])
        self.A = cfg["spsa"].get("A", 0.1 * self.N)
        self.alpha = cfg["spsa"].get("alpha", 0.602)
        self.gamma = cfg["spsa"].get("gamma", 0.101)

        self.lock = threading.Lock()
        self.k_launched = 0          # iterations started (drives the schedules)
        self.pairs_done = 0
        self.w = self.l = self.d = 0 # from theta+ perspective
        self.failed = 0
        self.stop = threading.Event()

        self.book = self._load_book(cfg["fastchess"]["openings"])
        self.rng = random.Random(cfg["spsa"].get("seed", None))

        self.state_path = cfg.get("state_file", "spsa_state.json")
        self.history_path = cfg.get("history_file", "spsa_history.csv")
        self._init_history()

    # -- schedules -----------------------------------------------------------

    def gains(self, k, p: Param):
        """Per-parameter (a_k, c_k) at iteration k (1-based)."""
        c_k = p.c_end * (self.N / k) ** self.gamma
        a_end = p.r_end * p.c_end * p.c_end
        a_k = a_end * ((self.A + self.N) / (self.A + k)) ** self.alpha
        return a_k, c_k

    # -- book ------------------------------------------------------------------

    @staticmethod
    def _load_book(path):
        if not os.path.exists(path):
            sys.exit(f"Opening book not found: {path}")
        with open(path, "r", errors="replace") as f:
            n = sum(1 for line in f if line.strip())
        if n == 0:
            sys.exit(f"Opening book is empty: {path}")
        return n

    # -- persistence -----------------------------------------------------------

    def _init_history(self):
        if not os.path.exists(self.history_path):
            with open(self.history_path, "w") as f:
                f.write("pairs,games,W,L,D," + ",".join(p.name for p in self.params) + "\n")

    def save_state(self):
        with self.lock:
            state = {
                "k_launched": self.k_launched,
                "pairs_done": self.pairs_done,
                "wld": [self.w, self.l, self.d],
                "theta": {p.name: p.value for p in self.params},
            }
        tmp = self.state_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f, indent=2)
        os.replace(tmp, self.state_path)

    def load_state(self, path):
        with open(path) as f:
            state = json.load(f)
        self.k_launched = state["k_launched"]
        self.pairs_done = state["pairs_done"]
        self.w, self.l, self.d = state["wld"]
        for p in self.params:
            if p.name in state["theta"]:
                p.value = state["theta"][p.name]
        print(f"Resumed at pair {self.pairs_done}, theta = {self.theta_str()}")

    # -- reporting ---------------------------------------------------------------

    def theta_str(self):
        return "  ".join(f"{p.name}={int(round(p.value))}" for p in self.params)

    def report(self):
        with self.lock:
            done, w, l, d = self.pairs_done, self.w, self.l, self.d
            line = f"{done},{2*done},{w},{l},{d}," + ",".join(f"{p.value:.3f}" for p in self.params)
            theta = self.theta_str()
        with open(self.history_path, "a") as f:
            f.write(line + "\n")
        games = 2 * done
        pct = 100.0 * done / self.N
        score = (w + 0.5 * d) / max(games, 1) * 100.0
        print(f"[{done}/{self.N} pairs, {pct:.1f}%]  +{w} -{l} ={d} ({score:.1f}%)  {theta}",
              flush=True)

    # -- one SPSA iteration -------------------------------------------------------

    def run_pair(self, worker_id):
        with self.lock:
            if self.k_launched >= self.N:
                return False
            self.k_launched += 1
            k = self.k_launched
            snapshot = [(p, p.value) for p in self.params]

        delta = [self.rng.choice((-1, 1)) for _ in snapshot]
        plus, minus, cks = {}, {}, []
        for (p, theta_i), d_i in zip(snapshot, delta):
            a_k, c_k = self.gains(k, p)
            cks.append((a_k, c_k))
            lo, hi = p.min, p.max
            plus[p.name] = int(round(max(lo, min(hi, theta_i + c_k * d_i))))
            minus[p.name] = int(round(max(lo, min(hi, theta_i - c_k * d_i))))

        result = self.play_match(plus, minus, worker_id)
        if result is None:
            with self.lock:
                self.failed += 1
            return True  # keep going; skip the update

        wp, lp, dp = result  # from theta+ perspective
        grad = wp - lp       # in {-2..2}

        with self.lock:
            for (p, _), d_i, (a_k, c_k) in zip(snapshot, delta, cks):
                if grad != 0:
                    p.value += a_k * grad / (c_k * d_i)
                    p.value = max(p.min, min(p.max, p.value))
            self.pairs_done += 1
            self.w += wp
            self.l += lp
            self.d += dp
            done = self.pairs_done
        if done % self.cfg.get("report_every", 50) == 0:
            self.report()
            self.save_state()
        return True

    # -- fastchess -----------------------------------------------------------------

    def play_match(self, plus, minus, worker_id):
        fc = self.cfg["fastchess"]
        opening_start = self.rng.randint(1, self.book)

        def eng(name, vals):
            parts = [f'cmd={fc["engine"]}', f"name={name}"]
            for k, v in vals.items():
                parts.append(f"option.{k}={v}")
            return parts

        with tempfile.TemporaryDirectory(prefix=f"spsa{worker_id}_") as tmp:
            pgn = os.path.join(tmp, "out.pgn")
            cmd = [fc.get("binary", "fastchess")]
            cmd += ["-engine"] + eng("plus", plus)
            cmd += ["-engine"] + eng("minus", minus)
            cmd += ["-each", f'tc={fc["tc"]}',
                    f'option.Threads={fc.get("threads", 1)}',
                    f'option.Hash={fc.get("hash", 16)}']
            cmd += ["-openings", f'file={fc["openings"]}', f'format={fc.get("book_format", "epd")}',
                    "order=sequential", f"start={opening_start}"]
            cmd += ["-repeat", "-rounds", "1", "-games", "2"]
            cmd += ["-concurrency", "1"]
            cmd += ["-resign", "movecount=5", "score=400"]
            cmd += ["-draw", "movecount=40", "score=10"]
            cmd += ["-pgnout", f"file={pgn}"]
            cmd += shlex.split(fc.get("extra_args", ""))

            try:
                proc = subprocess.run(cmd, capture_output=True, text=True,
                                      timeout=fc.get("pair_timeout_sec", 1200))
            except subprocess.TimeoutExpired:
                print(f"worker {worker_id}: fastchess timed out; skipping pair", file=sys.stderr)
                return None
            except FileNotFoundError:
                self.stop.set()
                sys.exit(f'fastchess binary not found: {fc.get("binary", "fastchess")}')

            res = self._parse_pgn(pgn)
            if res is None:
                res = self._parse_stdout(proc.stdout)
            if res is None:
                print(f"worker {worker_id}: could not parse result\n--- stdout ---\n"
                      f"{proc.stdout[-2000:]}\n--- stderr ---\n{proc.stderr[-2000:]}",
                      file=sys.stderr)
            return res

    @staticmethod
    def _parse_pgn(path):
        if not os.path.exists(path):
            return None
        w = l = d = games = 0
        white = result = None
        with open(path, errors="replace") as f:
            for line in f:
                m = re.match(r'\[White "(.*)"\]', line)
                if m:
                    white = m.group(1)
                m = re.match(r'\[Result "(.*)"\]', line)
                if m:
                    result = m.group(1)
                    if result == "1/2-1/2":
                        d += 1
                    elif result == "1-0":
                        w += white == "plus" and 1 or 0
                        l += white == "minus" and 1 or 0
                    elif result == "0-1":
                        w += white == "minus" and 1 or 0
                        l += white == "plus" and 1 or 0
                    else:
                        return None  # "*" — unfinished game
                    games += 1
        return (w, l, d) if games == 2 else None

    @staticmethod
    def _parse_stdout(out):
        hits = re.findall(r"Score of plus vs minus: (\d+) - (\d+) - (\d+)", out)
        if not hits:
            return None
        w, l, d = map(int, hits[-1])
        return (w, l, d) if w + l + d == 2 else None

    # -- engine sanity check ---------------------------------------------------------

    def verify_engine(self):
        fc = self.cfg["fastchess"]
        engine = fc["engine"]
        if not os.path.exists(engine):
            sys.exit(f"Engine not found: {engine}")
        try:
            proc = subprocess.Popen([engine], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    text=True)
            proc.stdin.write("uci\n")
            proc.stdin.flush()
            opts, deadline = {}, time.time() + 10
            while time.time() < deadline:
                line = proc.stdout.readline()
                if not line:
                    break
                m = re.match(r"option name (\S+) type spin default (-?\d+) min (-?\d+) max (-?\d+)",
                             line.strip())
                if m:
                    opts[m.group(1)] = (int(m.group(3)), int(m.group(4)))
                if line.strip() == "uciok":
                    break
            proc.stdin.write("quit\n")
            proc.stdin.flush()
            proc.wait(timeout=5)
        except Exception as e:
            sys.exit(f"Failed to interrogate engine over UCI: {e}")

        ok = True
        for p in self.params:
            if p.name not in opts:
                print(f"ERROR: engine does not expose option '{p.name}' "
                      f"(commented out in uci.zig?)", file=sys.stderr)
                ok = False
                continue
            emin, emax = opts[p.name]
            # Probes can reach start +/- c_1; make sure the engine's setoption clamps
            # can never silently flatten a probe.
            c1 = p.c_end * self.N ** self.gamma
            reach_lo, reach_hi = p.min, p.max
            if reach_lo < emin or reach_hi > emax:
                print(f"ERROR: '{p.name}' config bounds [{p.min:.0f},{p.max:.0f}] exceed engine "
                      f"clamps [{emin},{emax}] — probes would be silently clamped. "
                      f"Tighten the config bounds or widen the engine clamps.", file=sys.stderr)
                ok = False
            if c1 > (p.max - p.min) / 2:
                print(f"WARNING: '{p.name}' initial c_1={c1:.1f} is large vs range "
                      f"[{p.min:.0f},{p.max:.0f}]; early probes will pin to the bounds.",
                      file=sys.stderr)
        if not ok:
            sys.exit(1)
        print(f"Engine OK — all {len(self.params)} tuned options present, bounds compatible.")

    # -- main loop ----------------------------------------------------------------------

    def run(self):
        self.verify_engine()
        conc = int(self.cfg.get("concurrency", os.cpu_count() or 1))
        print(f"Tuning {len(self.params)} parameters, {self.N} pairs "
              f"({2 * self.N} games), concurrency {conc}, tc {self.cfg['fastchess']['tc']}")
        print("Start:", self.theta_str())

        def worker(wid):
            while not self.stop.is_set():
                if not self.run_pair(wid):
                    return

        def on_sigint(sig, frame):
            print("\nStopping after in-flight pairs finish...", flush=True)
            self.stop.set()

        signal.signal(signal.SIGINT, on_sigint)

        with ThreadPoolExecutor(max_workers=conc) as ex:
            futs = [ex.submit(worker, i) for i in range(conc)]
            for f in futs:
                f.result()

        self.report()
        self.save_state()
        print("\n=== FINAL VALUES ===")
        for p in self.params:
            v = int(round(p.value))
            print(f"setoption name {p.name} value {v}")
        print("\nFor tunable_parameters.zig:")
        for p in self.params:
            print(f"pub var {p.name} = {int(round(p.value))};")
        if self.failed:
            print(f"\n({self.failed} pairs failed to parse and were skipped)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--resume", help="state json from a previous run")
    args = ap.parse_args()
    with open(args.config) as f:
        cfg = json.load(f)
    t = Tuner(cfg)
    if args.resume:
        t.load_state(args.resume)
    t.run()


if __name__ == "__main__":
    main()
