# Test: GRAFT_BUILD — the two-stage companion to GRAFT_FETCH. Stage 1 fetches a
# source (content-addressed); stage 2 unpacks it, runs a command, and repacks the
# result as a separate cache entry keyed by source + command. Uses a deterministic
# command so the build is reproducible (and thus pinnable).
b := build_test_build_macro
GRAFT_CACHE := .cache_test_build_macro

include ../graft.mk

# Stage 1: fetch the source.
SRC_TGT     := miniz.h
SRC_COMMIT  := 3.0.2
SRC_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,SRC))

# Stage 2: build it.
VARIANT ?= one
BLD_SRC := SRC
BLD_TGT := built.txt
BLD_CMD := echo built-$(VARIANT) > built.txt
$(eval $(call GRAFT_BUILD,BLD))

DIRS := $b $(GRAFT_CACHE) $(SRC_DIR) $(BLD_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# Build variant one; output lands in the build dir, alongside the source files.
	@$(MAKE) -s -f test_build_macro.mk VARIANT=one $(BLD_TGT)
	@grep -q built-one $(BLD_DIR)/built.txt || (echo "ERROR: build command did not run" && exit 1)
	@test -f $(BLD_DIR)/miniz.h || (echo "ERROR: build output is missing the source it was built from" && exit 1)
	@echo "  build from a fetched source: OK"
	@# Two cache entries now exist: the source, and the build.
	@N=$$(ls $(GRAFT_CACHE)/hash_files | grep -cE '^[0-9a-f]{64}$$'); \
	  test "$$N" = 2 || (echo "ERROR: expected source + build entries, have $$N" && exit 1)
	@echo "  source and build are separate cache entries: OK"
	@# Change the build command (same source): a new build entry, source reused.
	@$(MAKE) -s -f test_build_macro.mk VARIANT=two $(BLD_TGT)
	@grep -q built-two $(BLD_DIR)/built.txt || (echo "ERROR: changing the command did not rebuild" && exit 1)
	@N=$$(ls $(GRAFT_CACHE)/hash_files | grep -cE '^[0-9a-f]{64}$$'); \
	  test "$$N" = 3 || (echo "ERROR: build-command change did not re-key (have $$N)" && exit 1)
	@echo "  change command: new build entry, source reused: OK"
	@echo "Build macro test: OK"
