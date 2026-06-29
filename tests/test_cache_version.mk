# Test: bumping the pinned version re-fetches into a FRESH version-stamped dir and
# cache file, leaving the old ones in place (so switching back reuses them). No
# DIR/TAR/TMP are set — all default, and DIR + TAR embed the version token. This
# fails if DIR is unversioned (new source re-extracted over the old tree) or if the
# cache filename is unversioned (stale archive reused).
b := build_test_cache_version
GRAFT_CACHE := .cache_test_cache_version

include ../graft.mk

# MINIZ_VER drives the pinned commit; overridden per sub-make below.
MINIZ_VER     ?= 3.0.2
MINIZ_TGT     := miniz.h
MINIZ_COMMIT  := $(MINIZ_VER)
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# ── Build 2.1.0; it lands in its own version-stamped dir ──
	@$(MAKE) -s -f test_cache_version.mk MINIZ_VER=2.1.0 $b/miniz-2.1.0/miniz.h
	@test -f $b/miniz-2.1.0/miniz.h || (echo "ERROR: 2.1.0 not built into $b/miniz-2.1.0" && exit 1)
	@A=$$(cksum $b/miniz-2.1.0/miniz.h | cut -d' ' -f1); echo "$$A" > $b/.a
	@echo "  build 2.1.0 -> $b/miniz-2.1.0: OK"

	@# ── Bump to 3.0.2; fresh dir, old dir untouched, content differs ──
	@$(MAKE) -s -f test_cache_version.mk MINIZ_VER=3.0.2 $b/miniz-3.0.2/miniz.h
	@test -f $b/miniz-3.0.2/miniz.h || (echo "ERROR: 3.0.2 not built into $b/miniz-3.0.2" && exit 1)
	@test -d $b/miniz-2.1.0 || (echo "ERROR: old version dir was clobbered by the bump" && exit 1)
	@B=$$(cksum $b/miniz-3.0.2/miniz.h | cut -d' ' -f1); A=$$(cat $b/.a); \
	  test "$$A" != "$$B" || (echo "ERROR: miniz.h unchanged after bump" && exit 1)
	@echo "  bump to 3.0.2 -> $b/miniz-3.0.2 (old dir kept): OK"

	@# ── Both versioned dirs AND cache entries coexist (switching back reuses them) ──
	@test -d $b/miniz-2.1.0 && test -d $b/miniz-3.0.2 || (echo "ERROR: version dirs do not coexist" && exit 1)
	@# Two distinct content-addressed cache files (one per version key).
	@N=$$(ls $(GRAFT_CACHE)/hash_files | grep -cE '^[0-9a-f]{64}$$'); \
	  test "$$N" -ge 2 || (echo "ERROR: cache entries do not coexist (have $$N)" && exit 1)
	@echo "Versioned dir + cache test: OK"
