# Graft: Make helpers for fetching dependencies and supervising processes
# MIT License
#
# Before including, set:
#   b             output directory (e.g. build); holds generated output, safe to clean
#   GRAFT_CACHE   download cache (e.g. .cache); holds fetched archives/files, meant to
#                 outlive `make clean`. Use ?= so it can point at a shared/relocated
#                 cache. All cache paths are relative to it, so the cache dir can be
#                 moved or copied between machines without breaking a rebuild.
#
# Design rule: every macro below only READS variables of the form NAME_FIELD.
# The only values graft fills in are the mechanical paths — the install dir, cache
# path, and clone scratch dir (DIR, TAR, TMP, FILE) — and only when the caller left
# them unset; everything else must be provided. So `grep NAME_` in a caller
# Makefile, plus those documented defaults, accounts for every variable used.
# Missing required fields trigger an immediate $(error).
#
# ─── GRAFT_FETCH(NAME) ────────────────────────────────────────────────────────────
#   Fetches and extracts a dependency. Reads ($1 = NAME, uppercase):
#     $1_TGT          existence probe, relative to DIR              [required]
#     $1_DIR          install dir                     [default $b/<name>-<ver>]
#     $1_TAR          cache handle      [default $(GRAFT_CACHE)/<keyhash>, content-addressed]
#     One of:
#       $1_TAR_URL    tarball URL
#       $1_ZIP_URL    zip URL (extracted with unzip)
#       $1_GIT_URL    git URL
#     $1_COMMIT       git tag, branch, or full commit SHA         [git only]
#     $1_TMP          scratch dir for git clone  [git only; default $b/graft-tmp/<name>]
#     $1_SHA256       expected sha256 of the fetched archive       [optional]
#                     (set empty to make the build print the hash to pin)
#     $1_EXTRA        extra prereqs of the archive                 [optional]
#     $1_PRE_UNPACK   shell hook before the git clone is archived  [optional]
#     $1_POST_UNPACK  shell hook after extraction                  [optional]
#     $1_PATCH        unified diff applied after extraction        [optional]
#     $1_OVERLAY      dir whose files are symlinked over $1_DIR    [optional]
#   Caller must also add $($1_DIR) and $(GRAFT_CACHE) to DIRS.
#   Generates: name_tgt (phony → $1_TGT), name_patch (if $1_PATCH set).
#
# ─── GRAFT_FETCH_FILE(NAME) ─────────────────────────────────────────────────
#   Fetches a single file (no archive, no extraction). Reads:
#     $1_TGT          install path for the file                     [required]
#     $1_URL          source URL                                    [required]
#     $1_FILE         cache handle      [default $(GRAFT_CACHE)/<keyhash>, content-addressed]
#     $1_SHA256       expected sha256 of the downloaded file        [optional]
#                     (set empty to make the build print the hash to pin)
#     $1_EXTRA        extra prereqs of the download                 [optional]
#     $1_POST_FETCH   shell hook after the file is installed        [optional]
#   Caller must add $(GRAFT_CACHE) to DIRS; the install dir is created automatically.
#   Generates: name_tgt (phony → $1_TGT).
#
# ─── GRAFT_DAEMON(NAME) ───────────────────────────────────────────────────────────
#   Supervises a long-running process via a pidfile. Reads:
#     $1_CMD          command to run                               [required]
#     $1_PIDFILE      pidfile path                                 [required]
#     $1_TIMEOUT      auto-kill after N seconds                    [required]
#     $1_READY_CMD    readiness probe command                      [required]
#     $1_READY_TRIES  readiness probe attempts                     [required]
#     $1_DEP          make prerequisites that trigger restart      [optional]
#   Global flag: RESTART=1 stops all daemons at make startup.
#   Generates: $1_PIDFILE (file rule), name_stop (phony).
#
# ─── GRAFT_MK_DIR(DIR) ────────────────────────────────────────────────────────────
#   Emits a `mkdir -p` rule. Use with:
#     $(foreach d,$(DIRS),$(eval $(call GRAFT_MK_DIR,$d)))

GRAFT_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

# A per-invocation id used to name temp files. Downloads/archives are written to
# "<final>.part.$(GRAFT_RUNID)" and atomically renamed into place, so a crashed or
# concurrent build never leaves a half-written file that looks like a valid cache
# entry — important when GRAFT_CACHE is shared between projects or jobs.
GRAFT_RUNID := $(shell echo $$$$)

# ── helpers ─────────────────────────────────────────────────────────────────

# $(call GRAFT_LOWER,STR): lowercase
GRAFT_LOWER = $(shell echo '$1' | tr '[:upper:]' '[:lower:]')

# $(call GRAFT_VTOKEN,NAME): a human-readable, filename-safe version token: the git
# commit/tag (with '/' made safe), or a short hash of the source URL. Used for the
# install dir name ($b/<name>-<ver>) so a version bump lands in a fresh dir.
GRAFT_VTOKEN = $(if $($1_GIT_URL),$(subst /,_,$($1_COMMIT)),$(firstword $(shell printf %s '$($1_TAR_URL)$($1_ZIP_URL)$($1_URL)' | cksum)))

# $(call GRAFT_SHAKEY,NAME): the SHA component of the cache key. The pinned hash if
# set; a 'discover' sentinel if $1_SHA256 is defined but empty (so discovery mode
# gets its own key and always re-downloads to print the hash, even if a no-SHA copy
# is already cached); empty if $1_SHA256 is unset.
GRAFT_SHAKEY = $(if $(filter-out undefined,$(origin $1_SHA256)),$(or $($1_SHA256),discover),)

# $(call GRAFT_KEYHASH,NAME): 12 hex of sha256 over the pinned commit/version, every
# source URL field, AND the SHA key part. This keys the cache file, so any change to
# the version, commit, URL, or expected hash produces a new key (and a re-download +
# re-verify). Unlike VTOKEN it folds in the URL, so two deps pinned to the same
# tag/commit never collide.
GRAFT_KEYHASH = $(shell printf %s '$($1_COMMIT)|$($1_GIT_URL)|$($1_TAR_URL)|$($1_ZIP_URL)|$($1_URL)|$(call GRAFT_SHAKEY,$1)' | sha256sum | cut -c1-12)

# GRAFT_FINALIZE: shell snippet ending a fetch recipe. The freshly downloaded
# "$@.part.<runid>" is content-addressed as "<handle>_<sha256[:12]>" and the Make
# handle ($@) is pointed at it by a relative symlink. So the stored cache file name
# is <keyhash>_<filehash> (opaque, storage-only), while $@ stays a stable target.
GRAFT_FINALIZE = fh=$$$$(sha256sum "$$@.part.$(GRAFT_RUNID)" | cut -c1-12) && mv -f "$$@.part.$(GRAFT_RUNID)" "$$@_$$$$fh" && ln -sfn "$$$$(basename "$$@")_$$$$fh" "$$@"

# $(call GRAFT_VERIFY,NAME): integrity check run on "$@.part.<runid>" when
# $1_SHA256 is DEFINED (even if empty). Empty => "discovery" mode: print the actual
# hash as a ready-to-paste assignment and fail, so you can pin it. Set but wrong =>
# fail with expected-vs-actual. Matches => pass. Used by every fetch type.
GRAFT_VERIFY = want='$($1_SHA256)'; got=$$$$(sha256sum "$$@.part.$(GRAFT_RUNID)" | cut -d' ' -f1); if [ -z "$$$$want" ]; then printf 'graft: %s_SHA256 is empty — pin it by adding:\n    %s_SHA256 := %s\n' '$1' '$1' "$$$$got" >&2; rm -f "$$@.part.$(GRAFT_RUNID)"; exit 1; elif [ "$$$$want" != "$$$$got" ]; then printf 'graft: %s_SHA256 mismatch\n  expected: %s\n  actual:   %s\n' '$1' "$$$$want" "$$$$got" >&2; rm -f "$$@.part.$(GRAFT_RUNID)"; exit 1; fi

# $(call GRAFT_OVERLAY,SRC,DST): symlink files from SRC into DST (shell snippet)
define GRAFT_OVERLAY
find $1 -type f -printf '%P\n' | while read -r f; do \
	mkdir -p "$2/$$(dirname "$$f")" && rm -f "$2/$$f" && \
	ln -rs "$$(realpath "$1/$$f")" "$2/$$f"; \
done
endef

# $(call GRAFT_REQUIRE,NAME,FIELD ...): error if any NAME_FIELD is empty
GRAFT_REQUIRE = $(foreach f,$2,$(if $($1_$f),,$(error graft: $1_$f must be set)))

define GRAFT_MK_DIR
$1:
	mkdir -p $$@
endef

# pidwatch binary: compiled into $b/ so `make clean` removes it
GRAFT_PIDWATCH := $b/pidwatch
$(GRAFT_PIDWATCH): $(GRAFT_DIR)pidwatch.c | $b
	@cc -O2 -o $@ $<

# ── GRAFT_FETCH ───────────────────────────────────────────────────────────────────
define GRAFT_FETCH
$(eval _n := $(call GRAFT_LOWER,$1))
# Mechanical paths default for convenience; set them before the call to override.
# DIR (install dir) carries a human-readable version token, so bumping the pinned
# version lands the new source in a fresh dir and re-extracts cleanly — old
# versions stay put, switching back reuses them, no stale files. TAR is the cache
# handle: a stable symlink named by GRAFT_KEYHASH(version+url) pointing at the
# content-addressed file. TMP is git-clone scratch, under $b so it is per-project
# and cleaned by `make clean`. Only TGT (the existence probe, relative to DIR) is
# mandatory.
$(if $($1_DIR),,$(eval $1_DIR := $b/$(_n)-$(call GRAFT_VTOKEN,$1)))
$(if $($1_GIT_URL),$(if $($1_TMP),,$(eval $1_TMP := $b/graft-tmp/$(_n))))
$(if $($1_TAR),,$(eval $1_TAR := $(GRAFT_CACHE)/$(call GRAFT_KEYHASH,$1)))
$(call GRAFT_REQUIRE,$1,TGT TAR)
$(if $($1_GIT_URL),$(call GRAFT_REQUIRE,$1,COMMIT TMP))
# TGT is given relative to the install dir; make it absolute so the versioned DIR
# (and thus a version bump) flows through to every rule that depends on it.
$(eval $1_TGT := $($1_DIR)/$($1_TGT))

# Downloads use `curl -fL` so an HTTP error (404, 500) fails the build instead of
# saving the error page as the archive. Each fetch writes to a temp file, then
# GRAFT_VERIFY checks it (if $1_SHA256 is set — empty triggers hash discovery) and
# GRAFT_FINALIZE content-addresses it and points the cache handle ($@) at it, so the
# cache only ever holds complete, verified, named-by-content files. $1_SHA256 works
# for every source type (git/tar/zip/file).
ifneq ($($1_TAR_URL),)
$($1_TAR): | $(GRAFT_CACHE) $($1_EXTRA)
	curl -fL --retry 3 $($1_TAR_URL) > $$@.part.$(GRAFT_RUNID)
	$(if $(filter-out undefined,$(origin $1_SHA256)),@$(call GRAFT_VERIFY,$1),@:)
	@$(GRAFT_FINALIZE)
endif

ifneq ($($1_ZIP_URL),)
$($1_TAR): | $(GRAFT_CACHE) $($1_EXTRA)
	curl -fL --retry 3 $($1_ZIP_URL) > $$@.part.$(GRAFT_RUNID)
	$(if $(filter-out undefined,$(origin $1_SHA256)),@$(call GRAFT_VERIFY,$1),@:)
	@$(GRAFT_FINALIZE)
endif

ifneq ($($1_GIT_URL),)
$($1_TAR): | $(GRAFT_CACHE) $($1_EXTRA)
	rm -rf $($1_TMP) && mkdir -p $($1_TMP)
	git -C $($1_TMP) init -q
	git -C $($1_TMP) remote add origin $($1_GIT_URL)
	git -C $($1_TMP) fetch -q --depth 1 origin $($1_COMMIT)
	git -C $($1_TMP) -c advice.detachedHead=false checkout -q FETCH_HEAD
	git -C $($1_TMP) submodule update -q --init --recursive --depth 1
ifneq ($($1_PRE_UNPACK),)
	$($1_PRE_UNPACK)
endif
	tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C $(dir $($1_TMP)) --exclude='.git*' -cf - $(notdir $($1_TMP)) | gzip -n > $$@.part.$(GRAFT_RUNID)
	$(if $(filter-out undefined,$(origin $1_SHA256)),@$(call GRAFT_VERIFY,$1),@:)
	@$(GRAFT_FINALIZE)
endif

# TAR is a normal prerequisite (not order-only) so a freshly fetched archive
# (e.g. after a version bump changes the cache filename) re-extracts over the
# existing install dir. DIR stays order-only (its mtime churns as files land).
ifneq ($($1_ZIP_URL),)
$($1_TGT): $($1_TAR) | $($1_DIR)
	cd $($1_DIR) && unzip -o $(abspath $($1_TAR))
	@touch $(abspath $($1_TGT))
else
$($1_TGT): $($1_TAR) | $($1_DIR)
	tar -xf $($1_TAR) --strip-components=1 -C $($1_DIR) --touch
endif
ifneq ($($1_POST_UNPACK),)
	$($1_POST_UNPACK)
endif
ifneq ($($1_PATCH),)
	if [ -s $($1_PATCH) ]; then patch -p2 -d $($1_DIR) < $($1_PATCH); fi
endif
ifneq ($($1_OVERLAY),)
	$$(call GRAFT_OVERLAY,$($1_OVERLAY),$($1_DIR))
endif

.PHONY: $(_n)_tgt
$(_n)_tgt: $($1_TGT)

ifneq ($($1_PATCH),)
# name_patch diffs the live (edited) install dir against a pristine tree it
# reconstructs from the cached archive. It depends on TAR, NOT TGT, on purpose:
# pulling TGT into the graph lets a missing or freshly-rebuilt archive re-extract
# over the very edits being captured, silently yielding an empty patch. TAR is
# re-fetched if absent; the install dir is always read exactly as it sits.
.PHONY: $(_n)_patch
$(_n)_patch: $($1_TAR)
	@test -d $($1_DIR) || { echo "graft: $($1_DIR) missing — run 'make' and edit it before 'make $(_n)_patch'"; exit 1; }
	rm -rf $($1_TMP) && mkdir -p $($1_TMP)/old
	cp -r $($1_DIR) $($1_TMP)/new
	tar -xf $($1_TAR) --strip-components=1 -C $($1_TMP)/old
	find "$($1_TMP)/new" -mindepth 1 | while read -r item; do \
		rel="$$$${item#$($1_TMP)/new/}"; \
		[ ! -e "$($1_TMP)/old/$$$$rel" ] && rm -rf "$$$$item" || :; \
	done
ifneq ($($1_OVERLAY),)
	$$(call GRAFT_OVERLAY,$($1_OVERLAY),$($1_TMP)/old)
	$$(call GRAFT_OVERLAY,$($1_OVERLAY),$($1_TMP)/new)
endif
	@mkdir -p $(dir $(abspath $($1_PATCH)))
	cd $($1_TMP) && diff -ruN ./old ./new > $(abspath $($1_PATCH)) | true
endif
endef

# ── GRAFT_FETCH_FILE ──────────────────────────────────────────────────────────────
define GRAFT_FETCH_FILE
$(eval _n := $(call GRAFT_LOWER,$1))
# FILE is the cache handle: a stable symlink named by GRAFT_KEYHASH(version+url)
# pointing at the content-addressed download, so any change to the URL re-fetches.
$(if $($1_FILE),,$(eval $1_FILE := $(GRAFT_CACHE)/$(call GRAFT_KEYHASH,$1)))
$(call GRAFT_REQUIRE,$1,TGT URL FILE)

# `curl -fL` so an HTTP error fails the build instead of caching the error page;
# GRAFT_FINALIZE content-addresses the download under the cache and points the
# handle at it. $1_SHA256, if set, is the expected sha256 of the downloaded file.
$($1_FILE): | $(GRAFT_CACHE) $($1_EXTRA)
	curl -fL --retry 3 $($1_URL) > $$@.part.$(GRAFT_RUNID)
	$(if $(filter-out undefined,$(origin $1_SHA256)),@$(call GRAFT_VERIFY,$1),@:)
	@$(GRAFT_FINALIZE)

# FILE is a normal prerequisite so a freshly downloaded version re-installs over
# the existing target. The install dir is created on demand.
$($1_TGT): $($1_FILE)
	@mkdir -p $(dir $($1_TGT))
	cp $($1_FILE) $$@
ifneq ($($1_POST_FETCH),)
	$($1_POST_FETCH)
endif

.PHONY: $(_n)_tgt
$(_n)_tgt: $($1_TGT)
endef

# ── GRAFT_DAEMON ──────────────────────────────────────────────────────────────────
# Optional: $1_STDOUT and $1_STDERR, if set, pidwatch redirects the
# daemon's stdout/stderr to those file paths (append mode) instead of
# /dev/null. The paths are also written into the pidfile so
# `pidwatch status` can show where the logs are.
define GRAFT_DAEMON
$(call GRAFT_REQUIRE,$1,CMD PIDFILE TIMEOUT READY_CMD READY_TRIES)
$(eval _n := $(call GRAFT_LOWER,$1))

.PHONY: $(_n)_stop $(_n)_status
$(_n)_stop: $(GRAFT_PIDWATCH)
	@$(GRAFT_PIDWATCH) stop $($1_PIDFILE)

$(_n)_status: $(GRAFT_PIDWATCH)
	@$(GRAFT_PIDWATCH) status $($1_PIDFILE)

ifdef RESTART
$(shell $(GRAFT_PIDWATCH) stop $($1_PIDFILE) 2>/dev/null)
endif

$($1_PIDFILE): $($1_DEP) $(GRAFT_PIDWATCH)
	@$(GRAFT_PIDWATCH) stop $$@
	@$(GRAFT_PIDWATCH) start $$@ $($1_TIMEOUT) \
		$(if $($1_STDOUT),-o $($1_STDOUT)) \
		$(if $($1_STDERR),-e $($1_STDERR)) \
		$($1_CMD)
	@t=0; while [ $$$$t -lt $($1_READY_TRIES) ]; do \
		$($1_READY_CMD) 2>/dev/null && break; \
		t=`expr $$$$t + 1`; sleep 0.1; \
	done
endef
