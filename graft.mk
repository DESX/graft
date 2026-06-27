# Graft: Make helpers for fetching dependencies and supervising processes
# MIT License
#
# Before including, set:
#   b    output directory (e.g. build)
#   DL   download cache  (e.g. .cache)
#
# Design rule: every macro below only READS variables of the form NAME_FIELD
# that the caller has already defined. Graft never invents defaults, so
# `grep NAME_` in a caller Makefile is authoritative for every variable used.
# Missing required fields trigger an immediate $(error).
#
# ─── GRAFT_FETCH(NAME) ────────────────────────────────────────────────────────────
#   Fetches and extracts a dependency. Reads ($1 = NAME, uppercase):
#     $1_DIR          install dir                                   [required]
#     $1_TGT          existence probe path                          [required]
#     $1_TAR          cached archive path  [default $(DL)/<name>-<ver>.tar.gz]
#     One of:
#       $1_TAR_URL    tarball URL
#       $1_ZIP_URL    zip URL (extracted with unzip)
#       $1_GIT_URL    git URL
#     $1_COMMIT       git tag, branch, or full commit SHA         [git only]
#     $1_TMP          scratch dir for git clone   [git only; default /tmp/graft_<name>]
#     $1_EXTRA        extra prereqs of the archive                 [optional]
#     $1_PRE_UNPACK   shell hook before the git clone is archived  [optional]
#     $1_POST_UNPACK  shell hook after extraction                  [optional]
#     $1_PATCH        unified diff applied after extraction        [optional]
#     $1_OVERLAY      dir whose files are symlinked over $1_DIR    [optional]
#   Caller must also add $($1_DIR) and $(DL) to DIRS.
#   Generates: name_tgt (phony → $1_TGT), name_patch (if $1_PATCH set).
#
# ─── GRAFT_FETCH_FILE(NAME) ─────────────────────────────────────────────────
#   Fetches a single file (no archive, no extraction). Reads:
#     $1_TGT          install path for the file                     [required]
#     $1_URL          source URL                                    [required]
#     $1_FILE         cached download path     [default $(DL)/<name>-<ver>]
#     $1_EXTRA        extra prereqs of the download                 [optional]
#     $1_POST_FETCH   shell hook after the file is installed        [optional]
#   Caller must add $(DL) to DIRS; the install dir is created automatically.
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

# ── helpers ─────────────────────────────────────────────────────────────────

# $(call GRAFT_LOWER,STR): lowercase
GRAFT_LOWER = $(shell echo '$1' | tr '[:upper:]' '[:lower:]')

# $(call GRAFT_VTOKEN,NAME): a filename-safe token that changes whenever the pinned
# source version changes: the git commit (with '/' made safe), or a short hash
# of the tarball/zip/file URL. Embedded in the default cache filename so a version
# bump lands in a new cache file (and re-fetches) instead of reusing the stale one.
GRAFT_VTOKEN = $(if $($1_GIT_URL),$(subst /,_,$($1_COMMIT)),$(firstword $(shell printf %s '$($1_TAR_URL)$($1_ZIP_URL)$($1_URL)' | cksum)))

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
# TAR carries a version token (git commit or a hash of the source URL) so a
# version bump fetches a fresh archive and re-extracts instead of silently
# reusing the stale cached one. TMP is scratch space for the git clone.
$(if $($1_GIT_URL),$(if $($1_TMP),,$(eval $1_TMP := /tmp/graft_$(_n))))
$(if $($1_TAR),,$(eval $1_TAR := $(DL)/$(_n)-$(call GRAFT_VTOKEN,$1).tar.gz))
$(call GRAFT_REQUIRE,$1,DIR TGT TAR)
$(if $($1_GIT_URL),$(call GRAFT_REQUIRE,$1,COMMIT TMP))

ifneq ($($1_TAR_URL),)
$($1_TAR): | $(DL) $($1_EXTRA)
	curl -L $($1_TAR_URL) > $$@
endif

ifneq ($($1_ZIP_URL),)
$($1_TAR): | $(DL) $($1_EXTRA)
	curl -L $($1_ZIP_URL) > $$@
endif

ifneq ($($1_GIT_URL),)
$($1_TAR): | $(DL) $($1_EXTRA)
	rm -rf $($1_TMP) && mkdir -p $($1_TMP)
	git -C $($1_TMP) init -q
	git -C $($1_TMP) remote add origin $($1_GIT_URL)
	git -C $($1_TMP) fetch -q --depth 1 origin $($1_COMMIT)
	git -C $($1_TMP) -c advice.detachedHead=false checkout -q FETCH_HEAD
	git -C $($1_TMP) submodule update -q --init --recursive --depth 1
ifneq ($($1_PRE_UNPACK),)
	$($1_PRE_UNPACK)
endif
	tar -czf $$@ -C $(dir $($1_TMP)) --exclude='.git*' $(notdir $($1_TMP))
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
# FILE is the versioned cache path (default); it carries a hash of the URL so a
# version bump downloads afresh and re-installs instead of reusing the stale one.
$(if $($1_FILE),,$(eval $1_FILE := $(DL)/$(_n)-$(call GRAFT_VTOKEN,$1)))
$(call GRAFT_REQUIRE,$1,TGT URL FILE)

$($1_FILE): | $(DL) $($1_EXTRA)
	curl -L $($1_URL) > $$@

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
