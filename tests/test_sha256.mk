# Test: optional NAME_SHA256 integrity check. A correct hash is accepted; a wrong
# hash fails the build and installs nothing. One instance, with the cache cleaned
# between cases so the download (and its verify) actually runs each time — a cache
# hit would skip it. (The cache key is content-addressed by URL, so two same-URL
# instances would share one entry.)
b := build_test_sha256
GRAFT_CACHE := .cache_test_sha256

include ../graft.mk

HDR_TGT    := $b/miniz.h
HDR_URL    := https://raw.githubusercontent.com/richgel999/miniz/3.0.2/miniz.h
HDR_SHA256 := $(SHA)
$(eval $(call GRAFT_FETCH_FILE,HDR))

GOOD := 8033197e77c9567de66425939ab6164405e54aa3c60acf9312905d32c8cddc03
BAD  := 0000000000000000000000000000000000000000000000000000000000000000

DIRS := $b $(GRAFT_CACHE)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# Wrong sha256 → build must fail and install nothing.
	@rm -rf $(GRAFT_CACHE) $(HDR_TGT)
	@! $(MAKE) -s -f test_sha256.mk SHA=$(BAD) $(HDR_TGT) >/dev/null 2>&1 \
	  || (echo "ERROR: wrong sha256 was accepted" && exit 1)
	@test ! -f $(HDR_TGT) || (echo "ERROR: file installed despite bad sha256" && exit 1)
	@echo "  wrong sha256 rejected: OK"

	@# Correct sha256 → fetch succeeds.
	@rm -rf $(GRAFT_CACHE) $(HDR_TGT)
	@$(MAKE) -s -f test_sha256.mk SHA=$(GOOD) $(HDR_TGT)
	@test -f $(HDR_TGT) || (echo "ERROR: correct sha256 fetch failed" && exit 1)
	@echo "  correct sha256 accepted: OK"
	@echo "SHA256 integrity test: OK"
