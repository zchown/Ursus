#!/usr/bin/env python3
"""
Fix viriformat .vf files that have incorrect castling move encoding.

Bug: castling moves were encoded as king -> king's destination (e.g. e1->g1)
Fix: castling moves should be king -> rook's original square (e.g. e1->h1)

Usage:
    python fix_vf_castling.py -o output.vf input1.vf input2.vf input3.vf
"""

import sys
import struct
from pathlib import Path

CASTLE_FLAG = 0b10

def fix_castle_move(move_u16: int) -> int:
    from_sq = move_u16 & 0x3F
    to_sq = (move_u16 >> 6) & 0x3F
    flags = (move_u16 >> 12) & 0xF
    flag_type = (flags >> 2) & 0x3

    if flag_type != CASTLE_FLAG:
        return move_u16

    rank_base = (from_sq // 8) * 8
    if to_sq > from_sq:
        new_to = rank_base + 7
    else:
        new_to = rank_base

    return from_sq | (new_to << 6) | (flags << 12)

def process_file(data: bytes, output: bytearray) -> tuple:
    pos = 0
    length = len(data)
    games = 0
    games_fixed = 0
    moves = 0
    moves_fixed = 0

    while pos + 32 <= length:
        output.extend(data[pos:pos+32])
        pos += 32
        games += 1
        game_had_fix = False

        while pos + 4 <= length:
            move_u16, eval_i16 = struct.unpack('<Hh', data[pos:pos+4])

            if move_u16 == 0 and eval_i16 == 0:
                output.extend(data[pos:pos+4])
                pos += 4
                break

            moves += 1
            fixed = fix_castle_move(move_u16)
            if fixed != move_u16:
                moves_fixed += 1
                game_had_fix = True
                output.extend(struct.pack('<Hh', fixed, eval_i16))
            else:
                output.extend(data[pos:pos+4])
            pos += 4
        else:
            print(f"  Warning: truncated game at byte {pos}")
            break

        if game_had_fix:
            games_fixed += 1

    return games, games_fixed, moves, moves_fixed

def main():
    if '-o' not in sys.argv or len(sys.argv) < 4:
        print("Usage: python fix_vf_castling.py -o output.vf input1.vf input2.vf ...")
        sys.exit(1)

    o_idx = sys.argv.index('-o')
    output_path = sys.argv[o_idx + 1]
    input_files = [a for i, a in enumerate(sys.argv[1:], 1) if i != o_idx and i != o_idx + 1]

    print(f"Fixing {len(input_files)} file(s) -> {output_path}\n")

    combined = bytearray()
    total_games = total_fixed = total_moves = total_mfixed = 0

    for f in input_files:
        data = Path(f).read_bytes()
        games, gf, moves, mf = process_file(data, combined)
        total_games += games
        total_fixed += gf
        total_moves += moves
        total_mfixed += mf
        print(f"  {f}: {games} games, {mf} castling moves fixed")

    Path(output_path).write_bytes(bytes(combined))

    print(f"\nTotal: {total_games} games, {total_moves} moves, {total_mfixed} castling fixes")
    print(f"Written to: {output_path}")

if __name__ == '__main__':
    main()
