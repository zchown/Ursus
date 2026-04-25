import struct
import sys
from pathlib import Path

SCALE_FACTOR = 128.0 / 400.0  # 0.32

def rescale_vf(input_path: str, output_path: str):
    in_path = Path(input_path)
    out_path = Path(output_path)

    games = 0
    positions = 0

    with open(in_path, "rb") as fin, open(out_path, "wb") as fout:
        while True:
            # 32-byte header - write unchanged
            header = fin.read(32)
            if len(header) < 32:
                break
            fout.write(header)

            # Read moves until null terminator
            while True:
                entry = fin.read(4)
                if len(entry) < 4:
                    raise ValueError(f"Unexpected EOF at game {games}")

                move_data, eval_score = struct.unpack("<Hh", entry)

                # Null terminator
                if move_data == 0 and eval_score == 0:
                    fout.write(entry)
                    break

                # Rescale eval score from 400 -> 128
                rescaled = int(eval_score * SCALE_FACTOR)
                rescaled = max(-32000, min(32000, rescaled))
                fout.write(struct.pack("<Hh", move_data, rescaled))
                positions += 1

            games += 1
            if games % 10000 == 0:
                print(f"\r  {games:,} games, {positions:,} positions...", end="", flush=True)

    print(f"\rDone: {games:,} games, {positions:,} positions -> {out_path}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python rescale_vf.py <input.vf> <output.vf>")
        sys.exit(1)

    rescale_vf(sys.argv[1], sys.argv[2])
