# Graft self-bootstrapping example.
#
# This Makefile vendors NOTHING — no graft.mk, no pidwatch.c in the repo. The
# rule below clones graft on first use and then includes it, so `make` on a
# fresh checkout Just Works with no separate setup step.
#
# Pin a specific commit, not a branch. graft.mk is part of your build contract;
# tracking `main` lets an upstream change alter your build between checkouts.
# A pinned SHA makes builds reproducible and updates a one-line, reviewable diff.
#
# `git clone -b` only accepts branches and tags, so to pin an arbitrary commit
# we shallow-fetch the SHA and check out FETCH_HEAD (GitHub allows fetching a
# SHA directly).
#
# To try it against a local graft checkout instead of GitHub:
#   make GRAFT_URL=../.. GRAFT_REV=$(git -C ../.. rev-parse HEAD)

b  := build
DL := .cache

GRAFT_URL ?= https://github.com/DESX/graft.git
# Pinned commit — bump deliberately (keep the SHA on its own line; a trailing
# inline comment would leave whitespace in the value).
GRAFT_REV ?= 65dd2d0dd4fedde5a2cab1f381287ae02ec0eabb
$(DL)/graft/graft.mk:
	@mkdir -p $(dir $@)
	@git -C $(dir $@) init -q
	@git -C $(dir $@) fetch -q --depth=1 $(GRAFT_URL) $(GRAFT_REV)
	@git -C $(dir $@) checkout -q FETCH_HEAD
include $(DL)/graft/graft.mk

# A small header-only dependency, fetched via graft to prove bootstrap worked.
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_TAR     := $(DL)/miniz-3.0.2.tar.gz
MINIZ_TMP     := /tmp/graft_example_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call FETCH,MINIZ))

DIRS := $b $(DL) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call MK_DIR,$V)))

all: $(MINIZ_TGT)
	@echo "Bootstrapped graft ($(GRAFT_REV)) and fetched miniz into $(MINIZ_DIR)"

clean:
	rm -rf $b $(DL)
