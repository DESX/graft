# Test: ZIP_URL download and extraction (the unzip path of GRAFT_FETCH).
#
# Skips gracefully when `unzip` is not installed — graft only needs it for zip
# sources, so its absence is not a graft failure. Unlike the tar path, zip
# extraction does NOT strip a leading directory; files land exactly as the
# archive stores them. The miniz release zip is flat (miniz.h at the top), so
# the target sits directly under MINIZ_DIR.
b := build_test_zip_download
GRAFT_CACHE := .cache_test_zip_download

include ../graft.mk

MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_TAR     := $(GRAFT_CACHE)/miniz-3.0.2.zip
MINIZ_ZIP_URL := https://github.com/richgel999/miniz/releases/download/3.0.2/miniz-3.0.2.zip
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

# Gate the whole test at parse time: with no unzip, never build the zip target.
HAVE_UNZIP := $(shell command -v unzip 2>/dev/null)

.PHONY: test
ifeq ($(HAVE_UNZIP),)
test:
	@echo "  unzip not installed — skipping zip test"
else
test: $(MINIZ_TGT)
	@# Verify extraction landed the flat layout (zip path does not strip a dir).
	@test -f $(MINIZ_DIR)/miniz.h || (echo "ERROR: miniz.h not found" && exit 1)
	@test -f $(MINIZ_DIR)/miniz.c || (echo "ERROR: miniz.c not found" && exit 1)
	@# Verify the cached zip exists.
	@test -f $(MINIZ_TAR) || (echo "ERROR: cache not created" && exit 1)
	@echo "Zip download test: OK"
endif
