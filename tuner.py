import subprocess
import random
import sys

ENGINE = "./zig-out/bin/Ursus" 

CUTECHESS = "cutechess-cli"

TC = "1/0.05" 

# SPSA Parameters
c = 2.0        # Perturbation size 
a = 1.0        # Learning rate 
A = 100        # Stability constant 
alpha = 0.602  # Standard SPSA decay
gamma = 0.101  # Standard SPSA decay

# Parameters to Tune
# Format: "UCI_Name": { "value": StartVal, "min": Min, "max": Max, "step": StepScale }
# "step" allows you to treat sensitive parameters (like reductions) differently than large ones (like scores)
PARAMS = {
    "aspiration_window": { "value": 50,  "min": 10,  "max": 200, "step": 5 },
    "rfp_depth":    { "value": 6,   "min": 1,   "max": 12,  "step": 1 },
    "rfp_mul":      { "value": 50,  "min": 10,  "max": 150, "step": 5 },
    "rfp_improvement": { "value": 75,  "min": 10,   "max": 150,  "step": 5 },
    "nmp_improvement": { "value": 75,  "min": 10,   "max": 150,  "step": 5 },
    "nmp_base":     { "value": 3,   "min": 1,   "max": 8,   "step": 1 },
    "nmp_depth_div": { "value": 3,   "min": 1,   "max": 8,   "step": 1 },
    "nmp_beta_div":  { "value": 150,   "min": 50,   "max": 300,   "step": 10 },
    "razoring_margin":  { "value": 300, "min": 100, "max": 600, "step": 10 },
    "probcut_margin":    { "value": 200, "min": 50, "max": 600, "step": 10 },
    "probcut_depth": { "value": 3,   "min": 1,   "max": 8,   "step": 1 },
}

def run_match(params_a, params_b):
    """
    Runs a 2-game match (A vs B, B vs A) to cancel color advantage.
    Returns score for A (1.0 win, 0.5 draw, 0.0 loss).
    """

    # Build engine A command with options
    engine_a = ["-engine", f"name=Hero", f"cmd={ENGINE}"]
    for k, v in params_a.items():
        engine_a.append(f"option.{k}={int(v)}")
    
    # Build engine B command with options
    engine_b = ["-engine", f"name=Villain", f"cmd={ENGINE}"]
    for k, v in params_b.items():
        engine_b.append(f"option.{k}={int(v)}")

    cmd = [
        CUTECHESS,
        *engine_a,
        *engine_b,
        "-each", "proto=uci", f"tc={TC}", "timemargin=75",
        "-tb", "../Ursus/Syzygy/3-4-5",
        "-draw", "movenumber=40", "movecount=6", "score=15", 
        "-resign", "movecount=3", "score=400",
        "-games", "8",
        "-repeat",
        "-concurrency", "8",
        "-openings", "file=../Ursus/8moves_v3.pgn", "order=random", 
        "-recover"
    ]

    # Debug: print the command (only first time)
    if not hasattr(run_match, '_debug_printed'):
        print(f"\nDEBUG: Running command:\n{' '.join(cmd)}\n")
        run_match._debug_printed = True

    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    stdout, stderr = process.communicate()

    # Debug: print any errors
    if stderr:
        print(f"STDERR: {stderr}")
    
    if process.returncode != 0:
        print(f"WARNING: cutechess-cli exited with code {process.returncode}")

    wins, losses, draws = 0, 0, 0
    found_score = False
    
    for line in stdout.splitlines():
        if line.startswith("Score of Hero vs Villain"):
            parts = line.split(":")[-1].strip().split()
            wins = int(parts[0])
            losses = int(parts[2])
            draws = int(parts[4])
            found_score = True
            break

    if not found_score:
        print("WARNING: Could not find score line in output!")
        print("STDOUT Preview:")
        print(stdout[:500] if stdout else "(empty)")

    total_games = wins + losses + draws
    if total_games == 0:
        print("WARNING: No games were played!")
        return 0.5 

    return (wins + 0.5 * draws) / total_games

def spsa_tune():
    iteration = 0

    print(f"Starting SPSA Tuner on {len(PARAMS)} parameters...")
    print(f"Engine: {ENGINE}")
    print(f"Time Control: {TC}")

    while True:
        iteration += 1

        # 1. Calculate decay factors
        ck = c / (iteration ** gamma)
        ak = a / ((iteration + A) ** alpha)

        # 2. Generate Perturbation Vector (Delta)
        # Bernoulli distribution (+1 or -1)
        delta = {k: random.choice([-1, 1]) for k in PARAMS}

        # 3. Create two parameter sets (Theta + ck*Delta, Theta - ck*Delta)
        theta_plus = {}
        theta_minus = {}

        for k, p in PARAMS.items():
            change = ck * delta[k] * p["step"]

            # Clamp to min/max
            val_plus = max(p["min"], min(p["max"], p["value"] + change))
            val_minus = max(p["min"], min(p["max"], p["value"] - change))

            theta_plus[k] = val_plus
            theta_minus[k] = val_minus

        # 4. Run the match
        score_plus = run_match(theta_plus, theta_minus)

        # 5. Estimate Gradient and Update Parameters
        # Gradient approximation: (Score(theta+) - Score(theta-)) / (2 * ck)
        # Note: Score(theta-) is just (1 - score_plus) roughly in a head-to-head
        # Simplification for match play:
        # If Plus scored > 50%, we move towards Plus. If < 50%, we move towards Minus.

        score_delta = (score_plus - 0.5) # Positive if Plus won, negative if Minus won

        print(f"Iter {iteration}: Score={score_plus:.2f} | ", end="")

        for k in PARAMS:
            # Gradient update rule
            # The 'gradient' for this parameter is score_delta / (ck * delta)
            # Update = -ak * gradient (but we want to maximize score, so +ak)

            gradient = score_delta / (ck * delta[k])
            update = ak * gradient * PARAMS[k]["step"]

            # Update the central value
            new_val = PARAMS[k]["value"] + update

            # Clamp and Save
            PARAMS[k]["value"] = max(PARAMS[k]["min"], min(PARAMS[k]["max"], new_val))

            # Formatting for print
            print(f"{k}={PARAMS[k]['value']:.2f} ", end="")

        print("") # Newline

        # Periodically save results to file
        if iteration % 5 == 0:
            with open("tuned_params.txt", "w") as f:
                for k, v in PARAMS.items():
                    f.write(f"{k} = {v['value']}\n")

if __name__ == "__main__":
    try:
        spsa_tune()
    except KeyboardInterrupt:
        print("\nTuning stopped.")
