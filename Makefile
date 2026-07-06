EXE ?= ursus
EVALFILE ?=

build:
	zig build -Doptimize=ReleaseFast -Dtarget=native
	cp zig-out/bin/Ursus $(EXE)
