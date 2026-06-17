# Graft

Tiny Make helpers for **fetching dependencies with first-class patching** and for **supervising long-running processes** via pidfiles. One `graft.mk` to include, no other runtime.

## Why Graft?

Existing dependency managers (vcpkg, Conan, CMake FetchContent) treat patching as an afterthought. When you need to fix a bug in a dependency before upstream accepts your PR, you're stuck maintaining a fork.

Graft makes patching a core workflow:

- **Patch files** are tracked in your repo — small, auditable diffs
- **Overlays** let you replace specific files via symlinks
- **Patch regeneration** with `make <dep>_patch` after you modify the extracted source
- **Caching** preserves your patches across rebuilds

### Compared to alternatives

| Feature | Graft | vcpkg | Conan | FetchContent |
|---------|-------|-------|-------|--------------|
| Patching workflow | First-class | Port overlay | Awkward | PATCH_COMMAND |
| Overlay support | Yes | No | No | No |
| Patch regeneration | `make X_patch` | Manual | Manual | Manual |
| Language agnostic | Yes | C/C++ | C/C++ | CMake |
| Dependencies | make, curl, git | vcpkg | pip, conan | cmake |

## Design rule

**Graft never invents variables.** Every `NAME_FIELD` a macro reads must be set by the caller first. That means `grep NAME_` in your Makefile is authoritative — there's no hidden defaulting inside `graft.mk`. Missing required fields trigger an immediate `$(error)`.

## Quick Start

1. Copy `graft.mk` and `pidwatch.c` into your project.
2. Set up your Makefile:

```makefile
b  := build
DL := .cache

include graft.mk

# Declare every variable the macro will read.
FMT_DIR     := $b/fmt
FMT_TGT     := $(FMT_DIR)/README.md
FMT_TAR     := $(DL)/fmt-10.2.1.tar.gz
FMT_TMP     := /tmp/fmt
FMT_COMMIT  := 10.2.1
FMT_GIT_URL := https://github.com/fmtlib/fmt.git
$(eval $(call FETCH,FMT))

my_app: main.cpp $(FMT_TGT)
	g++ -o $@ $< -I$(FMT_DIR)/include

DIRS := $b $(DL) $(FMT_DIR)
$(foreach d,$(sort $(DIRS)),$(eval $(call MK_DIR,$d)))
```

3. Run `make` — the dependency is fetched, cached, and extracted automatically.

## Self-bootstrapping (recommended)

Instead of vendoring `graft.mk` and `pidwatch.c` into your repo, let Make fetch
graft on first use. Add a rule that clones graft if the include is missing, then
`include` it — `make <anything>` on a fresh checkout pulls graft, then re-reads
the Makefile with the macros available. No separate bootstrap step.

**Pin a specific commit, not a branch.** `graft.mk` is the contract your build
depends on; tracking `main` means an upstream change can silently break or alter
your build between checkouts. A pinned SHA makes builds reproducible and updates
an explicit, reviewable change to one line.

```makefile
# Self-bootstrapping graft, pinned to a specific commit for reproducibility.
GRAFT_URL ?= https://github.com/DESX/graft.git
# Pinned commit — bump deliberately. (Keep the SHA on its own line: a trailing
# `# comment` would leave whitespace in the value.)
GRAFT_REV ?= 65dd2d0dd4fedde5a2cab1f381287ae02ec0eabb
.cache/graft/graft.mk:
	@mkdir -p $(dir $@)
	@git -C $(dir $@) init -q
	@git -C $(dir $@) fetch -q --depth=1 $(GRAFT_URL) $(GRAFT_REV)
	@git -C $(dir $@) checkout -q FETCH_HEAD
include .cache/graft/graft.mk
```

A shallow `fetch <sha>` + `checkout FETCH_HEAD` is used rather than
`git clone --depth=1 -b <rev>`, because `-b` only accepts branches and tags — it
cannot pin an arbitrary commit. (GitHub allows fetching a SHA directly.)

To update graft, change `GRAFT_REV` to the new commit and delete `.cache/graft`.

## FETCH — dependency fetch & extract

`$(eval $(call FETCH,NAME))` emits rules to download an archive, extract it into `$(NAME_DIR)`, and optionally patch/overlay it. All variables must be set before the call.

### Required

| Variable | Description |
|----------|-------------|
| `NAME_DIR` | Install directory |
| `NAME_TGT` | Existence probe (any file inside `NAME_DIR`) |
| `NAME_TAR` | Cached archive path |
| One of `NAME_TAR_URL` / `NAME_ZIP_URL` / `NAME_GIT_URL` | Source |
| `NAME_COMMIT`, `NAME_TMP` | Required when `NAME_GIT_URL` is set |

### Optional

| Variable | Description |
|----------|-------------|
| `NAME_EXTRA` | Extra prerequisites of the archive target |
| `NAME_PRE_UNPACK` | Shell hook run inside `NAME_TMP` before archive caching (git only) |
| `NAME_POST_UNPACK` | Shell hook run after extraction |
| `NAME_PATCH` | Unified diff applied with `patch -p2` after extraction |
| `NAME_OVERLAY` | Directory whose files are symlinked over `NAME_DIR` |

### Generated targets

| Target | Description |
|--------|-------------|
| `name_tgt` | Phony → `NAME_TGT` |
| `name_patch` | Regenerate `NAME_PATCH` by diffing `NAME_DIR` against a fresh extraction (only if `NAME_PATCH` is set) |

### Patching

```makefile
FMT_PATCH := patches/fmt-fix-bug.patch
```

After editing files in `$(FMT_DIR)`, run `make fmt_patch` to regenerate the patch file. Graft re-extracts a clean copy of the archive, diffs against your modified tree, and writes the result to `FMT_PATCH`.

### Overlays

```makefile
FMT_OVERLAY := overlays/fmt/
```

Every file under `overlays/fmt/` is symlinked into the matching spot in `$(FMT_DIR)`, preserving directory structure. Useful for header replacement or drop-in config files.

### Inter-dependency ordering

```makefile
CMAKE_DIR     := $b/cmake
CMAKE_TGT     := $(CMAKE_DIR)/bin/cmake
CMAKE_TAR     := $(DL)/cmake.tar.gz
CMAKE_TAR_URL := https://github.com/Kitware/CMake/releases/download/v3.28.0/cmake-3.28.0-linux-x86_64.tar.gz
$(eval $(call FETCH,CMAKE))

FMT_PRE_UNPACK = $(CMAKE_TGT) -S $(FMT_TMP) -B build && $(CMAKE_TGT) --build build
FMT_EXTRA      = $(CMAKE_TGT)
# … then $(eval $(call FETCH,FMT))
```

## DAEMON — pidfile-managed processes

`$(eval $(call DAEMON,NAME))` emits rules to start, monitor, and stop a long-running process. The pidfile is the contract: it exists if and only if the process is alive. A background watchdog (`pidwatch`) maintains that invariant.

### Required

| Variable | Description |
|----------|-------------|
| `NAME_CMD` | Command to run |
| `NAME_PIDFILE` | Pidfile path |
| `NAME_TIMEOUT` | Auto-kill after N seconds |
| `NAME_READY_CMD` | Readiness probe (runs in a retry loop) |
| `NAME_READY_TRIES` | Number of probe attempts (100ms each) |

### Optional

| Variable | Description |
|----------|-------------|
| `NAME_DEP` | Make prerequisites that trigger a restart when they change |

### Generated targets

| Target | Description |
|--------|-------------|
| `NAME_PIDFILE` | File rule — build it to start the process |
| `name_stop` | Phony — stops the process and removes the pidfile |

### Global flags

| Flag | Description |
|------|-------------|
| `RESTART=1` | Stop every registered daemon at make startup |

### Example

```makefile
DEVD_DIR     := $b/devd
DEVD_TGT     := $(DEVD_DIR)/devd
DEVD_TAR     := $(DL)/devd.tgz
DEVD_TAR_URL := https://github.com/cortesi/devd/releases/download/v0.9/devd-0.9-linux64.tgz
$(eval $(call FETCH,DEVD))

SRV_CMD         := $(abspath $(DEVD_TGT)) -l -p 8080 $(abspath $b/site)
SRV_DEP         := $(DEVD_TGT)
SRV_PIDFILE     := $b/server.pid
SRV_TIMEOUT     := 86400
SRV_READY_CMD   := curl -sf http://localhost:8080/ > /dev/null
SRV_READY_TRIES := 20
$(eval $(call DAEMON,SRV))

dev: $(SRV_PIDFILE)
stop: srv_stop
```

## MK_DIR

Helper to emit `mkdir -p` rules in bulk:

```makefile
DIRS := $b $(DL) $(FMT_DIR)
$(foreach d,$(sort $(DIRS)),$(eval $(call MK_DIR,$d)))
```

## Required setup

| Variable | Description |
|----------|-------------|
| `b` | Output directory — `pidwatch` and all extracted deps land here |
| `DL` | Download cache |
| `DIRS` | Append every directory the rules need; feed to `MK_DIR` |

## Testing

```bash
cd tests && make
```

Individual tests: `cd tests && make test_git_clone`.

## Requirements

- GNU Make
- curl, git, tar (with gzip), cc
- unzip (only if using `NAME_ZIP_URL`)
- patch (only if using `NAME_PATCH`)

## License

MIT. See [LICENSE](LICENSE).
