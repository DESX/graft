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
# The values graft fills in are the install dir (DIR) and the git-clone scratch dir
# (TMP), only when unset; the cache itself is managed automatically (see "Cache
# layout" below). Everything else must be provided. So `grep NAME_` in a caller
# Makefile, plus those defaults, accounts for every variable used. Missing required
# fields trigger an immediate $(error).
#
# Cache layout (under GRAFT_CACHE): downloads are stored content-addressed in
#   hash_files/<sha256>   — the file's bytes, named by their own full sha256
#   key_files/<keyhash>   — a small text record per source (12-hex hash of commit+url);
#                           line 1 is the sha256 of that source's content, the rest is
#                           metadata. The build resolves content through these.
#   <NAME>_<file>         — a human-named symlink (root of the cache) to the content,
#                           for manual inspection only; the build never reads it.
#
# ─── GRAFT_FETCH(NAME) ────────────────────────────────────────────────────────────
#   Fetches and extracts a dependency. Reads ($1 = NAME, uppercase):
#     $1_TGT          existence probe, relative to DIR              [required]
#     $1_DIR          install dir                     [default $b/<name>-<ver>]
#     $1_TAR          name of the inspection symlink (cache root)   [optional]
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
#     $1_FILE         name of the inspection symlink (cache root)   [optional]
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

# The cache helper that runs every fetch recipe's body. Make owns the dependency
# graph; graft.sh does the imperative work (download, content-address, verify,
# extract) over explicit file args. It reads GRAFT_CACHE from the environment.
GRAFT_SH := $(GRAFT_DIR)graft.sh
export GRAFT_CACHE

# Always-out-of-date prerequisite. Discovery (empty NAME_SHA256) lists this so the
# extraction always re-runs and prints the hash, even if the install target already
# exists from a previous build.
.PHONY: GRAFT_FORCE
GRAFT_FORCE: ;

# ── helpers ─────────────────────────────────────────────────────────────────

# $(call GRAFT_LOWER,STR): lowercase
GRAFT_LOWER = $(shell echo '$1' | tr '[:upper:]' '[:lower:]')

# $(call GRAFT_VTOKEN,NAME): a human-readable, filename-safe version token: the git
# commit/tag (with '/' made safe), or a short hash of the source URL. Used for the
# install dir name ($b/<name>-<ver>) so a version bump lands in a fresh dir.
GRAFT_VTOKEN = $(if $($1_GIT_URL),$(subst /,_,$($1_COMMIT)),$(firstword $(shell printf %s '$($1_TAR_URL)$($1_ZIP_URL)$($1_URL)' | cksum)))

# $(call GRAFT_KEYHASH,NAME): 12 hex of sha256 over the source identity — the commit,
# every URL, AND the build command (PRE_UNPACK). Names the keyfile, so any change to
# the version, commit, URL, or how it's built is a new key. Folds in the URL, so the
# same tag/commit on two repos never collide. The expected SHA is deliberately NOT in
# the key: pinning addresses the content file directly, so adding a hash never
# re-downloads.
GRAFT_KEYHASH = $(shell printf %s '$($1_COMMIT)|$($1_GIT_URL)|$($1_TAR_URL)|$($1_ZIP_URL)|$($1_URL)|$($1_PRE_UNPACK)' | sha256sum | cut -c1-12)

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
# Mechanical paths default; set them before the call to override. DIR (install dir)
# is version-stamped so a version bump lands in a fresh dir. KEY is the keyfile
# ($(GRAFT_CACHE)/key_files/<keyhash>): its first line is the sha256 of the
# downloaded content, stored at $(GRAFT_CACHE)/hash_files/<that-sha>. TMP is git-clone
# scratch under $b. Only TGT (probe, relative to DIR) is mandatory.
$(if $($1_DIR),,$(eval $1_DIR := $b/$(_n)-$(call GRAFT_VTOKEN,$1)))
$(if $($1_GIT_URL),$(if $($1_TMP),,$(eval $1_TMP := $b/graft-tmp/$(_n))))
$(eval $1_KEY := $(GRAFT_CACHE)/key_files/$(call GRAFT_KEYHASH,$1))
# VERBOSE names only the human-readable inspection symlink in the cache root. TAR, if
# set, overrides it (basename only); the content/key stores are ALWAYS hash-named.
$(eval $1_VERBOSE := $(if $($1_TAR),$(notdir $($1_TAR)),$1_$(_n)-$(call GRAFT_VTOKEN,$1)$(if $($1_ZIP_URL),.zip,.tar.gz)))
$(call GRAFT_REQUIRE,$1,TGT)
$(if $($1_GIT_URL),$(call GRAFT_REQUIRE,$1,COMMIT TMP))
$(eval $1_TGT := $($1_DIR)/$($1_TGT))

# ── download: target = the keyfile. graft.sh clones/downloads, content-addresses the
# result into hash_files/, and records its hash + metadata in the keyfile. For a git
# source, PRE_UNPACK runs between the clone and the archive (and is part of the key).
$($1_KEY): | $(GRAFT_CACHE) $($1_EXTRA)
ifneq ($($1_GIT_URL),)
	@sh $(GRAFT_SH) clone $($1_TMP) $($1_GIT_URL) $($1_COMMIT)
ifneq ($($1_PRE_UNPACK),)
	$($1_PRE_UNPACK)
endif
	@sh $(GRAFT_SH) store-dir $$@ $($1_TMP) $1 $($1_VERBOSE) $($1_GIT_URL) $($1_COMMIT) $(if $($1_PRE_UNPACK),yes,no)
else
	@sh $(GRAFT_SH) fetch-file $$@ $(if $($1_TAR_URL),$($1_TAR_URL),$($1_ZIP_URL)) $1 $($1_VERBOSE)
endif

# ── pick the build handle and discovery flag from the SHA state ──
# (Single unconditional evals: $(eval)s inside ifeq branches would all run during the
# $(call), so ifeq can only gate emitted rule text, not assignments.)
#   pinned  (SHA set)        -> handle = the content file named by the pinned hash
#   discover(SHA empty)      -> handle = keyfile; extraction prints the hash and fails
#   unpinned(SHA unset)      -> handle = keyfile
$(eval $1_HANDLE := $(if $(filter-out undefined,$(origin $1_SHA256)),$(if $(strip $($1_SHA256)),$(GRAFT_CACHE)/hash_files/$($1_SHA256),$($1_KEY)),$($1_KEY)))
$(eval $1_DISC := $(if $(filter-out undefined,$(origin $1_SHA256)),$(if $(strip $($1_SHA256)),,1),))

# Pinned only: the content file is keyed on the source via the keyfile, so a source
# change re-runs this and errors with the real hash if the pin no longer matches — you
# can never silently build the old content after bumping a version.
ifneq ($(filter-out undefined,$(origin $1_SHA256)),)
ifneq ($(strip $($1_SHA256)),)
$($1_HANDLE): $($1_KEY)
	@sh $(GRAFT_SH) verify $($1_KEY) $($1_SHA256) $1 '$(if $($1_PRE_UNPACK),built,)'
endif
endif

# ── extract: graft.sh reads the content hash from the keyfile and untars/unzips it
# into DIR (or, in discovery mode, prints the hash and fails).
ifneq ($($1_ZIP_URL),)
$($1_TGT): $($1_HANDLE) $(if $($1_DISC),GRAFT_FORCE) | $($1_DIR) $($1_KEY)
	@sh $(GRAFT_SH) extract $($1_KEY) $($1_DIR) zip '$($1_DISC)' $1
	@touch $(abspath $($1_TGT))
else
$($1_TGT): $($1_HANDLE) $(if $($1_DISC),GRAFT_FORCE) | $($1_DIR) $($1_KEY)
	@sh $(GRAFT_SH) extract $($1_KEY) $($1_DIR) tar '$($1_DISC)' $1
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
# name_patch diffs the live (edited) install dir against the pristine tree, which it
# reconstructs from the cached content (resolved via the keyfile). Depends on the
# keyfile, not TGT, so it never re-extracts over the edits being captured.
.PHONY: $(_n)_patch
$(_n)_patch: $($1_KEY)
	@test -d $($1_DIR) || { echo "graft: $($1_DIR) missing — run 'make' and edit it before 'make $(_n)_patch'"; exit 1; }
	rm -rf $($1_TMP) && mkdir -p $($1_TMP)/old
	cp -r $($1_DIR) $($1_TMP)/new
	@sh $(GRAFT_SH) unpack-pristine $($1_KEY) $($1_TMP)/old
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
# KEY is the keyfile ($(GRAFT_CACHE)/key_files/<keyhash>); its first line is the
# sha256 of the downloaded file, stored at $(GRAFT_CACHE)/hash_files/<that-sha>.
$(eval $1_KEY := $(GRAFT_CACHE)/key_files/$(call GRAFT_KEYHASH,$1))
# VERBOSE names only the inspection symlink; FILE, if set, overrides it (basename).
$(eval $1_VERBOSE := $(if $($1_FILE),$(notdir $($1_FILE)),$1_$(_n)-$(call GRAFT_VTOKEN,$1)))
$(call GRAFT_REQUIRE,$1,TGT URL)

# Download rule, target = the keyfile. graft.sh downloads and content-addresses it.
$($1_KEY): | $(GRAFT_CACHE) $($1_EXTRA)
	@sh $(GRAFT_SH) fetch-file $$@ $($1_URL) $1 $($1_VERBOSE)

# ── pick the build handle and discovery flag from the SHA state (see GRAFT_FETCH) ──
$(eval $1_HANDLE := $(if $(filter-out undefined,$(origin $1_SHA256)),$(if $(strip $($1_SHA256)),$(GRAFT_CACHE)/hash_files/$($1_SHA256),$($1_KEY)),$($1_KEY)))
$(eval $1_DISC := $(if $(filter-out undefined,$(origin $1_SHA256)),$(if $(strip $($1_SHA256)),,1),))
ifneq ($(filter-out undefined,$(origin $1_SHA256)),)
ifneq ($(strip $($1_SHA256)),)
$($1_HANDLE): $($1_KEY)
	@sh $(GRAFT_SH) verify $($1_KEY) $($1_SHA256) $1 ''
endif
endif

# Install: graft.sh resolves the content hash from the keyfile and copies it to TGT.
$($1_TGT): $($1_HANDLE) $(if $($1_DISC),GRAFT_FORCE) | $($1_KEY)
	@sh $(GRAFT_SH) place $($1_KEY) $$@ '$($1_DISC)' $1
ifneq ($($1_POST_FETCH),)
	$($1_POST_FETCH)
endif

.PHONY: $(_n)_tgt
$(_n)_tgt: $($1_TGT)
endef

# ── GRAFT_BUILD ───────────────────────────────────────────────────────────────────
# Builds a fetched source into its own cache entry — the two-stage companion to
# GRAFT_FETCH: stage 1 fetches the source (content-addressed, pinnable as a
# supply-chain input); GRAFT_BUILD is stage 2. It unpacks the source into a scratch
# dir, runs a command there (which MAY use the network), and repacks the result.
# Reads ($1 = NAME):
#   $1_SRC          name of a GRAFT_FETCH dependency to build       [required]
#   $1_CMD          build command, run in the source scratch dir    [required]
#   $1_TGT          existence probe, relative to DIR                [required]
#   $1_DIR          install dir                          [default $b/<name>]
#   $1_TMP          build scratch dir            [default $b/graft-tmp/<name>]
#   $1_SHA256       expected sha256 of the built output             [optional]
#                   (pinning it asserts the build is reproducible; empty = discover)
#   $1_TAR          inspection symlink name                         [optional]
#   $1_EXTRA $1_POST_UNPACK $1_PATCH $1_OVERLAY                      [optional]
# The cache key is the source's keyhash + the build command, so the same source
# built two ways yields two entries and changing the command rebuilds. The built
# output is non-reproducible by nature; pin $1_SHA256 only if you expect it to be.
define GRAFT_BUILD
$(eval _n := $(call GRAFT_LOWER,$1))
$(call GRAFT_REQUIRE,$1,TGT SRC CMD)
$(eval $1_SRCKEY := $($($1_SRC)_KEY))
$(if $($1_SRCKEY),,$(error graft: $1_SRC ('$($1_SRC)') is not a GRAFT_FETCH dependency))
$(if $($1_DIR),,$(eval $1_DIR := $b/$(_n)))
$(if $($1_TMP),,$(eval $1_TMP := $b/graft-tmp/$(_n)))
$(eval $1_KEY := $(GRAFT_CACHE)/key_files/$(shell printf %s 'build|$(notdir $($1_SRCKEY))|$($1_CMD)' | sha256sum | cut -c1-12))
$(eval $1_VERBOSE := $(if $($1_TAR),$(notdir $($1_TAR)),$1_$(_n).tar.gz))
$(eval $1_TGT := $($1_DIR)/$($1_TGT))

# build rule: unpack the source, run the command in the scratch dir, repack.
$($1_KEY): $($1_SRCKEY) | $(GRAFT_CACHE) $($1_EXTRA)
	rm -rf $($1_TMP) && mkdir -p $($1_TMP)
	@sh $(GRAFT_SH) unpack-pristine $($1_SRCKEY) $($1_TMP)
	cd $($1_TMP) && $($1_CMD)
	@sh $(GRAFT_SH) store-build $$@ $($1_TMP) $1 $($1_VERBOSE) $($1_SRC)

# handle / pinned-rule / extraction — identical to GRAFT_FETCH (built=yes for pins).
$(eval $1_HANDLE := $(if $(filter-out undefined,$(origin $1_SHA256)),$(if $(strip $($1_SHA256)),$(GRAFT_CACHE)/hash_files/$($1_SHA256),$($1_KEY)),$($1_KEY)))
$(eval $1_DISC := $(if $(filter-out undefined,$(origin $1_SHA256)),$(if $(strip $($1_SHA256)),,1),))
ifneq ($(filter-out undefined,$(origin $1_SHA256)),)
ifneq ($(strip $($1_SHA256)),)
$($1_HANDLE): $($1_KEY)
	@sh $(GRAFT_SH) verify $($1_KEY) $($1_SHA256) $1 built
endif
endif
$($1_TGT): $($1_HANDLE) $(if $($1_DISC),GRAFT_FORCE) | $($1_DIR) $($1_KEY)
	@sh $(GRAFT_SH) extract $($1_KEY) $($1_DIR) tar '$($1_DISC)' $1
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
