EXE ?= ursus
EVALFILE ?=

NET_DEST := src/nnue/nets/quantised10bucket.bin

ZIG   ?= zig
CORES ?= 8

build:
	@if [ -n "$(EVALFILE)" ]; then \
		mkdir -p "$$(dirname $(NET_DEST))"; \
		cp "$(EVALFILE)" "$(NET_DEST)"; \
	elif [ ! -f "$(NET_DEST)" ]; then \
		git submodule update --init --depth 1; \
	fi
	@n=$$(nproc 2>/dev/null || echo 1); \
	[ "$$n" -gt $(CORES) ] && n=$(CORES) || :; \
	if [ "$$(uname -s)" = "Linux" ] && command -v taskset >/dev/null 2>&1; then \
		taskset -c 0-$$((n-1)) $(ZIG) build -Doptimize=ReleaseFast -Dtarget=native; \
	else \
		$(ZIG) build -Doptimize=ReleaseFast -Dtarget=native; \
	fi
	cp zig-out/bin/Ursus $(EXE)
