#!/usr/bin/env bash
set -euo pipefail

ENGINE_NEW="./zig-out/bin/Ursus"
# ENGINE_BASE="./engines/Ursus3.0"
# ENGINE_BASE="./engines/Ursus_with_nnue_overhead"
# ENGINE_BASE="./engines/UrsusEQ"
# ENGINE_BASE="./engines/Ursus2.15.1"
ENGINE_BASE="./engines/Ursus2.26.1"
# ENGINE_BASE="./../Chess-Coding-Adventure/Chess-Coding-Adventure/bin/Release/net6.0/osx-arm64/Chess-Coding-Adventure"

FASTCHESS="fastchess"

OPENINGS="8moves_v3.pgn"

CONCURRENCY=10
TC="2+0.2"
ROUNDS=10000
TIMEMARGIN=50

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
# -each nodes=100000 \

$FASTCHESS \
  -engine cmd="$ENGINE_NEW" name=New \
  -engine cmd="$ENGINE_BASE" name=Base \
  -each tc=$TC timemargin=$TIMEMARGIN \
  -openings file="$OPENINGS" format=pgn order=random \
  -repeat \
  -rounds $ROUNDS \
  -concurrency $CONCURRENCY \
  -tb "../Ursus/Syzygy/3-4-5" \
  -recover \
  -ratinginterval 10 \
  -sprt elo0=$ELO0 elo1=$ELO1 alpha=$ALPHA beta=$BETA \
  -pgnout file="$PGN" \
  | tee "$LOG"

# -draw movenumber=40 movecount=8 score=15 \
# 	-resign movecount=5 score=400 \
echo
echo "SPRT test finished"
echo "PGN: $PGN"
echo "Log: $LOG"
