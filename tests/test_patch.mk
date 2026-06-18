# Test: PATCH application
b := build_test_patch
DL := .cache_test_patch

include ../graft.mk

# Create test patch file - adds a comment to the top of miniz.h
# Note: patch -p2 strips 2 path components, so old/miniz/file becomes file
PATCH_CONTENT := --- old/miniz/miniz.h\n+++ new/miniz/miniz.h\n@@ -1,3 +1,4 @@\n+/* PATCHED BY GRAFT TEST */\n /* miniz.c 3.0.0 - public domain deflate/inflate, zlib-subset, ZIP reading/writing/appending, PNG writing\n    See "unlicense" statement at the end of this file.\n    Rich Geldreich <richgel99@gmail.com>, last updated Oct. 13, 2013\n

# Use a small repo and apply a patch
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_TAR     := $(DL)/miniz_3.0.2.tar.gz
MINIZ_TMP     := /tmp/graft_test_patch_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
MINIZ_PATCH   := test_patch.patch
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(DL) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

# Create patch file before running
$(MINIZ_PATCH):
	@printf '%b' '$(PATCH_CONTENT)' > $@

.PHONY: test
test: $(MINIZ_PATCH) $(MINIZ_TGT)
	@# Verify patch was applied
	@grep -q "PATCHED BY GRAFT TEST" $(MINIZ_DIR)/miniz.h || (echo "ERROR: patch not applied" && exit 1)
	@echo "Patch test: OK"
	@rm -f $(MINIZ_PATCH)
