# Test: Caching behavior
b := build_test_caching
GRAFT_CACHE := .cache_test_caching

include ../graft.mk

MINIZ_DIR     := $b/miniz
MINIZ_TGT     := miniz.h
MINIZ_TMP     := /tmp/graft_test_caching_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test:
	@# First build - creates cache
	@$(MAKE) -f test_caching.mk $(MINIZ_TGT)
	@test -f $(MINIZ_KEY) || (echo "ERROR: keyfile not created" && exit 1)
	@# The content file is named by its hash; its mtime must not change on a rebuild
	@# (a re-download would replace it).
	@CF=$(GRAFT_CACHE)/hash_files/$$(head -1 $(MINIZ_KEY)) && \
	 CACHE_TIME=$$(stat -c %Y $$CF) && \
	 sleep 1 && \
	 rm -rf $(MINIZ_DIR) && \
	 $(MAKE) -f test_caching.mk $(MINIZ_TGT) && \
	 NEW_TIME=$$(stat -c %Y $$CF) && \
	 test "$$CACHE_TIME" = "$$NEW_TIME" || (echo "ERROR: cache was re-downloaded" && exit 1)
	@echo "Caching test: OK"
