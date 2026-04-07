# Graft test runner
SHELL := /bin/bash

TESTS := test_tar_download test_git_clone test_patch test_overlay test_caching test_dependencies test_pidwatch

.PHONY: all clean $(TESTS)

all: $(TESTS)
	@echo ""; echo "=== All tests passed ==="

$(TESTS):
	@echo ""; echo "=== Running $@ ==="
	@rm -rf build_$@ .cache_$@
	@mkdir -p build_$@ .cache_$@
	@set -o pipefail && $(MAKE) -f $@.mk test 2>&1 | tee build_$@/log.txt || (echo "FAILED: $@" && exit 1)
	@rm -rf build_$@ .cache_$@
	@echo "PASSED: $@"

clean:
	rm -rf build_* .cache_*
