# Test: bumping the version re-fetches and re-extracts (no stale cache).
#
# No NAME_TAR is set — the default must embed the version token, so two commits
# land in two cache files AND the install dir actually updates on a bump. This
# fails if NAME_TAR is unversioned (old tar reused) OR if NAME_TGT keeps TAR as
# an order-only prereq (new tar downloaded but never re-extracted).
b := build_test_cache_version
DL := .cache_test_cache_version

include ../graft.mk

# MINIZ_VER drives the pinned commit; overridden per sub-make below. No MINIZ_TAR
# and no MINIZ_TMP — both come from graft's defaults.
MINIZ_VER     ?= 3.0.2
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_COMMIT  := $(MINIZ_VER)
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(DL) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# ── Build 2.1.0, record what landed in the install dir ──
	@$(MAKE) -s -f test_cache_version.mk MINIZ_VER=2.1.0 $(MINIZ_TGT)
	@A=$$(cksum $(MINIZ_TGT) | cut -d' ' -f1); echo "$$A" > $b/.a
	@test -f $(DL)/miniz-2.1.0.tar.gz || (echo "ERROR: default tar not versioned (2.1.0)" && exit 1)
	@echo "  build 2.1.0: OK"

	@# ── Bump to 3.0.2; the extracted header must change ──
	@$(MAKE) -s -f test_cache_version.mk MINIZ_VER=3.0.2 $(MINIZ_TGT)
	@B=$$(cksum $(MINIZ_TGT) | cut -d' ' -f1); A=$$(cat $b/.a); \
	  test "$$A" != "$$B" || (echo "ERROR: miniz.h unchanged after bump — stale cache!" && exit 1)
	@test -f $(DL)/miniz-3.0.2.tar.gz || (echo "ERROR: default tar not versioned (3.0.2)" && exit 1)
	@echo "  bump to 3.0.2 re-extracted: OK"

	@# ── Both versioned archives coexist (switching back reuses the cache) ──
	@test -f $(DL)/miniz-2.1.0.tar.gz && test -f $(DL)/miniz-3.0.2.tar.gz \
	  || (echo "ERROR: versioned tars do not coexist" && exit 1)
	@echo "Cache versioning test: OK"
