# Test: GRAFT_FETCH's COMMIT accepts both a tag and a raw commit SHA.
#
# `git clone --branch <sha>` rejects SHAs, so this fails if graft still clones
# that way. We fetch miniz two ways — by the tag 2.1.0 and by the exact commit
# that tag points at — and assert the extracted header is byte-identical, which
# proves the SHA path resolves to the same source as the tag path.
b := build_test_git_ref
DL := .cache_test_git_ref

include ../graft.mk

# Tag 2.1.0 and its commit SHA are the same revision of miniz.
GITREF_SHA := a4264837ae37384b1d7a205a6732db322f0f3769

# ── by tag ──
TAGGED_DIR     := $b/tagged
TAGGED_TGT     := $(TAGGED_DIR)/miniz.h
TAGGED_COMMIT  := 2.1.0
TAGGED_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,TAGGED))

# ── by raw commit SHA ──
PINNED_DIR     := $b/pinned
PINNED_TGT     := $(PINNED_DIR)/miniz.h
PINNED_COMMIT  := $(GITREF_SHA)
PINNED_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,PINNED))

DIRS := $b $(DL) $(TAGGED_DIR) $(PINNED_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: $(TAGGED_TGT) $(PINNED_TGT)
	@# Both fetches must have produced the header.
	@test -f $(TAGGED_TGT) || (echo "ERROR: tag fetch produced no miniz.h" && exit 1)
	@echo "  fetch by tag (2.1.0): OK"
	@test -f $(PINNED_TGT) || (echo "ERROR: SHA fetch produced no miniz.h" && exit 1)
	@echo "  fetch by commit SHA: OK"
	@# Tag and its commit SHA must yield byte-identical source.
	@cmp -s $(TAGGED_TGT) $(PINNED_TGT) \
	  || (echo "ERROR: tag and SHA fetched different content" && exit 1)
	@echo "Git ref (tag + commit SHA) test: OK"
