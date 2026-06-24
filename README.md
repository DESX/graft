# Graft

Graft is a library for GNU Makefiles. You include a single `graft.mk` and get
macros for fetching, caching, patching, and overlaying source dependencies, plus
a small process supervisor. It needs only `make`, `curl`, `git`, `tar`, and a C
compiler.

Every macro is prefixed `GRAFT_`, and every variable a dependency reads is named
`NAME_FIELD`, so `grep GRAFT_` and `grep NAME_` show exactly what comes from
graft and what each dependency uses. Full variable lists are in the header
comment of `graft.mk`.

## Features

- [Self-bootstrapping](#self-bootstrapping): clone graft on first build, no vendoring.
- [Fetching a dependency](#fetching-a-dependency): download, cache, and extract a source tree.
- [Patching a dependency](#patching-a-dependency): make a small change to existing upstream files without forking.
- [Overlaying files](#overlaying-files): add or replace whole files with your own.
- [Other macros](#other-macros): single-file fetch, daemon supervision, bulk mkdir.

## Self-bootstrapping

You do not have to vendor `graft.mk`. Add a rule that clones graft when the
include is missing, then `include` it. On a fresh checkout `make` fetches graft
and re-reads the Makefile with the macros available, with no setup step. Pin a
release tag so the build stays reproducible.

```makefile
GRAFT_URL ?= https://github.com/DESX/graft.git
GRAFT_REV ?= v1.4.0
.cache/graft/graft.mk:; @git clone -q --depth=1 -b $(GRAFT_REV) $(GRAFT_URL) $(dir $@)
include .cache/graft/graft.mk
```

To update graft, bump `GRAFT_REV` and delete `.cache/graft`.

## Fetching a dependency

`GRAFT_FETCH` downloads an archive (or clones a git repo), caches it, and
extracts it into a directory you choose. Set the `NAME_*` variables, then call
the macro:

```makefile
b  := build
DL := .cache

FMT_DIR     := $b/fmt
FMT_TGT     := $(FMT_DIR)/README.md
FMT_COMMIT  := 10.2.1
FMT_GIT_URL := https://github.com/fmtlib/fmt.git
$(eval $(call GRAFT_FETCH,FMT))

DIRS := $b $(DL) $(FMT_DIR)
$(foreach d,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$d)))
```

`NAME_TGT` is any file that exists once extraction succeeds; your build rules
depend on it. The source is one of `NAME_GIT_URL` (with `NAME_COMMIT`),
`NAME_TAR_URL`, or `NAME_ZIP_URL`.

The caching is the important part. The cached archive's filename embeds a version
token: the git commit, or a hash of the URL. Bump `FMT_COMMIT` and the filename
changes, so graft fetches the new version and re-extracts. Leave it alone and
nothing re-downloads. No stale checkouts, no manual cache busting.

## Patching a dependency

Patching is for making a small change to files that already exist upstream,
without forking the repo or vendoring its source. You edit the extracted files in
place, and graft captures the edits as a tracked diff that it re-applies on every
clean build.

Point `NAME_PATCH` at a patch file. It does not need to exist yet:

```makefile
FMT_PATCH := patches/fmt.patch
$(eval $(call GRAFT_FETCH,FMT))
```

Say you need to change one line in fmt's `core.h`. The full sequence:

```
make                                # fetches and extracts fmt; no patch yet
vim build/fmt/include/fmt/core.h    # edit the file in place
make fmt_patch                      # writes your edit into patches/fmt.patch
git add patches/fmt.patch           # commit the small diff, not the whole repo
```

From then on, any clean build re-applies `patches/fmt.patch` automatically, so
the change rides along with a fresh fetch. Rerun `make fmt_patch` whenever you
edit the files again to refresh the diff. A patch records changes to files that
already exist; to add brand-new files, use an overlay.

## Overlaying files

An overlay is for adding or replacing whole files with your own, without changing
the upstream content. You keep the file in your repo and graft symlinks it over
the extracted dependency, so it stays a normal tracked file that you fully own.

Point `NAME_OVERLAY` at a directory that mirrors the dependency's layout:

```makefile
FMT_OVERLAY := overlays/fmt/
$(eval $(call GRAFT_FETCH,FMT))
```

Say you want to drop in your own `config.h`. The full sequence:

```
mkdir -p overlays/fmt/include/fmt
echo '#define FMT_HEADER_ONLY 1' > overlays/fmt/include/fmt/config.h
make                                # symlinks it into build/fmt/include/fmt/
git add overlays/fmt                # the file lives in your repo
```

Every file under `overlays/fmt/` is symlinked into the matching path in
`build/fmt/`, so it survives a re-fetch. Because it is a symlink, editing
`build/fmt/include/fmt/config.h` edits your tracked `overlays/fmt/...` copy, and
the change shows up in `git status` instead of being lost in the build tree.

## Other macros

`GRAFT_FETCH_FILE` fetches a single file (a header, binary, or script) to a path
you choose, with the same versioned caching as `GRAFT_FETCH`:

```makefile
STB_TGT := $b/include/stb_image.h
STB_URL := https://raw.githubusercontent.com/nothings/stb/v2.30/stb_image.h
$(eval $(call GRAFT_FETCH_FILE,STB))
```

`GRAFT_DAEMON` starts, probes, and stops a long-running process through a pidfile
kept honest by a bundled watchdog. `GRAFT_MK_DIR` emits `mkdir -p` rules in bulk.
See the header comment in `graft.mk` for their variables.

## Testing and requirements

```bash
cd tests && make
```

Requires GNU Make, curl, git, tar (with gzip), and a C compiler, plus `unzip` for
zip sources and `patch` for patches.

## License

MIT. See [LICENSE](LICENSE).
