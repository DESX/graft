# Test: TAR and TMP default when omitted (mechanical-path defaults).
b := build_test_defaults
DL := .cache_test_defaults

include ../graft.mk

# A git dep with neither _TAR nor _TMP set — FETCH must default both.
MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call FETCH,MINIZ))

DIRS := $b $(DL) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call MK_DIR,$V)))

.PHONY: test
test: $(MINIZ_TGT)
	@# Extraction still works with no TAR/TMP supplied.
	@test -f $(MINIZ_DIR)/miniz.h || (echo "ERROR: miniz.h not found" && exit 1)
	@# FETCH populated MINIZ_TAR with the default $(DL)/<name>.tar.gz ...
	@test "$(MINIZ_TAR)" = "$(DL)/miniz.tar.gz" || (echo "ERROR: TAR default wrong: '$(MINIZ_TAR)'" && exit 1)
	@test -f $(DL)/miniz.tar.gz || (echo "ERROR: default TAR cache not created" && exit 1)
	@# ... and MINIZ_TMP with /tmp/graft_<name>.
	@test "$(MINIZ_TMP)" = "/tmp/graft_miniz" || (echo "ERROR: TMP default wrong: '$(MINIZ_TMP)'" && exit 1)
	@echo "Defaults test: OK"
