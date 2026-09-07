EXE ?= ursus
EVALFILE ?=
POLICYFILE ?=

ZIG   ?= zig
CORES ?= 8

NET_DIR     := src/nnue/nets
NET_DEST    := $(NET_DIR)/Alkaid.bin
POLICY_DEST := $(NET_DIR)/policy_pw512.bin

NET_URL     := https://raw.githubusercontent.com/zchown/UrsusNets/main/Alkaid.bin
POLICY_URL  := https://raw.githubusercontent.com/zchown/UrsusNets/main/policy_pw512.bin

build:
	@mkdir -p "$(NET_DIR)"
	@if [ -n "$(EVALFILE)" ]; then \
		cp "$(EVALFILE)" "$(NET_DEST)"; \
	elif [ ! -s "$(NET_DEST)" ]; then \
		curl -4 --max-time 10 -sLo "$(NET_DEST)" $(NET_URL); \
	fi
	@if [ -n "$(POLICYFILE)" ]; then \
		cp "$(POLICYFILE)" "$(POLICY_DEST)"; \
	elif [ ! -s "$(POLICY_DEST)" ]; then \
		curl -4 --max-time 10 -sLo "$(POLICY_DEST)" $(POLICY_URL); \
	fi
	@n=$$(nproc 2>/dev/null || echo 1); \
	[ "$$n" -gt $(CORES) ] && n=$(CORES) || :; \
	if [ "$$(uname -s)" = "Linux" ] && command -v taskset >/dev/null 2>&1; then \
		taskset -c 0-$$((n-1)) $(ZIG) build -Doptimize=ReleaseFast -Dtarget=native; \
	else \
		$(ZIG) build -Doptimize=ReleaseFast -Dtarget=native; \
	fi
	cp zig-out/bin/Ursus $(EXE)
