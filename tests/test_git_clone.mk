# Test: GIT_URL clone and cache
b := build_test_git_clone
GRAFT_CACHE := .cache_test_git_clone

include ../graft.mk

# Use a small, stable repo
MINIZ_DIR    := $b/miniz
MINIZ_TGT    := $(MINIZ_DIR)/miniz.h
MINIZ_TAR    := $(GRAFT_CACHE)/miniz_3.0.2.tar.gz
MINIZ_TMP    := /tmp/graft_test_miniz
MINIZ_COMMIT := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: $(MINIZ_TGT)
	@# Verify extraction
	@test -f $(MINIZ_DIR)/miniz.h || (echo "ERROR: miniz.h not found" && exit 1)
	@test -f $(MINIZ_DIR)/LICENSE || (echo "ERROR: LICENSE not found" && exit 1)
	@# Verify cache created
	@test -f $(MINIZ_TAR) || (echo "ERROR: cache not created" && exit 1)
	@# Verify .git not in cache
	@test ! -d $(MINIZ_DIR)/.git || (echo "ERROR: .git should be excluded" && exit 1)
	@echo "Git clone test: OK"
