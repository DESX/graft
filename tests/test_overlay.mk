# Test: GRAFT_OVERLAY symlinks
b := build_test_overlay
DL := .cache_test_overlay
OVERLAY_DIR := overlay_test

include ../graft.mk

# Use a small repo with overlay
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_TAR     := $(DL)/miniz_3.0.2.tar.gz
MINIZ_TMP     := /tmp/graft_test_overlay_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
MINIZ_OVERLAY := $(OVERLAY_DIR)
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(DL) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

# Create overlay directory with a replacement file
$(OVERLAY_DIR)/custom.txt:
	@mkdir -p $(OVERLAY_DIR)
	@echo "GRAFT_OVERLAY CONTENT" > $@

.PHONY: test
test: $(OVERLAY_DIR)/custom.txt $(MINIZ_TGT)
	@# Verify overlay file exists as symlink
	@test -L $(MINIZ_DIR)/custom.txt || (echo "ERROR: overlay not symlinked" && exit 1)
	@# Verify content
	@grep -q "GRAFT_OVERLAY CONTENT" $(MINIZ_DIR)/custom.txt || (echo "ERROR: overlay content wrong" && exit 1)
	@echo "Overlay test: OK"
	@rm -rf $(OVERLAY_DIR)
