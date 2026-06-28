# Test: `make name_patch` tolerates an odd step ordering — specifically, the
# download cache being cleaned between the build and the patch-generation step.
#
# The documented flow is: build, edit the install dir in place, then
# `make name_patch` to capture the edit. name_patch rebuilds the pristine tree
# from the cached archive to diff against. If that archive was removed in the
# meantime, name_patch must re-fetch it WITHOUT re-extracting over — and thereby
# silently wiping — the in-place edit it is supposed to capture. Before the fix,
# this produced an empty patch and lost the edit.
b := build_test_patch_robust
GRAFT_CACHE := .cache_test_patch_robust

include ../graft.mk

MINIZ_DIR     := $b/miniz
MINIZ_TGT     := $(MINIZ_DIR)/miniz.h
MINIZ_TMP     := /tmp/graft_test_patch_robust_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
MINIZ_PATCH   := $b/patches/miniz.patch
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

EDIT := EDIT SURVIVES CACHE WIPE

.PHONY: test
test: | $b
	@# ── Build, then edit the install dir in place ──
	@$(MAKE) -s -f test_patch_robust.mk $(MINIZ_TGT)
	@sed -i '1i /* $(EDIT) */' $(MINIZ_DIR)/miniz.h
	@echo "  build + in-place edit: OK"

	@# ── Clean the download cache, THEN generate the patch ──
	@rm -rf $(GRAFT_CACHE)
	@$(MAKE) -s -f test_patch_robust.mk miniz_patch
	@# The edit must survive in the install dir (not re-extracted away)...
	@grep -q "$(EDIT)" $(MINIZ_DIR)/miniz.h \
	  || (echo "ERROR: in-place edit wiped by patch generation" && exit 1)
	@# ...and be captured in the generated patch (not an empty diff).
	@test -s $(MINIZ_PATCH) || (echo "ERROR: empty patch generated" && exit 1)
	@grep -q "$(EDIT)" $(MINIZ_PATCH) \
	  || (echo "ERROR: edit not captured in patch" && exit 1)
	@echo "  generate patch after cache wipe: OK"

	@# ── A clean rebuild re-applies the captured patch ──
	@rm -rf $(MINIZ_DIR)
	@$(MAKE) -s -f test_patch_robust.mk $(MINIZ_TGT)
	@grep -q "$(EDIT)" $(MINIZ_DIR)/miniz.h \
	  || (echo "ERROR: patch not re-applied on clean rebuild" && exit 1)
	@echo "Patch robustness (cache-wipe) test: OK"
