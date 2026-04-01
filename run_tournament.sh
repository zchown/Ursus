#!/usr/bin/env bash
set -euo pipefail

CUTECHESS="cutechess-cli"
FASTCHESS="fastchess"

ENGINES=(
  "Ursus=./zig-out/bin/Ursus"
  # "Ursus3.10=./engines/Ursus3.10"
  # "Ursus3.6=./engines/Ursus3.6"
  "stash37=./../stash/stash-bot-v37.0/src/stash" # 3426
  "stash35=./../stash/stash-bot-v35.0/src/stash-bot" # 3350
  "Raphael=./../Raphael/uci" # 3612
  # "Lynx=./../lynx/Lynx.Cli" # 3373
  # "Grail=./../grail-arm64" # 3336
  # "Simbelmyne=./../simbelmyne" # 3244
  "Odonata=./../odonata/target/release/odonata" #3352
  "tcheran"="./../tcheran/target/release/engine" #3634
  # "Sirius"="./../sirius/Sirius-9.0/build/arm64/Sirius/sirius" # 3534 - On my machine its absolutely terrible for some reason
  # "Sykora=./../sykora/zig-out/bin/Sykora"
  # "Pawn=./../pawn/build/pawn" # 3554
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
  -ratinginterval 25 \
  -recover \
  -pgnout "$PGN" \
  | tee "$LOG"

# -resign movecount=5 score=400 \
# 	-draw movenumber=40 movecount=6 score=15 \
echo
echo "Tournament finished"
echo "PGN: $PGN"
echo "Log: $LOG"

