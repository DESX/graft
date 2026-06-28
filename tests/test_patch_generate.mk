# Test: NAME_PATCH may point at a file that does not exist yet. The build
# succeeds with no patch, you edit the extracted tree in place, `make name_patch`
# writes the diff, and a clean rebuild re-applies it.
b := build_test_patch_generate
GRAFT_CACHE := .cache_test_patch_generate

include ../graft.mk

MINIZ_DIR     := $b/miniz
MINIZ_TGT     := miniz.h
MINIZ_TMP     := /tmp/graft_test_patch_generate_miniz
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
MINIZ_PATCH   := $b/patches/miniz.patch
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# ── Build succeeds even though MINIZ_PATCH does not exist yet ──
	@test ! -f $(MINIZ_PATCH) || (echo "ERROR: patch should not exist yet" && exit 1)
	@$(MAKE) -s -f test_patch_generate.mk $(MINIZ_TGT)
	@grep -q "MY LOCAL TWEAK" $(MINIZ_DIR)/miniz.h && (echo "ERROR: nothing should be patched yet" && exit 1) || true
	@echo "  build with no patch file: OK"

	@# ── Edit in place, then generate the patch from the edit ──
	@sed -i '1i /* MY LOCAL TWEAK */' $(MINIZ_DIR)/miniz.h
	@$(MAKE) -s -f test_patch_generate.mk miniz_patch
	@test -s $(MINIZ_PATCH) || (echo "ERROR: patch not generated" && exit 1)
	@grep -q "MY LOCAL TWEAK" $(MINIZ_PATCH) || (echo "ERROR: edit not captured in patch" && exit 1)
	@echo "  generate patch from in-place edit: OK"

	@# ── Clean rebuild re-applies the generated patch ──
	@rm -rf $(MINIZ_DIR) $(GRAFT_CACHE)
	@$(MAKE) -s -f test_patch_generate.mk $(MINIZ_TGT)
	@grep -q "MY LOCAL TWEAK" $(MINIZ_DIR)/miniz.h || (echo "ERROR: patch not re-applied on clean build" && exit 1)
	@echo "Patch-generate test: OK"
