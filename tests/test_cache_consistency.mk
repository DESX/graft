# Test: changing any cache input re-resolves cleanly WITHOUT `make clean`. Each
# distinct input (version/commit, or expected SHA) gets its own cache entry and
# install dir; old ones are left intact; switching back reuses them. Guards against
# the cache or build tree drifting into a polluted/unexpected state on input changes.
# (URL-in-key and URL-change re-fetch are covered by test_cache_key/test_fetch_file.)
b := build_test_cache_consistency
GRAFT_CACHE := .cache_test_cache_consistency

include ../graft.mk

VER     ?= 3.0.2
MINIZ_TGT     := miniz.h
MINIZ_COMMIT  := $(VER)
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# 1. version 3.0.2 → one entry + its dir.
	@$(MAKE) -s -f test_cache_consistency.mk VER=3.0.2 $b/miniz-3.0.2/miniz.h
	@test -f $b/miniz-3.0.2/miniz.h || (echo "ERROR: 3.0.2 not built" && exit 1)
	@N=$$(ls $(GRAFT_CACHE) | grep -cE '^[0-9a-f]{12}_[0-9a-f]{12}$$'); \
	  test "$$N" = 1 || (echo "ERROR: expected 1 cache entry, have $$N" && exit 1)
	@echo "  build 3.0.2: OK"

	@# 2. change version to 2.1.0 (no make clean): fresh entry + dir, old kept.
	@$(MAKE) -s -f test_cache_consistency.mk VER=2.1.0 $b/miniz-2.1.0/miniz.h
	@test -f $b/miniz-2.1.0/miniz.h && test -d $b/miniz-3.0.2 \
	  || (echo "ERROR: version change clobbered the old dir" && exit 1)
	@N=$$(ls $(GRAFT_CACHE) | grep -cE '^[0-9a-f]{12}_[0-9a-f]{12}$$'); \
	  test "$$N" = 2 || (echo "ERROR: expected 2 entries after bump, have $$N" && exit 1)
	@echo "  change version (no clean): fresh entry, old kept: OK"

	@# 3. switch back to 3.0.2 (no make clean): reuse, no new entry/download.
	@$(MAKE) -s -f test_cache_consistency.mk VER=3.0.2 $b/miniz-3.0.2/miniz.h
	@N=$$(ls $(GRAFT_CACHE) | grep -cE '^[0-9a-f]{12}_[0-9a-f]{12}$$'); \
	  test "$$N" = 2 || (echo "ERROR: switch-back re-downloaded (entries now $$N)" && exit 1)
	@echo "  switch back: reused, no re-download: OK"

	@# 4. change the expected SHA at the same version (discover then pin): a distinct
	@#    key, so it re-fetches+verifies into its own entry instead of blind reuse.
	@H=$$($(MAKE) -s -f test_cache_consistency.mk VER=3.0.2 MINIZ_SHA256= $b/miniz-3.0.2/miniz.h 2>&1 >/dev/null | sed -n 's/.*MINIZ_SHA256 := //p'); \
	  test -n "$$H" || (echo "ERROR: discovery printed no hash" && exit 1); \
	  $(MAKE) -s -f test_cache_consistency.mk VER=3.0.2 MINIZ_SHA256=$$H $b/miniz-3.0.2/miniz.h
	@N=$$(ls $(GRAFT_CACHE) | grep -cE '^[0-9a-f]{12}_[0-9a-f]{12}$$'); \
	  test "$$N" = 3 || (echo "ERROR: pinning a SHA did not re-key (entries $$N)" && exit 1)
	@echo "  change SHA (no clean): distinct entry, re-verified: OK"
	@echo "Cache consistency (no make clean) test: OK"
