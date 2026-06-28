# Test: the empty-SHA discovery workflow, and that every fetch type takes a SHA.
# For a single-file fetch and a git fetch:
#   1. an empty NAME_SHA256 fails the build and prints the hash as a paste-ready line
#      (and installs nothing) — even with no `make clean`, because discovery has its
#      own cache key;
#   2. pasting that hash verifies and installs;
#   3. a wrong hash fails.
# The git roundtrip also proves the produced tarball is byte-reproducible: the hash
# discovered from one clone must verify a second, independent clone.
b := build_test_sha_discovery
GRAFT_CACHE := .cache_test_sha_discovery

include ../graft.mk

# Single-file source. NAME_SHA256 is supplied per sub-make (command line).
HDR_TGT := $b/hdr/miniz.h
HDR_URL := https://raw.githubusercontent.com/richgel999/miniz/3.0.2/miniz.h
$(eval $(call GRAFT_FETCH_FILE,HDR))

# Git source.
GIT_TGT     := miniz.h
GIT_COMMIT  := 3.0.2
GIT_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,GIT))

DIRS := $b $(GRAFT_CACHE) $(GIT_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: | $b
	@# ───── single file ─────
	@# Discovery: empty SHA prints the hash and fails, installing nothing.
	@h=$$($(MAKE) -s -f test_sha_discovery.mk HDR_SHA256= $(HDR_TGT) 2>&1 >/dev/null | sed -n 's/.*HDR_SHA256 := //p'); \
	  test -n "$$h" || (echo "ERROR: file discovery printed no hash" && exit 1); \
	  test ! -f $(HDR_TGT) || (echo "ERROR: file installed on empty SHA" && exit 1); \
	  echo "$$h" > $b/.hdr
	@# Pin the printed hash → verify + install.
	@H=$$(cat $b/.hdr); $(MAKE) -s -f test_sha_discovery.mk HDR_SHA256=$$H $(HDR_TGT); \
	  test -f $(HDR_TGT) || (echo "ERROR: file pinned hash failed to verify/install" && exit 1)
	@# Wrong hash → fail.
	@! $(MAKE) -s -f test_sha_discovery.mk HDR_SHA256=deadbeef $(HDR_TGT) >/dev/null 2>&1 \
	  || (echo "ERROR: wrong file SHA accepted" && exit 1)
	@echo "  file: discovery -> pin -> verify, wrong rejected: OK"

	@# ───── git (also proves the tarball is reproducible) ─────
	@h=$$($(MAKE) -s -f test_sha_discovery.mk GIT_SHA256= $(GIT_TGT) 2>&1 >/dev/null | sed -n 's/.*GIT_SHA256 := //p'); \
	  test -n "$$h" || (echo "ERROR: git discovery printed no hash" && exit 1); \
	  test ! -f $(GIT_TGT) || (echo "ERROR: git installed on empty SHA" && exit 1); \
	  echo "$$h" > $b/.git
	@# A second, independent clone must produce the same hash, so the pin verifies.
	@H=$$(cat $b/.git); $(MAKE) -s -f test_sha_discovery.mk GIT_SHA256=$$H $(GIT_TGT); \
	  test -f $(GIT_TGT) || (echo "ERROR: git pinned hash failed — tarball not reproducible?" && exit 1)
	@! $(MAKE) -s -f test_sha_discovery.mk GIT_SHA256=deadbeef $(GIT_TGT) >/dev/null 2>&1 \
	  || (echo "ERROR: wrong git SHA accepted" && exit 1)
	@echo "  git: discovery -> pin -> verify (reproducible), wrong rejected: OK"
	@echo "SHA discovery workflow test: OK"
