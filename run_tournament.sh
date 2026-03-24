#!/usr/bin/env bash
set -euo pipefail

CUTECHESS="cutechess-cli"
FASTCHESS="fastchess"

ENGINES=(
  "Ursus=./zig-out/bin/Ursus"
  "Ursus3.10=./engines/Ursus3.10"
  "stash37=./../stash/stash-bot-v37.0/src/stash"
  "stash35=./../stash/stash-bot-v35.0/src/stash-bot" # 3350
  "Raphael=./../Raphael/uci" # 3612
  # "Lynx=./../lynx/Lynx.Cli"
  "Grail=./../grail-arm64"
  "Simbelmyne=./../simbelmyne"
  "Odonata=./../odonata/target/release/odonata"
  "tcheran"="./../tcheran/target/release/engine"
  # "Sirius"="./../sirius/Sirius-9.0/build/arm64/Sirius/sirius"
  # "Sykora=./../sykora/zig-out/bin/Sykora"
  "Pawn=./../pawn/build/pawn"
  # "Chess-Coding-Adventure=./../Chess-Coding-Adventure/Chess-Coding-Adventure/bin/Release/net6.0/osx-arm64/Chess-Coding-Adventure"
)

# OPENINGS="8moves_v3.pgn"
# OPENINGS="openings.pgn"
OPENINGS="openings/UHO_Lichess_4852_v1.epd"

ROUNDS=250
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
  -openings file="$OPENINGS" format=epd order=random policy=round \
  -repeat 2 \
  -games 2 \
  -tb "../Ursus/Syzygy/3-4-5" \
  -rounds $ROUNDS \
  -concurrency $CONCURRENCY \
  -resign movecount=5 score=400 \
  -draw movenumber=40 movecount=6 score=15 \
  -ratinginterval 25 \
  -recover \
  -pgnout "$PGN" \
  | tee "$LOG"

echo
echo "Tournament finished"
echo "PGN: $PGN"
echo "Log: $LOG"

