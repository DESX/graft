# Graft

Graft is a Makefile library: a single `graft.mk` that you `include`. It provides
macros for fetching, extracting, and patching source dependencies, and for
supervising long-running processes via pidfiles. It relies only on common tools
— `make`, `curl`, `git`, `tar`, and a C compiler for the process watchdog.

## Features

- **Fetch & extract** — download a dependency from a tarball URL, a zip URL, or a
  git repository and extract it into a directory you choose; archives are cached.
- **Version-aware caching** — the default cache filename embeds a version token
  (the git commit, or a hash of the source URL), so bumping the version fetches a
  fresh archive and re-extracts instead of reusing a stale one.
- **Patching** — apply a tracked unified diff after extraction, and regenerate it
  with `make <dep>_patch` after editing the extracted source.
- **Overlays** — symlink your own files over an extracted dependency, e.g. to
  replace a header or drop in a config file.
- **Inter-dependency ordering** — require one dependency to be built before
  another, e.g. build a tool and then use it to build the next dependency.
- **Process supervision** — start, stop, and monitor a long-running process
  through a pidfile maintained by a small watchdog (`pidwatch`), with timeouts
  and readiness probes.
- **Self-bootstrapping** — optionally have Make fetch graft itself on first use,
  pinned to a release tag.

## Conventions

- **The caller sets every meaningful variable.** Each macro reads variables of the
  form `NAME_FIELD` (install dir, target probe, source URL, git commit, …); graft
  does not guess them, and a missing required field raises an immediate
  `$(error)`. So `grep NAME_` in your Makefile lists everything a dependency uses.
  The two exceptions are the mechanical paths `NAME_TAR` (cache file, default
  `$(DL)/<name>-<ver>.tar.gz`) and `NAME_TMP` (git scratch dir, default
  `/tmp/graft_<name>`); set either to override.
- **Every macro is prefixed `GRAFT_`** — `GRAFT_FETCH`, `GRAFT_DAEMON`,
  `GRAFT_MK_DIR`, and helpers like `GRAFT_LOWER` — so `grep GRAFT_` shows exactly
  what comes from graft.

## Setup

Two variables configure where things go, plus a list of directories to create:

| Variable | Description |
|----------|-------------|
| `b` | Output directory — `pidwatch` and all extracted deps land here |
| `DL` | Download cache |
| `DIRS` | Every directory the rules need; feed to `GRAFT_MK_DIR` |

Then `include graft.mk` — either vendored into your repo, or self-bootstrapped
(see [Self-bootstrapping](#self-bootstrapping)).

## Quick start

```makefile
b  := build
DL := .cache

include graft.mk

# Declare the install dir, a probe file, and the source. TAR/TMP paths default.
FMT_DIR     := $b/fmt
FMT_TGT     := $(FMT_DIR)/README.md
FMT_COMMIT  := 10.2.1
FMT_GIT_URL := https://github.com/fmtlib/fmt.git
$(eval $(call GRAFT_FETCH,FMT))

my_app: main.cpp $(FMT_TGT)
	g++ -o $@ $< -I$(FMT_DIR)/include

DIRS := $b $(DL) $(FMT_DIR)
$(foreach d,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$d)))
```

`make` fetches, caches, and extracts the dependency, then builds `my_app`.

## GRAFT_FETCH — fetch & extract

`$(eval $(call GRAFT_FETCH,NAME))` emits rules to download an archive, extract it
into `$(NAME_DIR)`, and optionally patch or overlay it. Set the variables before
the call.

### Required

| Variable | Description |
|----------|-------------|
| `NAME_DIR` | Install directory |
| `NAME_TGT` | Existence probe (any file inside `NAME_DIR`) |
| One of `NAME_TAR_URL` / `NAME_ZIP_URL` / `NAME_GIT_URL` | Source |
| `NAME_COMMIT` | Required when `NAME_GIT_URL` is set |

### Optional

| Variable | Description |
|----------|-------------|
| `NAME_TAR` | Cached archive path (default `$(DL)/<name>-<ver>.tar.gz`, where `<ver>` is the commit or a URL hash — so a version bump re-fetches) |
| `NAME_TMP` | Git clone scratch dir (default `/tmp/graft_<name>`; git only) |
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

After editing files in `$(FMT_DIR)`, run `make fmt_patch` to regenerate the patch
file. Graft re-extracts a clean copy of the archive, diffs against your modified
tree, and writes the result to `FMT_PATCH`.

### Overlays

```makefile
FMT_OVERLAY := overlays/fmt/
```

Every file under `overlays/fmt/` is symlinked into the matching spot in
`$(FMT_DIR)`, preserving directory structure. Useful for header replacement or
drop-in config files.

### Inter-dependency ordering

```makefile
CMAKE_DIR     := $b/cmake
CMAKE_TGT     := $(CMAKE_DIR)/bin/cmake
CMAKE_TAR     := $(DL)/cmake.tar.gz
CMAKE_TAR_URL := https://github.com/Kitware/CMake/releases/download/v3.28.0/cmake-3.28.0-linux-x86_64.tar.gz
$(eval $(call GRAFT_FETCH,CMAKE))

FMT_PRE_UNPACK = $(CMAKE_TGT) -S $(FMT_TMP) -B build && $(CMAKE_TGT) --build build
FMT_EXTRA      = $(CMAKE_TGT)
# … then $(eval $(call GRAFT_FETCH,FMT))
```

## GRAFT_DAEMON — pidfile-managed processes

`$(eval $(call GRAFT_DAEMON,NAME))` emits rules to start, monitor, and stop a
long-running process. The pidfile is the contract: it exists if and only if the
process is alive, and a background watchdog (`pidwatch`) maintains that invariant.

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
$(eval $(call GRAFT_FETCH,DEVD))

SRV_CMD         := $(abspath $(DEVD_TGT)) -l -p 8080 $(abspath $b/site)
SRV_DEP         := $(DEVD_TGT)
SRV_PIDFILE     := $b/server.pid
SRV_TIMEOUT     := 86400
SRV_READY_CMD   := curl -sf http://localhost:8080/ > /dev/null
SRV_READY_TRIES := 20
$(eval $(call GRAFT_DAEMON,SRV))

dev: $(SRV_PIDFILE)
stop: srv_stop
```

## GRAFT_MK_DIR — bulk `mkdir -p` rules

```makefile
DIRS := $b $(DL) $(FMT_DIR)
$(foreach d,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$d)))
```

## Self-bootstrapping

Instead of vendoring `graft.mk` and `pidwatch.c` into your repo, you can let Make
fetch graft on first use. Add a rule that clones graft if the include is missing,
then `include` it — on a fresh checkout `make <anything>` clones graft, then
re-reads the Makefile with the macros available, with no separate setup step.

Pin a release tag rather than a branch: tracking `main` lets an upstream change
alter your build between checkouts, whereas graft's immutable `vX.Y.Z` tags are
reproducible and keep the bootstrap to a single shallow clone.

```makefile
GRAFT_URL ?= https://github.com/DESX/graft.git
GRAFT_REV ?= v1.2.0
.cache/graft/graft.mk:; @git clone -q --depth=1 -b $(GRAFT_REV) $(GRAFT_URL) $(dir $@)
include .cache/graft/graft.mk
```

To update graft, change `GRAFT_REV` to a newer tag and delete `.cache/graft`.

`git clone -b` accepts a tag or branch name but cannot pin a bare commit SHA. To
pin a non-tag commit, replace the clone with:

```makefile
.cache/graft/graft.mk:
	@mkdir -p $(dir $@)
	@git -C $(dir $@) init -q
	@git -C $(dir $@) fetch -q --depth=1 $(GRAFT_URL) <sha>
	@git -C $(dir $@) checkout -q FETCH_HEAD
```

## Testing

```bash
cd tests && make
```

Run an individual test with `cd tests && make test_git_clone`.

## Requirements

- GNU Make
- curl, git, tar (with gzip), cc
- unzip (only if using `NAME_ZIP_URL`)
- patch (only if using `NAME_PATCH`)

## License

MIT. See [LICENSE](LICENSE).
