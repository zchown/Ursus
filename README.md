# Ursus Chess Engine

Ursus is a UCI-compatible chess engine written in [Zig](https://ziglang.org/). It uses a bitboard-based board representation, alpha-beta search with many search optimizations, and uses a NNUE for evaluation.

Available to play on lichess: [`Ursus_bot`](https://lichess.org/@/Ursus_bot)

It is playing on an old Intel NUC with a Intel® Core™ i5-4250U configured for 2 threads and a hash size of 1GB.

[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=bullet)](https://lichess.org/@/Ursus_bot/perf/bullet)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=blitz)](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=blitz)
[![lichess-rapid](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=rapid)](https://lichess-shield.vercel.app/api?username=Ursus_bot&format=rapid)

---

## Building

Ursus requires a [Zig](https://ziglang.org/) compiler. Because of Zigs pre 1.0 status and breaking changes it is recommended to use Zig 0.15.2 for building. There are no guarantees that code will compile on any other versions of Zig.

Ursus uses [Fathom](https://github.com/jdart1/Fathom) for Syzygy endgame tablebase probing. Place the Fathom source files (`tbprobe.c`, `tbprobe.h`, `tbconfig.h`, `stdendian.h`) under `deps/Fathom/src/` before building -- Fathom is bundled in via the build script and does not need to be installed separately. It is the only external dependency.

Turning on optimizations and native target is highly recommended for best performance.

```bash
zig build -Doptimize=ReleaseFast -Dtarget=native

```

The resulting binary communicates over standard input/output using the UCI protocol and is compatible with any UCI chess GUI (Arena, CuteChess, etc.).
There is also a secondary bindary `texel_tuner` for runing texel tuning on the legacy hand-crafted evaluation function, this is depricated and will eventually be removed.

---

## UCI Protocol Support

Ursus implements the core UCI protocol. The table below summarizes supported commands.

| Command | Status |
| --- | --- |
| `uci` | Supported |
| `isready` | Supported |
| `ucinewgame` | Supported -- resets the board and clears the TT |
| `position startpos [moves ...]` | Supported |
| `position fen <fen> [moves ...]` | Supported |
| `go` | Supported -- accepts `wtime`, `btime`, `winc`, `binc`, `movestogo`, `depth`, `nodes`, `mate`, `movetime`, `infinite`, `ponder` |
| `stop` | Supported |
| `ponderhit` | Supported |
| `quit` | Supported |
| `debug` | Supported -- turns debug mode on/off or prints current board FEN, debug mode is used to print any errors or warnings when parsing UCI commands or during search |
| `d` | Supported -- pretty-prints the current board |
| `register` | Accepted |
| `setoption name Hash` | Sets Hash size in MB, default 256 MB, supported up to 16384MB (16GB) |
| `setoption name Clear Hash` | Supported |
| `setoption name Ponder` | Supported |
| `setoption name Threads` | Sets number of search threads, default 1, supported up to 128 |
| `setoption name SyzygyPath` | Path to directory containing Syzygy tablebases (`.rtbw` / `.rtbz`); multiple directories separated by `:` on Unix or `;` on Windows. Empty / `<empty>` unloads. |
| `setoption name SyzygyProbeDepth` | Minimum depth at which in-tree WDL probing fires, default 1. Increase if TB probing causes a noticeable NPS drop. |
| `datagen` | Used to run self-play data generation for training the NNUE |
| `eval` / `hce` | Supported -- prints the current static NNUE or legacy HCE evaluation |

---

## Acknowledgements

- [fastchess](https://github.com/Disservin/fastchess) For being using to run my SPRT tests
- [cutechess](https://github.com/cutechess/cutechess) For being used to run tournaments and as a GUI for allowing me to play Ursus when it was much weaker.
- [Fathom](https://github.com/jdart1/Fathom) For the Syzygy tablebase probing library.
- [Syzygy tablebases](https://github.com/syzygy1/tb) by Ronald de Man, the underlying tablebase format Ursus probes.
- [bullet](https://github.com/jw1912/bullet) For running NNUE training.
- [weather-factory](https://github.com/jnlt3/weather-factory) Initially I ran my own spsa training code but yours was better and easier to use so thank you.
- [Kaggle](https://www.kaggle.com/) For providing free GPU resources for training the NNUE
- [lichess-bot](https://github.com/lichess-bot-devs/lichess-bot) For providing the interface for Ursus to play on lichess

## Special Thanks

- [Sebastian Lague](https://www.youtube.com/c/SebastianLague) and [tom7](https://tom7.org/chess/) For their excellent chess programming videos that first got me interested in chess engine development
- [Code Monkey King](https://www.youtube.com/@chessprogramming591) Whose [Bitboard CHESS ENGINE in C](https://www.youtube.com/playlist?list=PLmN0neTso3Jxh8ZIylk74JpwfiWNI76Cs) helped me through the early stages of development in particular with understanding bitboard move generation and board representation.
- [Ciekce](https://github.com/Ciekce), author of [Stormphrax](https://github.com/Ciekce/Stormphrax) which I often used as a reference. Also for being a helpful resource for engine development.
- [Jonathan Hallström](https://github.com/JonathanHallstrom), author of [Pawnocchio](https://github.com/JonathanHallstrom/pawnocchio) and [Yinuo Huang](https://github.com/SnowballSH) author of [Avalanche](https://github.com/SnowballSH/Avalanche) Both of your engines were helpful references for my own engine development as fellow Zig engines.
- [Engine Programming Discord](https://discord.com/invite/F6W6mMsTGN) For being a great resource for engine development and providing a friendly community to discuss chess programming with. Also for putting up with me.
- [Chess Programming Wiki](https://www.chessprogramming.org/) For being a great resource for learning about different techniques and the history of chess programming.
- [lichess](https://lichess.org/) For allowing me to have Ursus play games on their platform
