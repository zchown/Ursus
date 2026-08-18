EXE ?= ursus
EVALFILE ?=

ZIG   ?= zig
CORES ?= 8

build:
	@n=$$(nproc 2>/dev/null || echo 1); \
	[ "$$n" -gt $(CORES) ] && n=$(CORES) || :; \
	if [ "$$(uname -s)" = "Linux" ] && command -v taskset >/dev/null 2>&1; then \
		taskset -c 0-$$((n-1)) $(ZIG) build -Doptimize=ReleaseFast -Dtarget=native; \
	else \
		$(ZIG) build -Doptimize=ReleaseFast -Dtarget=native; \
	fi
	cp zig-out/bin/Ursus $(EXE)
