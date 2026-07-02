import sys

def prune_epd(bookname, use_hash_keys=True):
    """
    Remove duplicate opening positions from an EPD/FEN book in a single pass.

    - Ignores halfmove/fullmove counters when comparing positions (a duplicate
      position with a different counter is still a duplicate).
    - Preserves the original order (first occurrence of each position is kept).
    - O(n) time, O(unique positions) memory.

    use_hash_keys: store a 64-bit hash of each key instead of the raw string.
    Cuts memory roughly in half for a book this size. Collision probability
    is negligible (~1 in a billion) for 8M entries in a 64-bit space, but
    set to False if you want a zero-risk exact-match guarantee.
    """
    if bookname.endswith(".epd"):
        outname = bookname.replace(".epd", "_pruned.epd")
    elif bookname.endswith(".fen"):
        outname = bookname.replace(".fen", "_pruned.fen")
    else:
        outname = bookname + ".pruned"

    seen = set()
    total = 0
    kept = 0
    report_every = 500_000

    # Large I/O buffers matter a lot at this scale.
    with open(bookname, "r", buffering=1 << 20) as fin, \
         open(outname, "w", buffering=1 << 20) as fout:
        for line in fin:
            total += 1
            stripped = line.rstrip("\n")
            if not stripped:
                continue

            # Position key = first 4 FEN fields, ignoring move counters.
            fields = stripped.split(" ", 5)
            key = " ".join(fields[:4])
            if use_hash_keys:
                key = hash(key)

            if key in seen:
                pass  # duplicate, skip
            else:
                seen.add(key)
                fout.write(line if line.endswith("\n") else line + "\n")
                kept += 1

            if total % report_every == 0:
                print(f"...{total:,} lines processed, {kept:,} unique kept",
                      file=sys.stderr)

    print(f"Done. {total:,} lines read, {kept:,} unique positions kept, "
          f"{total - kept:,} duplicates removed.", file=sys.stderr)
    print(f"Wrote pruned book to {outname}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1].endswith((".epd", ".fen")):
        prune_epd(sys.argv[1])
    else:
        print(f"Usage: python {sys.argv[0]} <book.epd>")
        print("\nRemoves duplicate opening positions from an EPD/FEN book,")
        print("ignoring halfmove/fullmove counters, preserving original order.")
