# Test: the build command (PRE_UNPACK) is part of the cache key, so changing HOW a
# dep is built re-fetches into a fresh entry instead of serving the stale build. Also
# checks the keyfile records built=yes, and that a pinned mismatch on a built dep uses
# the build-aware error message.
#
# Uses a deterministic PRE_UNPACK (echo a marker) so the archive is reproducible.
b := build_test_build_key
GRAFT_CACHE := .cache_test_build_key

include ../graft.mk

VARIANT ?= one
MINIZ_TGT     := marker.txt
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
MINIZ_PRE_UNPACK = echo built-$(VARIANT) > $(MINIZ_TMP)/marker.txt
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# 1. Build variant "one"; the marker is part of the archived content.
	@$(MAKE) -s -f test_build_key.mk VARIANT=one $b/miniz-3.0.2/marker.txt
	@grep -q built-one $b/miniz-3.0.2/marker.txt || (echo "ERROR: variant one not built" && exit 1)
	@grep -q built=yes $(GRAFT_CACHE)/key_files/* || (echo "ERROR: keyfile missing built=yes" && exit 1)
	@cat $(GRAFT_CACHE)/key_files/* | head -1 > $b/.h1
	@echo "  variant one built; keyfile records built=yes: OK"

	@# 2. Change the build command (same source) — fresh key/entry, no stale reuse.
	@$(MAKE) -s -f test_build_key.mk VARIANT=two $b/miniz-3.0.2/marker.txt
	@grep -q built-two $b/miniz-3.0.2/marker.txt || (echo "ERROR: PRE_UNPACK change served a stale build" && exit 1)
	@N=$$(ls $(GRAFT_CACHE)/hash_files | grep -cE '^[0-9a-f]{64}$$'); \
	  test "$$N" = 2 || (echo "ERROR: build-command change did not re-key (entries $$N)" && exit 1)
	@echo "  change build command (no clean): fresh entry, no stale build: OK"

	@# 3. Pin variant one's hash but build variant two -> build-aware mismatch message.
	@H1=$$(cat $b/.h1); out=$$($(MAKE) -s -f test_build_key.mk VARIANT=two MINIZ_SHA256=$$H1 $b/miniz-3.0.2/marker.txt 2>&1); \
	  echo "$$out" | grep -q 'built output differs' \
	  || (echo "ERROR: expected build-aware message, got: $$out" && exit 1)
	@echo "  pinned mismatch on a built dep uses the build-aware message: OK"
	@echo "Build-command key test: OK"
