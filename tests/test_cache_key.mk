# Test: the content-addressed cache key. A cache file is named <keyhash>_<filehash>,
# where keyhash = sha256(commit/version + source URL)[:12]. Folding the URL into the
# key means the SAME tag/commit on two different repos never collides (the old
# commit-only scheme did), and the filehash records the stored content.
b := build_test_cache_key
GRAFT_CACHE := .cache_test_cache_key

include ../graft.mk

# Real dep (fetched below).
A_TGT     := miniz.h
A_COMMIT  := 3.0.2
A_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,A))

# Same commit string, different URL — never fetched, only its key is compared.
B_TGT     := miniz.h
B_COMMIT  := 3.0.2
B_GIT_URL := https://github.com/someone/miniz-fork.git
$(eval $(call GRAFT_FETCH,B))

DIRS := $b $(GRAFT_CACHE) $(A_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: $(A_TGT)
	@# The cache handle is an opaque 12-hex key under the cache dir.
	@echo "$(A_TAR)" | grep -qE '/[0-9a-f]{12}$$' || (echo "ERROR: cache handle not a keyhash: '$(A_TAR)'" && exit 1)
	@# Same commit + different URL => different key (no collision).
	@test "$(A_TAR)" != "$(B_TAR)" || (echo "ERROR: same commit on different repos collided in cache" && exit 1)
	@echo "  url folded into key (no tag/commit collision): OK"
	@# The stored file is content-addressed <keyhash>_<filehash>, reached via the handle.
	@test -L $(A_TAR) && test -f $(A_TAR) || (echo "ERROR: cache handle missing or broken" && exit 1)
	@readlink $(A_TAR) | grep -qE '^[0-9a-f]{12}_[0-9a-f]{12}$$' \
	  || (echo "ERROR: cache file not content-addressed: '$$(readlink $(A_TAR))'" && exit 1)
	@echo "  content-addressed <keyhash>_<filehash>: OK"
	@echo "Cache key test: OK"
