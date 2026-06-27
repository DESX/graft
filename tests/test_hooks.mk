# Test: the PRE_UNPACK / POST_UNPACK hooks documented under "Build hooks".
#
# PRE_UNPACK runs in the clone scratch dir (TMP) BEFORE the tree is archived, so
# its output is captured in the cached archive and survives a clean extraction.
# POST_UNPACK runs AFTER extraction into the install dir (DIR). This test proves
# both placements by leaving a marker from each and checking where it lands.
b := build_test_hooks
DL := .cache_test_hooks

include ../graft.mk

MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_TMP     := /tmp/graft_test_hooks_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
MINIZ_PRE_UNPACK   = echo pre  > $(MINIZ_TMP)/pre_marker.txt
MINIZ_POST_UNPACK  = echo post > $(abspath $(MINIZ_DIR))/post_marker.txt
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(DL) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: $(MINIZ_TGT)
	@# PRE_UNPACK output was archived into the cache, so it extracted into DIR.
	@test -f $(MINIZ_DIR)/pre_marker.txt \
	  || (echo "ERROR: PRE_UNPACK output not captured in the archive" && exit 1)
	@grep -q pre $(MINIZ_DIR)/pre_marker.txt || (echo "ERROR: PRE_UNPACK marker wrong" && exit 1)
	@echo "  PRE_UNPACK captured in cache + extracted: OK"
	@# POST_UNPACK ran after extraction, writing straight into DIR.
	@test -f $(MINIZ_DIR)/post_marker.txt \
	  || (echo "ERROR: POST_UNPACK did not run after extraction" && exit 1)
	@echo "  POST_UNPACK ran after extraction: OK"
	@echo "Hooks (PRE/POST_UNPACK) test: OK"
