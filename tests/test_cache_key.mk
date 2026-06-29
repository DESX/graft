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
	@# The keyfile lives under key_files/ and is named by a 12-hex keyhash.
	@echo "$(A_KEY)" | grep -qE '/key_files/[0-9a-f]{12}$$' || (echo "ERROR: key path wrong: '$(A_KEY)'" && exit 1)
	@# Same commit + different URL => different keyhash (no collision).
	@test "$(A_KEY)" != "$(B_KEY)" || (echo "ERROR: same commit on different repos collided in cache" && exit 1)
	@echo "  url folded into key (no tag/commit collision): OK"
	@# The keyfile's first line is the full sha256 of the content, which is stored in
	@# hash_files/ named by exactly that hash (pure content-addressing).
	@fh=$$(head -1 $(A_KEY)); \
	  echo "$$fh" | grep -qE '^[0-9a-f]{64}$$' || (echo "ERROR: keyfile line 1 not a full sha256: '$$fh'" && exit 1); \
	  test -f $(GRAFT_CACHE)/hash_files/$$fh || (echo "ERROR: content file hash_files/$$fh missing" && exit 1)
	@echo "  content stored as hash_files/<full-sha256>: OK"
	@echo "Cache key test: OK"
