#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG
########################################

# Paths to engines
ENGINE_NEW="./engines/Ursus1.0"
ENGINE_BASE="./engines/Ursus1.0"

# cutechess binary (assumes it's on PATH)
CUTECHESS="cutechess-cli"

# Openings
OPENINGS="Balsa/Balsa_v500.pgn"

# Match settings
GAMES=200
CONCURRENCY=8
TC="120/3"

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
  -each tc=$TC \
  -openings file="$OPENINGS" format=pgn order=random \
  -repeat \
  -games $GAMES \
  -concurrency $CONCURRENCY \
  -recover \
  -pgnout "$PGN" \
  | tee "$LOG"

echo
echo "Match finished"
echo "PGN: $PGN"
echo "Log: $LOG"

