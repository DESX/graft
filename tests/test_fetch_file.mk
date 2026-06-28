# Test: GRAFT_FETCH_FILE downloads a single file, caches it content-addressed,
# re-fetches on a URL/version bump, and runs the POST_FETCH hook.
b := build_test_fetch_file
GRAFT_CACHE := .cache_test_fetch_file

include ../graft.mk

# A single header fetched straight to HDR_TGT — no archive, no extraction. VER
# drives the URL; overridden per sub-make below. No HDR_FILE — it defaults.
VER     ?= 3.0.2
HDR_TGT := $b/include/miniz.h
HDR_URL := https://raw.githubusercontent.com/richgel999/miniz/$(VER)/miniz.h
HDR_POST_FETCH = touch $b/.post_fetch_ran
$(eval $(call GRAFT_FETCH_FILE,HDR))

DIRS := $b $(GRAFT_CACHE)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# ── Fetch 2.1.0; lands at HDR_TGT, cached under a versioned name ──
	@rm -f $b/.post_fetch_ran
	@$(MAKE) -s -f test_fetch_file.mk VER=2.1.0 $(HDR_TGT)
	@test -f $(HDR_TGT) || (echo "ERROR: file not fetched" && exit 1)
	@test -f $b/.post_fetch_ran || (echo "ERROR: POST_FETCH hook did not run" && exit 1)
	@ls $(GRAFT_CACHE) | grep -qE '^[0-9a-f]{12}_[0-9a-f]{12}$$' || (echo "ERROR: no content-addressed cache file" && exit 1)
	@A=$$(cksum $(HDR_TGT) | cut -d' ' -f1); echo "$$A" > $b/.a
	@echo "  fetch 2.1.0: OK"

	@# ── Bump to 3.0.2; the installed file must change ──
	@$(MAKE) -s -f test_fetch_file.mk VER=3.0.2 $(HDR_TGT)
	@B=$$(cksum $(HDR_TGT) | cut -d' ' -f1); A=$$(cat $b/.a); \
	  test "$$A" != "$$B" || (echo "ERROR: file unchanged after URL bump — stale!" && exit 1)
	@echo "  bump to 3.0.2 re-fetched: OK"

	@# ── Both versions coexist in the cache (one content file per URL key) ──
	@N=$$(ls $(GRAFT_CACHE) | grep -cE '^[0-9a-f]{12}_[0-9a-f]{12}$$'); \
	  test "$$N" -ge 2 || (echo "ERROR: cache entries do not coexist (have $$N)" && exit 1)
	@echo "File fetch test: OK"
