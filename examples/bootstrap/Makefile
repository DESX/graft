# Graft self-bootstrapping example.
#
# This Makefile vendors NOTHING — no graft.mk, no pidwatch.c in the repo. The
# one-line rule below clones graft on first use and then includes it, so `make`
# on a fresh checkout Just Works with no separate setup step.
#
# Pin a release tag, not a branch. graft.mk is part of your build contract;
# tracking `main` lets an upstream change alter your build between checkouts.
# Graft publishes immutable vX.Y.Z tags — pinning one is reproducible and keeps
# the bootstrap to a single shallow clone (`git clone -b` accepts a tag name).
#
# To try it against a local graft checkout instead of GitHub:
#   make GRAFT_URL=../.. GRAFT_REV=main

b  := build
DL := .cache

GRAFT_URL ?= https://github.com/DESX/graft.git
GRAFT_REV ?= v1.2.0
$(DL)/graft/graft.mk:; @git clone -q --depth=1 -b $(GRAFT_REV) $(GRAFT_URL) $(dir $@)
include $(DL)/graft/graft.mk

# A small header-only dependency, fetched via graft to prove bootstrap worked.
# TAR and TMP are left to graft's defaults ($(DL)/miniz-3.0.2.tar.gz and
# /tmp/graft_miniz) — bumping MINIZ_COMMIT alone re-fetches the new version.
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(DL) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

all: $(MINIZ_TGT)
	@echo "Bootstrapped graft ($(GRAFT_REV)) and fetched miniz into $(MINIZ_DIR)"

clean:
	rm -rf $b $(DL)
