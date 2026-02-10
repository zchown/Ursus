#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG
########################################

# Paths to engines
ENGINE_NEW="./zig-out/bin/Ursus"
ENGINE_BASE="./engines/Ursus2.10.6"
# ENGINE_BASE="./engines/Ursus2.8"
# ENGINE_BASE="./../Chess-Coding-Adventure/Chess-Coding-Adventure/bin/Release/net6.0/osx-arm64/Chess-Coding-Adventure"

# cutechess binary (assumes it's on PATH)
CUTECHESS="cutechess-cli"

# Openings
OPENINGS="Balsa/Balsa_v110221.pgn"
# OPENINGS="Balsa/Balsa_v500.pgn"

# Match settings
GAMES=2048
CONCURRENCY=4
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
  -each tc=1/0.1 timemargin=20 \
  -openings file="$OPENINGS" format=pgn order=random \
  -repeat \
  -games $GAMES \
  -concurrency $CONCURRENCY \
  -recover \
  -resign movecount=5 score=1200 \
  -draw movenumber=40 movecount=8 score=10 \
  -ratinginterval 10 \
  -pgnout "$PGN" \
  | tee "$LOG"


echo
echo "Match finished"
echo "PGN: $PGN"
echo "Log: $LOG"

