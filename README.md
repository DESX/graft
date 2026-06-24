# Graft

Graft is a library for GNU Makefiles. Include a single `graft.mk` and you get
macros for fetching, caching, patching, and overlaying source dependencies, plus
a small process supervisor. It needs only `make`, `curl`, `git`, `tar`, and a C
compiler.

Every macro is prefixed `GRAFT_`, and every variable a dependency reads is named
`NAME_FIELD` — so `grep GRAFT_` and `grep NAME_` tell you exactly what comes from
graft and what each dependency uses. Full variable lists live in the header
comment of `graft.mk`.

## Self-bootstrapping

You don't have to vendor `graft.mk`. Add a rule that clones graft when the
include is missing, then `include` it — on a fresh checkout `make` fetches graft
and re-reads the Makefile with the macros available, no setup step. Pin a release
tag so the build stays reproducible.

```makefile
GRAFT_URL ?= https://github.com/DESX/graft.git
GRAFT_REV ?= v1.3.0
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

`NAME_TGT` is any file that exists once extraction succeeds; depend on it from
your build rules. The source is one of `NAME_GIT_URL` (with `NAME_COMMIT`),
`NAME_TAR_URL`, or `NAME_ZIP_URL`.

**The caching is the important part.** The cached archive's filename embeds a
version token — the git commit, or a hash of the URL. Bump `FMT_COMMIT` and the
filename changes, so graft fetches the new version and re-extracts; leave it
alone and nothing re-downloads. No stale checkouts, no manual cache busting.

## Patching a dependency

Set `NAME_PATCH` to a tracked diff and graft applies it automatically right after
extraction, on every clean build — so your changes survive a re-fetch.

```makefile
FMT_PATCH := patches/fmt.patch
$(eval $(call GRAFT_FETCH,FMT))
```

To change the patch, edit the extracted files **in place** under the build dir,
then run the generated `name_patch` target. Graft diffs your edits against a
clean extraction and rewrites the patch file for you:

```
# edit build/fmt/... directly, then:
make fmt_patch       # regenerates patches/fmt.patch from your in-place edits
```

## Overlaying files

`NAME_OVERLAY` points at a directory of your own files; graft symlinks each one
over the matching path in the extracted dependency.

```makefile
FMT_OVERLAY := overlays/fmt/
$(eval $(call GRAFT_FETCH,FMT))
```

Drop `overlays/fmt/include/foo.h` and it replaces `build/fmt/include/foo.h`.
Because they're symlinks, editing the file **under the build dir** edits your
tracked source — the change shows up in `git status` instead of being buried in
the build tree. Good for swapping a header or config file without keeping a diff.

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

## Testing & requirements

```bash
cd tests && make
```

Requires GNU Make, curl, git, tar (with gzip), and a C compiler — plus `unzip`
for zip sources and `patch` for patches.

## License

MIT. See [LICENSE](LICENSE).
