#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG
########################################

# Paths to engines
ENGINE_NEW="./zig-out/bin/Ursus"
ENGINE_BASE="./engines/Ursus2.19.1"
# ENGINE_BASE="./engines/UrsusPRETUNE"
# ENGINE_BASE="./engines/Ursus2.17.3"
# ENGINE_BASE="./engines/Ursus2.15.1"
# ENGINE_BASE="./releaseEngines/Ursus2.0"
# ENGINE_BASE="./../Chess-Coding-Adventure/Chess-Coding-Adventure/bin/Release/net6.0/osx-arm64/Chess-Coding-Adventure"

# cutechess binary (assumes it's on PATH)
CUTECHESS="cutechess-cli"

# Openings
OPENINGS="8moves_v3.pgn"
# OPENINGS="Balsa/Balsa_v500.pgn"

# Match settings
GAMES=4098
CONCURRENCY=10
TC="100/30"

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
  -each tc=2+0.1 timemargin=50 \
  -openings file="$OPENINGS" format=pgn order=random \
  -repeat \
  -games $GAMES \
  -tb "../Ursus/Syzygy/3-4-5" \
  -concurrency $CONCURRENCY \
  -draw movenumber=40 movecount=8 score=15 \
  -resign movecount=5 score=600 \
  -recover \
  -ratinginterval 10 \
  -pgnout "$PGN" \
  | tee "$LOG"


echo
echo "Match finished"
echo "PGN: $PGN"
echo "Log: $LOG"

