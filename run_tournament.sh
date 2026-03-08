#!/usr/bin/env bash
set -euo pipefail

########################################
# CONFIG
########################################

CUTECHESS="cutechess-cli"

# Engines (edit paths + names)
ENGINES=(
  "Ursus=./zig-out/bin/Ursus"
  # "Ursus3.0=./engines/Ursus3.0"
  "Lynx=./../lynx/Lynx.Cli"
  "Ursus3.3=./engines/Ursus3.3"
  "Ursus2.26=./engines/Ursus2.26.1"
  "Sykora=./../sykora/zig-out/bin/Sykora"
  "Chess-Coding-Adventure=./../Chess-Coding-Adventure/Chess-Coding-Adventure/bin/Release/net6.0/osx-arm64/Chess-Coding-Adventure"
)

# Openings
OPENINGS="8moves_v3.pgn"
# OPENINGS="Balsa/Balsa_v110221.pgn"

# Tournament size
ROUNDS=50
CONCURRENCY=10

# Time control
TC="4+0.04"

# Output
OUTDIR="tournaments/$(date +%Y%m%d_%H%M%S)"
PGN="$OUTDIR/games.pgn"
LOG="$OUTDIR/cutechess.log"

########################################
# SETUP
########################################

mkdir -p "$OUTDIR"

echo "Starting engine Elo tournament"
echo "Output dir: $OUTDIR"
echo

########################################
# BUILD ENGINE ARGS
########################################

ENGINE_ARGS=()
for E in "${ENGINES[@]}"; do
  NAME="${E%%=*}"
  CMD="${E#*=}"
  ENGINE_ARGS+=( -engine name="$NAME" cmd="$CMD" proto=uci )
done

########################################
# RUN
########################################

$CUTECHESS \
  "${ENGINE_ARGS[@]}" \
  -each tc=$TC timemargin=50 \
  -openings file="$OPENINGS" format=pgn order=random policy=round \
  -repeat 2 \
  -games 2 \
  -tb "../Ursus/Syzygy/3-4-5" \
  -rounds $ROUNDS \
  -concurrency $CONCURRENCY \
  -ratinginterval 5 \
  -draw movenumber=40 movecount=8 score=15 \
  -resign movecount=5 score=400 \
  -recover \
  -pgnout "$PGN" \
  | tee "$LOG"

echo
echo "Tournament finished"
echo "PGN: $PGN"
echo "Log: $LOG"

