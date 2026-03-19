#!/usr/bin/env bash
set -euo pipefail

CUTECHESS="cutechess-cli"
FASTCHESS="fastchess"

ENGINES=(
  "Ursus=./zig-out/bin/Ursus"
  "Ursus3.0=./engines/Ursus3.0"
  "Lynx=./../lynx/Lynx.Cli"
  "Grail=./../grail-arm64"
  "Simbelmyne=./../simbelmyne"
  "Odonata=./../odonata/target/release/odonata"
  "jpg"="./../tcheran/target/release/engine"
  "Ursus2.26=./engines/Ursus2.26.1"
  "Sykora=./../sykora/zig-out/bin/Sykora"
  "Pawn=./../pawn/build/pawn"
  "Chess-Coding-Adventure=./../Chess-Coding-Adventure/Chess-Coding-Adventure/bin/Release/net6.0/osx-arm64/Chess-Coding-Adventure"
)

# OPENINGS="8moves_v3.pgn"
OPENINGS="openings.pgn"

ROUNDS=1000
CONCURRENCY=10

TC="8+0.08"

OUTDIR="tournaments/$(date +%Y%m%d_%H%M%S)"
PGN="$OUTDIR/games.pgn"
LOG="$OUTDIR/cutechess.log"

mkdir -p "$OUTDIR"

echo "Starting engine Elo tournament"
echo "Output dir: $OUTDIR"
echo

ENGINE_ARGS=()
for E in "${ENGINES[@]}"; do
  NAME="${E%%=*}"
  CMD="${E#*=}"
  ENGINE_ARGS+=( -engine name="$NAME" cmd="$CMD" proto=uci )
done

$CUTECHESS \
  "${ENGINE_ARGS[@]}" \
  -each tc=$TC timemargin=50 option.Threads=1 option.Hash=64 \
  -openings file="$OPENINGS" format=pgn order=random policy=round \
  -repeat 2 \
  -games 2 \
  -tb "../Ursus/Syzygy/3-4-5" \
  -rounds $ROUNDS \
  -concurrency $CONCURRENCY \
  -resign movecount=5 score=400 \
  -ratinginterval 5 \
  -recover \
  -pgnout "$PGN" \
  | tee "$LOG"

echo
echo "Tournament finished"
echo "PGN: $PGN"
echo "Log: $LOG"

