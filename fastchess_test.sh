#!/usr/bin/env bash
set -euo pipefail

ENGINE_NEW="./zig-out/bin/Ursus"
ENGINE_BASE="./engines/Ursus3.30"
# ENGINE_BASE="./../stash/stash-bot-v37.0/src/stash"          # 3431
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
# OPENINGS="openings.pgn"

CONCURRENCY=10
TC="4+0.04"
ROUNDS=100000
TIMEMARGIN=50

# SPRT settings
# H0: 0 Elo (no improvement)
# H1: +5 Elo improvement
ELO0=-5
ELO1=0
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

# cutechess-cli \
#   -engine cmd="$ENGINE_NEW" name=New \
#   -engine cmd="$ENGINE_BASE" name=Base \
#   -each tc=$TC timemargin=$TIMEMARGIN proto=uci ponder \
#   -openings file="$OPENINGS" format=pgn order=random \
#   -games 2 \
#   -repeat \
#   -rounds $ROUNDS \
#   -concurrency $CONCURRENCY \
#   -tb "../Ursus/Syzygy/3-4-5" \
#   -recover \
#   -resign movecount=5 score=300 \
#   -ratinginterval 10 \
#   -sprt elo0=$ELO0 elo1=$ELO1 alpha=$ALPHA beta=$BETA \
#   -pgnout "$PGN" \
#   | tee "$LOG"

$FASTCHESS \
  -engine cmd="$ENGINE_NEW"  name=New \
  -engine cmd="$ENGINE_BASE" name=Base \
  -each tc=$TC timemargin=$TIMEMARGIN option.Threads=1 option.Hash=256 option.SyzygyPath="../Ursus/Syzygy/3-4-5" option.SyzygyProbeDepth=1 \
  -openings file="$OPENINGS" format=epd order=random \
  -tb "../Ursus/Syzygy/3-4-5" \
  -repeat \
  -rounds $ROUNDS \
  -concurrency $CONCURRENCY \
  -recover \
  -resign movecount=5 score=300 \
  -draw movenumber=40 movecount=8 score=10 \
  -sprt elo0=$ELO0 elo1=$ELO1 alpha=$ALPHA beta=$BETA \
  -ratinginterval 10 \
  -pgnout file="$PGN" \
  | tee "$LOG"


echo
echo "SPRT test finished"
echo "PGN: $PGN"
echo "Log: $LOG"
