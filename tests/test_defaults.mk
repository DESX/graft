# Test: TAR and TMP default when omitted (mechanical-path defaults).
b := build_test_defaults
GRAFT_CACHE := .cache_test_defaults

include ../graft.mk

# A git dep with neither _TAR nor _TMP set — GRAFT_FETCH must default both.
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: $(MINIZ_TGT)
	@# Extraction still works with no TAR/TMP supplied.
	@test -f $(MINIZ_DIR)/miniz.h || (echo "ERROR: miniz.h not found" && exit 1)
	@# GRAFT_FETCH populated MINIZ_TAR with the default $(GRAFT_CACHE)/<name>-<ver>.tar.gz,
	@# where <ver> is the git commit so a bump re-fetches instead of reusing it.
	@test "$(MINIZ_TAR)" = "$(GRAFT_CACHE)/miniz-3.0.2.tar.gz" || (echo "ERROR: TAR default wrong: '$(MINIZ_TAR)'" && exit 1)
	@test -f $(GRAFT_CACHE)/miniz-3.0.2.tar.gz || (echo "ERROR: default TAR cache not created" && exit 1)
	@# ... and MINIZ_TMP with $b/graft-tmp/<name> (per-project scratch, removed by clean).
	@test "$(MINIZ_TMP)" = "$b/graft-tmp/miniz" || (echo "ERROR: TMP default wrong: '$(MINIZ_TMP)'" && exit 1)
	@echo "Defaults test: OK"
