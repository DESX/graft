# Test: the cache dir is relocatable. Copy or move GRAFT_CACHE (to another machine,
# a shared drive, a different path) and a clean rebuild works from it alone, with
# no network. This proves GRAFT_CACHE is the only thing tying a build to the cache
# location and that cached archives carry no hard-coded absolute paths.
#
# Strategy: populate the cache online, move it to a different path, delete the
# build tree, then rebuild under a dead HTTP proxy so ANY network access fails
# fast. A successful rebuild therefore came entirely from the relocated cache.
b           := build_test_cache_relocatable
GRAFT_CACHE ?= .cache_test_cache_relocatable

include ../graft.mk

# One of each fetch mechanism: git (cache key = commit), tarball (key = URL hash),
# and a single file. All use graft's default cache paths under $(GRAFT_CACHE).
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := miniz.h
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

JQ_DIR     := $b/jq
JQ_TGT     := README.md
JQ_TAR_URL := https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-1.7.1.tar.gz
$(eval $(call GRAFT_FETCH,JQ))

HDR_TGT := $b/include/miniz.h
HDR_URL := https://raw.githubusercontent.com/richgel999/miniz/3.0.2/miniz.h
$(eval $(call GRAFT_FETCH_FILE,HDR))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR) $(JQ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

TARGETS := $(MINIZ_TGT) $(JQ_TGT) $(HDR_TGT)
MOVED   := $(GRAFT_CACHE)_moved
OFFLINE := https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 ALL_PROXY=http://127.0.0.1:9

.PHONY: test
test: | $b
	@# ── 1. Populate the cache online ──
	@$(MAKE) -s -f test_cache_relocatable.mk $(TARGETS)
	@echo "  populate cache (git + tar + file): OK"

	@# ── 2. Relocate the cache to a new path; wipe the build tree ──
	@rm -rf $(MOVED) && cp -r $(GRAFT_CACHE) $(MOVED) && rm -rf $(GRAFT_CACHE) $b
	@echo "  move $(GRAFT_CACHE) -> $(MOVED), clean build tree: OK"

	@# ── 3. Rebuild from the moved cache, pointing at it via the GRAFT_CACHE env
	@#       var (the makefile uses ?=, so the environment wins), network blocked ──
	@$(OFFLINE) GRAFT_CACHE=$(MOVED) $(MAKE) -s -f test_cache_relocatable.mk $(TARGETS) \
	  || { echo "ERROR: rebuild from relocated cache reached the network" && rm -rf $(MOVED) && exit 1; }
	@test -f $(MINIZ_DIR)/miniz.h || { echo "ERROR: git dep missing after relocation"  && rm -rf $(MOVED) && exit 1; }
	@test -f $(JQ_DIR)/README.md  || { echo "ERROR: tar dep missing after relocation"  && rm -rf $(MOVED) && exit 1; }
	@test -f $(HDR_TGT)           || { echo "ERROR: file dep missing after relocation" && rm -rf $(MOVED) && exit 1; }
	@rm -rf $(MOVED)
	@echo "Cache relocation (offline rebuild) test: OK"
