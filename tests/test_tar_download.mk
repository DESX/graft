# Test: TAR_URL download and extraction
b := build_test_tar_download
GRAFT_CACHE := .cache_test_tar_download

include ../graft.mk

# Use a small, stable tarball (jq release - ~1MB)
JQ_DIR     := $b/jq
JQ_TGT     := $(JQ_DIR)/README.md
JQ_TAR     := $(GRAFT_CACHE)/jq-1.7.1.tar.gz
JQ_TAR_URL := https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-1.7.1.tar.gz
$(eval $(call GRAFT_FETCH,JQ))

DIRS := $b $(GRAFT_CACHE) $(JQ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: $(JQ_TGT)
	@# Verify extraction
	@test -f $(JQ_DIR)/README.md || (echo "ERROR: README.md not found" && exit 1)
	@test -f $(JQ_DIR)/configure.ac || (echo "ERROR: configure.ac not found" && exit 1)
	@# Verify cache exists
	@test -f $(JQ_TAR) || (echo "ERROR: cache not created" && exit 1)
	@echo "TAR download test: OK"
