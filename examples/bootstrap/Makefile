# Graft self-bootstrapping example.
#
# This Makefile keeps NO copy of graft in the repo, no graft.mk, no pidwatch.c.
# The rule below clones graft on first use and then includes it, so `make` on a
# fresh checkout Just Works with no separate setup step.
#
# Pin a release tag, not a branch. graft.mk is part of your build contract;
# tracking `main` lets an upstream change alter your build between checkouts.
# Graft publishes immutable vX.Y.Z tags; pinning one is reproducible and keeps
# the bootstrap to a single shallow clone (`git clone -b` accepts a tag name).
#
# Graft is cloned into a version-stamped dir, graft-$(GRAFT_VER), so bumping
# GRAFT_VER clones the new copy alongside the old. Updating never needs a delete.
#
# To try it against a local graft checkout instead of GitHub:
#   make GRAFT_URL=../.. GRAFT_VER=main

b           := build
GRAFT_CACHE ?= .cache

# Keep `all` the default goal: the bootstrap clone rule below is the first target
# in the file and would otherwise be built (and nothing else) by a bare `make`.
.DEFAULT_GOAL := all

GRAFT_URL ?= https://github.com/DESX/graft.git
GRAFT_VER ?= v1.9.0
$(GRAFT_CACHE)/graft-$(GRAFT_VER)/graft.mk:; @git clone -q --depth=1 -b $(GRAFT_VER) $(GRAFT_URL) $(dir $@)
include $(GRAFT_CACHE)/graft-$(GRAFT_VER)/graft.mk

# A small header-only dependency, fetched via graft to prove bootstrap worked.
# TAR and TMP are left to graft's defaults ($(GRAFT_CACHE)/miniz-3.0.2.tar.gz and
# $b/graft-tmp/miniz); bumping MINIZ_COMMIT alone re-fetches the new version.
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := miniz.h
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

all: $(MINIZ_TGT)
	@echo "Bootstrapped graft ($(GRAFT_VER)) and fetched miniz into $(MINIZ_DIR)"

clean:
	rm -rf $b $(GRAFT_CACHE)
