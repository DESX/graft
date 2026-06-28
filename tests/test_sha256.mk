# Test: optional NAME_SHA256 integrity check on downloads. A correct hash is
# accepted; a wrong hash fails the build and installs nothing. Two instances of
# the same URL (distinct names => distinct cache files) exercise both outcomes.
b := build_test_sha256
GRAFT_CACHE := .cache_test_sha256

include ../graft.mk

URL := https://raw.githubusercontent.com/richgel999/miniz/3.0.2/miniz.h

GOOD_TGT    := $b/good.h
GOOD_URL    := $(URL)
GOOD_SHA256 := 8033197e77c9567de66425939ab6164405e54aa3c60acf9312905d32c8cddc03
$(eval $(call GRAFT_FETCH_FILE,GOOD))

BAD_TGT    := $b/bad.h
BAD_URL    := $(URL)
BAD_SHA256 := 0000000000000000000000000000000000000000000000000000000000000000
$(eval $(call GRAFT_FETCH_FILE,BAD))

DIRS := $b $(GRAFT_CACHE)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# Correct sha256 → fetch succeeds.
	@$(MAKE) -s -f test_sha256.mk $(GOOD_TGT)
	@test -f $(GOOD_TGT) || (echo "ERROR: correct sha256 fetch failed" && exit 1)
	@echo "  correct sha256 accepted: OK"

	@# Wrong sha256 → build must fail and install nothing.
	@! $(MAKE) -s -f test_sha256.mk $(BAD_TGT) >/dev/null 2>&1 \
	  || (echo "ERROR: wrong sha256 was accepted" && exit 1)
	@test ! -f $(BAD_TGT) || (echo "ERROR: file installed despite bad sha256" && exit 1)
	@echo "  wrong sha256 rejected: OK"
	@echo "SHA256 integrity test: OK"
