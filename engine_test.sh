#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG
########################################

# Paths to engines
ENGINE_NEW="./zig-out/bin/Ursus"
ENGINE_BASE="./engines/Ursus2.2.6"
# ENGINE_BASE="./engines/Ursus1.0"
# ENGINE_BASE="./../Chess-Coding-Adventure/Chess-Coding-Adventure/bin/Release/net6.0/osx-arm64/Chess-Coding-Adventure"

# cutechess binary (assumes it's on PATH)
CUTECHESS="cutechess-cli"

# Openings
OPENINGS="Balsa/Balsa_v110221.pgn"

# Match settings
GAMES=50
CONCURRENCY=4
TC="40/30"

# Output
OUTDIR="matches/$(date +%Y%m%d_%H%M%S)"
PGN="$OUTDIR/games.pgn"
LOG="$OUTDIR/cutechess.log"

########################################
# SETUP
########################################

mkdir -p "$OUTDIR"

echo "Starting cutechess match"
echo "Output dir: $OUTDIR"
echo

########################################
# RUN
########################################

$CUTECHESS \
  -engine name=New cmd="$ENGINE_NEW" proto=uci \
  -engine name=Base cmd="$ENGINE_BASE" proto=uci \
  -each tc=1/0.05 \
  -openings file="$OPENINGS" format=pgn order=random \
  -repeat \
  -games $GAMES \
  -concurrency $CONCURRENCY \
  -recover \
  -ratinginterval 10 \
  -pgnout "$PGN" \
  -debug all \
  | tee "$LOG"

echo
echo "Match finished"
echo "PGN: $PGN"
echo "Log: $LOG"

