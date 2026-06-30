#!/usr/bin/env bash
set -euo pipefail

ENGINE_NEW="./zig-out/bin/Ursus"
# ENGINE_NEW="./zig-out/bin/Ursus"
# ENGINE_BASE="./engines/Ursus4.6"
# ENGINE_BASE="./engines/Ursus3.39"
ENGINE_BASE="./../stash/stash-bot-v37.0/src/stash"          # 3431
# # ENGINE_BASE="./releaseEngines/Ursus6.0"
# ENGINE_BASE="./engines/Ursus3.2"
# ENGINE_BASE="./engines/Ursus_with_nnue_overhead"
# ENGINE_BASE="./engines/UrsusEQ"
# ENGINE_BASE="./engines/Ursus2.15.1"
# ENGINE_BASE="./engines/Ursus2.26.1"
# ENGINE_BASE="./../Chess-Coding-Adventure/Chess-Coding-Adventure/bin/Release/net6.0/osx-arm64/Chess-Coding-Adventure"

FASTCHESS="fastchess"
# fastchess -config file=config.json

# OPENINGS="8moves_v3.pgn"
OPENINGS="openings/UHO_Lichess_4852_v1.epd"
# OPENINGS="frdfrc.epd"
# OPENINGS="openings.pgn"

CONCURRENCY=8
TC="60.6"
ROUNDS=1000

# SPRT settings
# H0: 0 Elo (no improvement)
# H1: +5 Elo improvement
ELO0=0
ELO1=5
ALPHA=0.05
BETA=0.05

OUTDIR="matches/$(date +%Y%m%d_%H%M%S)"
PGN="$OUTDIR/games.pgn"
LOG="$OUTDIR/fastchess.log"

mkdir -p "$OUTDIR"

echo "Starting fastchess SPRT match"
echo "  New:    $ENGINE_NEW"
echo "  Base:   $ENGINE_BASE"
echo "  TC:     $TC"
echo "  Rounds: $ROUNDS (SPRT will stop early)"
echo "  SPRT:   elo0=$ELO0 elo1=$ELO1 alpha=$ALPHA beta=$BETA"
echo "  Output: $OUTDIR"
echo

$FASTCHESS \
  -engine cmd="$ENGINE_NEW"  name=Ursus \
  -engine cmd="$ENGINE_BASE" name=Stash37 \
  -each tc=$TC option.Threads=1 option.Hash=64 \
  -openings file="$OPENINGS" format=epd order=random \
  -tb "../Ursus/Syzygy/3-4-5" \
  -repeat \
  -rounds $ROUNDS \
  -concurrency $CONCURRENCY \
  -recover \
  -ratinginterval 10 \
  -pgnout file="$PGN" \
  | tee "$LOG"

# -sprt elo0=$ELO0 elo1=$ELO1 alpha=$ALPHA beta=$BETA \
