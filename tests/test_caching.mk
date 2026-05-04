# Test: Caching behavior
b := build_test_caching
DL := .cache_test_caching

include ../graft.mk

MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_TAR     := $(DL)/miniz_3.0.2.tar.gz
MINIZ_TMP     := /tmp/graft_test_caching_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call FETCH,MINIZ))

DIRS := $b $(DL) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call MK_DIR,$V)))

.PHONY: test
test:
	@# First build - creates cache
	@$(MAKE) -f test_caching.mk $(MINIZ_TGT)
	@test -f $(MINIZ_TAR) || (echo "ERROR: cache not created" && exit 1)
	@# Record cache timestamp
	@CACHE_TIME=$$(stat -c %Y $(MINIZ_TAR)) && \
	 sleep 1 && \
	 rm -rf $(MINIZ_DIR) && \
	 $(MAKE) -f test_caching.mk $(MINIZ_TGT) && \
	 NEW_TIME=$$(stat -c %Y $(MINIZ_TAR)) && \
	 test "$$CACHE_TIME" = "$$NEW_TIME" || (echo "ERROR: cache was re-downloaded" && exit 1)
	@echo "Caching test: OK"
