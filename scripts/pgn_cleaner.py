"""
clean_opening_book.py
---------------------
Converts an annotated Lichess study PGN into a clean opening book PGN.

What it does:
  - Strips ALL comments, NAGs, annotations, and %cal/%csl markers
  - Expands every variation branch into its own standalone game
  - Deduplicates identical lines
  - Optionally trims lines to a maximum ply depth
  - Writes one clean game per line with minimal headers

Usage:
  python3 clean_opening_book.py input.pgn output_book.pgn [--max-ply 30]
"""

import chess
import chess.pgn
import io
import sys
import argparse
from collections import OrderedDict


def extract_all_lines(game):
    """Recursively walk the variation tree, yielding every root-to-leaf path
    as a list of chess.Move objects."""
    def walk(node, moves):
        if not node.variations:
            yield moves[:]
            return
        for var in node.variations:
            moves.append(var.move)
            yield from walk(var, moves)
            moves.pop()
    yield from walk(game, [])


def moves_to_uci_key(move_list):
    """Create a hashable key from a move list for deduplication."""
    return tuple(m.uci() for m in move_list)


def line_to_pgn(move_list, board, event="Opening Book", max_ply=None):
    """Convert a move list to a clean PGN string (no comments, no variations)."""
    if max_ply is not None:
        move_list = move_list[:max_ply]

    new_game = chess.pgn.Game()
    new_game.headers["Event"] = event
    new_game.headers["White"] = "?"
    new_game.headers["Black"] = "?"
    new_game.headers["Result"] = "*"
    # Remove Date, Round, Site headers
    for h in ["Date", "Round", "Site"]:
        if h in new_game.headers:
            del new_game.headers[h]

    node = new_game
    b = board.copy()
    for move in move_list:
        node = node.add_variation(move)
        b.push(move)

    new_game.headers["Result"] = "*"
    exporter = chess.pgn.StringExporter(headers=True, variations=False, comments=False)
    return new_game.accept(exporter)


def clean_pgn(input_path, output_path, max_ply=None):
    with open(input_path, encoding="utf-8") as f:
        content = f.read()

    pgn_io = io.StringIO(content)
    all_lines = OrderedDict()  # uci_key -> (move_list, starting_board)
    total_games = 0
    skipped_dupes = 0

    while True:
        game = chess.pgn.read_game(pgn_io)
        if game is None:
            break
        total_games += 1

        starting_board = game.board()
        chapter = game.headers.get("ChapterName", game.headers.get("Event", "?"))

        for line in extract_all_lines(game):
            key = moves_to_uci_key(line)
            if key in all_lines:
                skipped_dupes += 1
            else:
                all_lines[key] = (line, starting_board, chapter)

    print(f"Chapters processed : {total_games}")
    print(f"Unique lines found : {len(all_lines)}")
    print(f"Duplicate lines    : {skipped_dupes}")
    if max_ply:
        print(f"Max ply depth      : {max_ply}")

    with open(output_path, "w", encoding="utf-8") as out:
        for key, (move_list, board, chapter) in all_lines.items():
            pgn_str = line_to_pgn(move_list, board, event=chapter, max_ply=max_ply)
            out.write(pgn_str + "\n\n")

    print(f"\nClean opening book written to: {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Clean a Lichess study PGN into an opening book.")
    parser.add_argument("input",  help="Input .pgn file (annotated Lichess study)")
    parser.add_argument("output", help="Output .pgn file (clean opening book)")
    parser.add_argument("--max-ply", type=int, default=None,
                        help="Truncate lines to this many half-moves (e.g. 30 = 15 moves)")
    args = parser.parse_args()

    clean_pgn(args.input, args.output, max_ply=args.max_ply)
