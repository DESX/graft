# Test: EXTRA dependencies ordering
b := build_test_dependencies
GRAFT_CACHE := .cache_test_dependencies
LOG := $(b)/order.log

include ../graft.mk

# First dependency (will be built first)
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_TAR     := $(GRAFT_CACHE)/miniz_3.0.2.tar.gz
MINIZ_TMP     := /tmp/graft_test_deps_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
MINIZ_POST_UNPACK = echo "MINIZ" >> $(abspath $(LOG))
$(eval $(call GRAFT_FETCH,MINIZ))

# Second dependency depends on first via EXTRA
TINYEXPR_DIR     := $b/tinyexpr
TINYEXPR_TGT     := $(TINYEXPR_DIR)/tinyexpr.h
TINYEXPR_TAR     := $(GRAFT_CACHE)/tinyexpr_master.tar.gz
TINYEXPR_TMP     := /tmp/graft_test_deps_tinyexpr
TINYEXPR_COMMIT  := master
TINYEXPR_GIT_URL := https://github.com/codeplea/tinyexpr.git
TINYEXPR_POST_UNPACK = echo "TINYEXPR" >> $(abspath $(LOG))
TINYEXPR_EXTRA   := $(MINIZ_TGT)
$(eval $(call GRAFT_FETCH,TINYEXPR))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR) $(TINYEXPR_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $(b)
	@rm -f $(LOG)
	@touch $(LOG)
	@$(MAKE) -f test_dependencies.mk $(TINYEXPR_TGT)
	@# Verify MINIZ was built before TINYEXPR
	@head -1 $(LOG) | grep -q "MINIZ" || (echo "ERROR: MINIZ should be first" && exit 1)
	@tail -1 $(LOG) | grep -q "TINYEXPR" || (echo "ERROR: TINYEXPR should be second" && exit 1)
	@echo "Dependencies test: OK"
