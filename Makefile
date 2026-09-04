EXE ?= ursus
EVALFILE ?=

ZIG   ?= zig
CORES ?= 8

NET_DEST := src/nnue/nets/Alkaid.bin

build:
	@if [ -n "$(EVALFILE)" ]; then \
		mkdir -p "$$(dirname $(NET_DEST))"; \
		cp "$(EVALFILE)" "$(NET_DEST)"; \
	elif [ ! -f "$(NET_DEST)" ]; then \
		mkdir -p "$$(dirname $(NET_DEST))"; \
		wget -qO "$(NET_DEST)" https://raw.githubusercontent.com/zchown/UrsusNets/main/Alkaid.bin || curl -sLo "$(NET_DEST)" https://raw.githubusercontent.com/zchown/UrsusNets/main/Alkaid.bin;
	fi
	@n=$$(nproc 2>/dev/null || echo 1); \
	[ "$$n" -gt $(CORES) ] && n=$(CORES) || :; \
	if [ "$$(uname -s)" = "Linux" ] && command -v taskset >/dev/null 2>&1; then \
		taskset -c 0-$$((n-1)) $(ZIG) build -Doptimize=ReleaseFast -Dtarget=native; \
	else \
		$(ZIG) build -Doptimize=ReleaseFast -Dtarget=native; \
	fi
	cp zig-out/bin/Ursus $(EXE)
