# Graft test runner
SHELL := /bin/bash

# Version of graft under test: the tag if we're on one, otherwise the short commit
# (with -dirty for uncommitted changes). Reported in every pass/fail line so a CI
# result names exactly which graft revision passed or failed. Falls back to
# "unknown" when git or history is unavailable.
GRAFT_VERSION := $(shell git -C .. describe --tags --always --dirty 2>/dev/null || echo unknown)

TESTS := test_tar_download test_zip_download test_git_clone test_git_ref test_patch test_patch_generate test_patch_robust test_overlay test_hooks test_build_key test_caching test_dependencies test_pidwatch test_bootstrap test_bootstrap_version test_defaults test_cache_version test_cache_relocatable test_cache_key test_cache_consistency test_cache_symlink test_sha256 test_sha_discovery test_fetch_file

.PHONY: all clean $(TESTS)

all: $(TESTS)
	@echo ""; echo "=== All tests passed (graft $(GRAFT_VERSION)) ==="

$(TESTS):
	@echo ""; echo "=== Running $@ (graft $(GRAFT_VERSION)) ==="
	@rm -rf build_$@ .cache_$@
	@mkdir -p build_$@ .cache_$@
	@set -o pipefail && $(MAKE) -f $@.mk test 2>&1 | tee build_$@/log.txt \
	  || { echo "FAILED: $@ (graft $(GRAFT_VERSION))"; exit 1; }
	@rm -rf build_$@ .cache_$@
	@echo "PASSED: $@ (graft $(GRAFT_VERSION))"

clean:
	rm -rf build_* .cache_*
