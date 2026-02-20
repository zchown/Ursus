"""
Ursus SPSA Tuner
=================
Stage order rationale:
  1. LMR + SE   - LMR is the most pervasive heuristic: it shapes effective depth
                  across the entire tree.  se_reduction is directly coupled to LMR
                  because singular extensions fire precisely when LMR would have
                  reduced a move but it turns out to be singular.  Tune together.
  2. NMP        - High Elo impact, but nmp_base / nmp_depth_div are calibrated
                  against effective depths that LMR sets.  Tune after LMR is settled.
  3. Q-Search   - Produces the leaf scores every pruning margin is measured against.
                  rfp_mul, futility_mul, razoring_* all ask "is the
                  static eval far enough from beta to prune?" - that question only
                  has a stable answer once QSearch is correct.
  4. RFP + LMP  - Depth-based and move-count forward pruning.  Stable LMR + QSearch
                  baseline needed.  lmp_base / lmp_mul share the same dependency.
  5. History    - Move ordering quality directly affects how many moves receive LMR
                  reductions and how often NMP fails high.  Tune after the heuristics
                  it feeds into are settled.
  7. Independent - Low-coupling parameters: aspiration window, lazy eval margin,
                  futility multiplier, IID depth, razoring.  Minimal cross-stage
                  dependencies so order within this group matters less.
  8. Refinement - Full joint fine-tune pass.

"""

import subprocess
import random
import json
import os
import math
import sys
import argparse
from collections import deque

ENGINE     = "./zig-out/bin/Ursus"
CUTECHESS  = "cutechess-cli"
TC         = "1+0.05"
OUTPUT_DIR = "tuning_results"

GAMES_PER_ITER = 10


C_INIT       = 2.5    # Perturbation size at iteration 1 (and during warmup)
A            = 100    # Stability constant — delays learning-rate decay
ALPHA        = 0.602  # Standard SPSA learning-rate decay exponent
GAMMA        = 0.101  # Standard SPSA perturbation decay exponent

# Perturbation stays fixed for the first WARMUP_ITERS iterations so the
# optimiser can freely explore before committing to a tighter search.
WARMUP_ITERS = 150

# Hard floor on ck: prevents the perturbation (and therefore the gradient
# denominator) from decaying so small that noise dominates.
CK_MIN = 0.3

# Adam momentum hyper-parameters
ADAM_BETA1   = 0.9
ADAM_BETA2   = 0.999
ADAM_EPS     = 1e-8
ADAM_ENABLED = True 

ALL_PARAMS = {
    # Search window / independent
    "aspiration_window": {"value": 39,   "min": 10,   "max": 200,   "step": 5 },
    "lazy_margin":       {"value": 810,  "min": 50,   "max": 1250,  "step": 5 },
    "futility_mul":      {"value": 165,   "min": 25,   "max": 250,   "step": 5 },
    "iid_depth":         {"value": 1,    "min": 1,    "max": 4,     "step": 1 },
    "razoring_base":     {"value": 294,  "min": 50,   "max": 500,   "step": 5 },
    "razoring_mul":      {"value": 88,  "min": 10,   "max": 300,   "step": 5 },
    # LMR + singular extensions (coupled — tune together)
    "lmr_base":          {"value": 64,   "min": 25,   "max": 125,   "step": 5 },
    "lmr_mul":           {"value": 36,   "min": 10,   "max": 100,   "step": 5 },
    "lmr_pv_min":        {"value": 7,    "min": 1,    "max": 10,    "step": 1 },
    "lmr_non_pv_min":    {"value": 4,    "min": 1,    "max": 10,    "step": 1 },
    "se_reduction":      {"value": 4,    "min": 0,    "max": 10,    "step": 1 },
    # NMP
    "nmp_improvement":   {"value": 23,   "min": 10,   "max": 100,   "step": 5 },
    "nmp_base":          {"value": 3,    "min": 1,    "max": 8,     "step": 1 },
    "nmp_depth_div":     {"value": 5,    "min": 1,    "max": 8,     "step": 1 },
    "nmp_beta_div":      {"value": 155,  "min": 50,   "max": 300,   "step": 5 },
    # Quiescent search
    "q_see_margin":      {"value": -35,  "min": -200, "max": 0,     "step": 5 },
    "q_delta_margin":    {"value": 184,  "min": 0,    "max": 400,   "step": 5 },
    # RFP
    "rfp_depth":         {"value": 7,    "min": 1,    "max": 12,    "step": 1 },
    "rfp_mul":           {"value": 102,   "min": 10,   "max": 150,   "step": 5 },
    "rfp_improvement":   {"value": 24,   "min": 10,   "max": 150,   "step": 5 },
    # LMP
    "lmp_base":          {"value": 5,    "min": 1,    "max": 10,    "step": 1 },
    "lmp_mul":           {"value": 2,    "min": 1,    "max": 15,    "step": 1 },

    "history_div":       {"value": 9319, "min": 1000,    "max": 12000, "step": 100},
}

STAGE_ORDER = [
    "stage1_lmr",
    "stage2_nmp",
    "stage3_q_search",
    "stage4_rfp",
    "stage6_history",
    "stage7_independent",
    "stage8_refinement",
]

STAGES = {
    "stage1_lmr": {
        "name": "LMR + Singular Extensions",
        "params": [
            "lmr_base", "lmr_mul", "lmr_pv_min", "lmr_non_pv_min",
            "se_reduction",
        ],
        "target_iters": 250,
        "description": (
            "Most pervasive heuristic — shapes effective depth across the whole tree. "
            "se_reduction is directly coupled: singular extensions re-expand exactly "
            "the moves LMR would reduce."
        ),
    },
    "stage2_nmp": {
        "name": "Null Move Pruning",
        "params": ["nmp_improvement", "nmp_base", "nmp_depth_div", "nmp_beta_div"],
        "target_iters": 200,
        "description": (
            "High Elo impact. nmp_base / nmp_depth_div are calibrated against "
            "the effective depths set by LMR, so LMR must be settled first."
        ),
    },
    "stage3_q_search": {
        "name": "Quiescent Search",
        "params": ["q_see_margin", "q_delta_margin"],
        "target_iters": 150,
        "description": (
            "Produces the leaf scores that all pruning margins are measured against. "
            "Must be stable before tuning RFP / ProbCut / futility margins."
        ),
    },
    "stage4_rfp": {
        "name": "Reverse Futility Pruning + LMP",
        "params": ["rfp_depth", "rfp_mul", "rfp_improvement", "lmp_base", "lmp_mul"],
        "target_iters": 400,
        "description": (
            "Depth-based and move-count forward pruning. Requires stable LMR "
            "(effective depths) and stable QSearch (leaf scores). lmp_base / lmp_mul "
            "share the same dependency and scale with depth."
        ),
    },
    "stage6_history": {
        "name": "History Heuristic",
        "params": ["history_div"],
        "target_iters": 200,
        "description": (
            "Move ordering quality directly affects how many moves receive LMR "
            "reductions and how often NMP fails high. Tune after those are settled."
        ),
    },
    "stage7_independent": {
        "name": "Independent Parameters",
        "params": [
            "aspiration_window", "lazy_margin", "futility_mul",
            "iid_depth", "razoring_base", "razoring_mul",
        ],
        "target_iters": 750,
        "description": (
            "Low cross-stage coupling. Aspiration window, lazy eval margin, "
            "futility multiplier, IID depth, razoring."
        ),
    },
    "stage8_refinement": {
        "name": "Full Refinement",
        "params": list(ALL_PARAMS.keys()),
        "target_iters": 5000,
        "description": "Joint fine-tune of all parameters together.",
    },
}

def checkpoint_path(stage_key: str) -> str:
    return os.path.join(OUTPUT_DIR, f"checkpoint_{stage_key}.json")


def save_checkpoint(stage_key: str, iteration: int, params: dict):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    data = {
        "stage":        stage_key,
        "iteration":    iteration,
        "params_float": {k: v["value"]      for k, v in params.items()},
        "params_int":   {k: int(v["value"]) for k, v in params.items()},
    }
    with open(checkpoint_path(stage_key), "w") as f:
        json.dump(data, f, indent=2)

    txt_path = os.path.join(OUTPUT_DIR, f"tuned_params_{stage_key}.txt")
    with open(txt_path, "w") as f:
        f.write(f"# {STAGES[stage_key]['name']} — iteration {iteration}\n\n")
        for k, v in params.items():
            f.write(f"{k} = {int(v['value'])}\n")


def load_checkpoint(stage_key: str) -> dict | None:
    path = checkpoint_path(stage_key)
    if not os.path.exists(path):
        return None
    with open(path) as f:
        return json.load(f).get("params_float")


def build_stage_params(stage_key: str, carry: dict | None = None) -> dict:
    """
    Construct the working params dict for a stage.
    carry is a {name: float_value} dict of values from previous stages.
    Any param name not found in ALL_PARAMS is skipped with a warning.
    """
    params = {}
    for name in STAGES[stage_key]["params"]:
        if name not in ALL_PARAMS:
            print(f"  WARNING: '{name}' listed in {stage_key} but not in "
                  f"ALL_PARAMS — skipping.")
            continue
        params[name] = ALL_PARAMS[name].copy()
        if carry and name in carry:
            params[name]["value"] = float(carry[name])
    return params


def sep(char="=", w=80):
    print(char * w)

_first_run = True


def run_match(params_a: dict, params_b: dict, games: int = GAMES_PER_ITER) -> float:
    """
    Run a cutechess-cli match.  Returns score for engine A in [0, 1].
    Returns 0.5 (neutral) on failure so the gradient is zero rather than
    corrupting the parameter update.
    """
    global _first_run

    def engine_args(name, params):
        args = ["-engine", f"name={name}", f"cmd={ENGINE}"]
        for k, v in params.items():
            args.append(f"option.{k}={int(v)}")
        return args

    cmd = [
        CUTECHESS,
        *engine_args("Hero",    params_a),
        *engine_args("Villain", params_b),
        "-each", "proto=uci", f"tc={TC}", "timemargin=25",
        "-tb", "../Ursus/Syzygy/3-4-5",
        "-draw",   "movenumber=40", "movecount=6", "score=15",
        "-resign", "movecount=4",   "score=800",
        "-games", str(games),
        "-repeat",
        "-concurrency", "10",
        "-openings", "file=../Ursus/8moves_v3.pgn", "order=random",
        "-recover",
    ]

    if _first_run:
        print(f"\nDEBUG first command:\n  {' '.join(cmd)}\n")
        _first_run = False

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    stdout, stderr = proc.communicate()

    if stderr:
        print(f"  STDERR: {stderr[:300]}")
    if proc.returncode != 0:
        print(f"  WARNING: cutechess-cli exited {proc.returncode}")

    for line in stdout.splitlines():
        if line.startswith("Score of Hero vs Villain"):
            parts = line.split(":")[-1].strip().split()
            wins, losses, draws = int(parts[0]), int(parts[2]), int(parts[4])
            total = wins + losses + draws
            if total == 0:
                print("  WARNING: zero games recorded.")
                return 0.5
            return (wins + 0.5 * draws) / total

    print("  WARNING: no score line found in cutechess output.")
    print(f"  stdout preview: {stdout[:400]}")
    return 0.5

class AdamState:
    """Tracks first and second gradient moments for one parameter."""

    def __init__(self):
        self.m = 0.0
        self.v = 0.0
        self.t = 0

    def update(self, grad: float) -> float:
        """
        One Adam step.  Returns the bias-corrected normalised update direction.
        Magnitude is normalised to ~1 so the outer ak controls the step size.
        """
        self.t += 1
        self.m = ADAM_BETA1 * self.m + (1 - ADAM_BETA1) * grad
        self.v = ADAM_BETA2 * self.v + (1 - ADAM_BETA2) * grad * grad
        m_hat  = self.m / (1 - ADAM_BETA1 ** self.t)
        v_hat  = self.v / (1 - ADAM_BETA2 ** self.t)
        return m_hat / (math.sqrt(v_hat) + ADAM_EPS)

def ck_schedule(iteration: int) -> float:
    """
    Fixed perturbation during warmup, then standard SPSA gamma decay.
    Hard floor at CK_MIN prevents the gradient denominator from collapsing.
    """
    if iteration <= WARMUP_ITERS:
        return C_INIT
    return max(CK_MIN, C_INIT / ((iteration - WARMUP_ITERS) ** GAMMA))


def param_a_scale(param: dict) -> float:
    """
    Scale the global learning rate by sqrt(range / 100) so that
    wide-range parameters (history_div: 1000-12000) and narrow-range ones
    (iid_depth: 1-4) make proportionally sensible progress.
    """
    return math.sqrt((param["max"] - param["min"]) / 100.0)

def spsa_tune_stage(stage_key: str, params: dict,
                    start_iter: int = 0) -> dict:
    """
    Run SPSA for one stage.  Returns the final params dict so values can be
    carried into the next stage.
    """
    stage_info    = STAGES[stage_key]
    target        = stage_info["target_iters"]
    param_history = {k: deque(maxlen=100) for k in params}
    score_history = deque(maxlen=100)
    adam_states   = {k: AdamState() for k in params}

    sep()
    print(f"  STAGE : {stage_info['name'].upper()}  ({stage_key})")
    print(f"  {stage_info['description']}")
    print()
    print(f"  Parameters   : {len(params)}")
    print(f"  Target iters : {target}")
    print(f"  Games / iter : {GAMES_PER_ITER}")
    print(f"  Adam         : {'enabled' if ADAM_ENABLED else 'disabled'}")
    print()
    print(f"  {'Parameter':<22} {'Start':>8}   Range")
    print(f"  {'-'*22} {'-'*8}   {'-'*18}")
    for k, p in params.items():
        print(f"  {k:<22} {p['value']:>8.1f}   [{p['min']}, {p['max']}]")
    sep()
    print()

    iteration = start_iter

    try:
        while iteration < target:
            iteration += 1

            ck      = ck_schedule(iteration)
            base_ak = 1.0 / ((iteration + A) ** ALPHA)
            delta   = {k: random.choice([-1, 1]) for k in params}

            # Perturbed parameter sets
            theta_plus  = {}
            theta_minus = {}
            for k, p in params.items():
                change          = ck * delta[k] * p["step"]
                theta_plus[k]   = max(p["min"], min(p["max"], p["value"] + change))
                theta_minus[k]  = max(p["min"], min(p["max"], p["value"] - change))

            # Evaluate
            score_plus  = run_match(theta_plus, theta_minus)
            score_delta = score_plus - 0.5
            score_history.append(score_plus)

            print(f"  Iter {iteration:5d}/{target} | ck={ck:.3f} | "
                  f"score={score_plus:.3f} | ", end="")

            # Update parameters
            safe_ck = max(ck, CK_MIN)
            for k in params:
                p        = params[k]
                raw_grad = score_delta / (safe_ck * delta[k])
                a_k      = base_ak * param_a_scale(p)

                if ADAM_ENABLED:
                    direction = adam_states[k].update(raw_grad)
                    update    = a_k * direction * p["step"]
                else:
                    update    = a_k * raw_grad * p["step"]

                p["value"] = max(p["min"], min(p["max"], p["value"] + update))
                param_history[k].append(p["value"])
                print(f"{k}={p['value']:.1f} ", end="")

            print()

            # Convergence report
            if iteration % 50 == 0 and iteration >= 100:
                _convergence_report(stage_key, iteration, params,
                                    param_history, score_history)

            # Checkpoint
            if iteration % 10 == 0:
                save_checkpoint(stage_key, iteration, params)

    except KeyboardInterrupt:
        print("\n  [Interrupted — saving checkpoint]")

    save_checkpoint(stage_key, iteration, params)
    return params


def _convergence_report(stage_key, iteration, params,
                        param_history, score_history):
    print()
    sep("-")
    print(f"  CONVERGENCE REPORT  (iter {iteration}, {stage_key})")
    sep("-")
    max_pct = 0.0
    for k, p in params.items():
        hist = list(param_history[k])
        if len(hist) < 10:
            continue
        prange      = max(hist) - min(hist)
        total_range = p["max"] - p["min"]
        pct         = (prange / total_range * 100) if total_range else 0
        max_pct     = max(max_pct, pct)
        print(f"  {k:<22} current={p['value']:7.1f}  "
              f"range={prange:6.1f}  ({pct:5.1f}% of span)")

    if len(score_history) >= 20:
        avg = sum(score_history) / len(score_history)
        print(f"\n  Avg score (last {len(score_history)}): {avg:.4f}")

    if   max_pct < 5.0:  tag = "✓ CONVERGED"
    elif max_pct < 10.0: tag = "→ CONVERGING"
    else:                tag = "✗ STILL EXPLORING"
    print(f"\n  {tag}  (max param variation = {max_pct:.1f}% of span)")
    sep("-")
    print()

def run_all_stages(start_from: str | None = None,
                   single_stage: str | None = None):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    carry: dict = {}

    stages_to_run = [single_stage] if single_stage else STAGE_ORDER
    skipping      = bool(start_from) and not single_stage

    for stage_key in stages_to_run:
        if skipping:
            if stage_key == start_from:
                skipping = False
            else:
                ckpt = load_checkpoint(stage_key)
                if ckpt:
                    carry.update(ckpt)
                    print(f"  Skipping {stage_key} — loaded checkpoint values.")
                else:
                    print(f"  Skipping {stage_key} — no checkpoint found, "
                          f"using defaults.")
                continue

        sep()
        print(f"  STARTING {stage_key.upper()}")
        sep()

        resume_values = None
        ckpt = load_checkpoint(stage_key)
        if ckpt:
            ans = input(f"\n  Checkpoint found for {stage_key}. "
                        f"Resume from it? [y/N] ").strip().lower()
            if ans == "y":
                resume_values = ckpt
                print("  Resuming with saved parameter values.\n")

        merged_carry = {**carry, **(resume_values or {})}
        params = build_stage_params(stage_key, merged_carry)

        final = spsa_tune_stage(stage_key, params)

        for k, v in final.items():
            carry[k]               = v["value"]
            ALL_PARAMS[k]["value"] = v["value"]

        _print_stage_summary(stage_key, final)

    sep()
    print("  ALL STAGES COMPLETE")
    sep()
    print()
    print("  Final tuned values (paste into ALL_PARAMS):")
    print()
    for k, v in ALL_PARAMS.items():
        print(f'    "{k}": {{"value": {int(v["value"])}, '
              f'"min": {v["min"]}, "max": {v["max"]}, "step": {v["step"]}}},')

    master = os.path.join(OUTPUT_DIR, "final_all_params.json")
    with open(master, "w") as f:
        json.dump(
            {k: {"value": int(v["value"]), "min": v["min"],
                 "max": v["max"], "step": v["step"]}
             for k, v in ALL_PARAMS.items()},
            f, indent=2,
        )
    print(f"\n  Master output: {master}")
    sep()


def _print_stage_summary(stage_key: str, params: dict):
    sep("-")
    print(f"  STAGE COMPLETE: {stage_key}")
    sep("-")
    for k, v in params.items():
        print(f"  {k:<22} = {int(v['value']):6d}")
    sep("-")
    print()

def main():
    parser = argparse.ArgumentParser(
        description="Ursus SPSA parameter tuner",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Stages (in order):\n" +
               "\n".join(f"  {s}" for s in STAGE_ORDER),
    )
    parser.add_argument(
        "--stage", metavar="STAGE_KEY",
        help="Run a single stage only (e.g. --stage stage2_nmp)",
    )
    parser.add_argument(
        "--from", dest="start_from", metavar="STAGE_KEY",
        help="Skip earlier stages and resume pipeline from this stage",
    )
    parser.add_argument(
        "--list", action="store_true",
        help="Print all stages and their parameters, then exit",
    )
    args = parser.parse_args()

    if args.list:
        for key in STAGE_ORDER:
            s = STAGES[key]
            print(f"\n{key}  —  {s['name']}")
            print(f"  {s['description']}")
            print(f"  target_iters : {s['target_iters']}")
            print(f"  params       : {s['params']}")
        return

    for attr, label in [("stage", "--stage"), ("start_from", "--from")]:
        val = getattr(args, attr, None)
        if val and val not in STAGES:
            parser.error(f"Unknown stage '{val}' for {label}. "
                         f"Valid: {', '.join(STAGE_ORDER)}")

    try:
        run_all_stages(start_from=args.start_from, single_stage=args.stage)
    except KeyboardInterrupt:
        print(f"\n\n  Tuning interrupted. Partial results in: {OUTPUT_DIR}/")
        sys.exit(0)


if __name__ == "__main__":
    main()
