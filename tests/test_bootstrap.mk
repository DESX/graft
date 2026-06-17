# Test: self-bootstrapping graft — pinned-commit fetch + checkout, then include.
b := build_test_bootstrap
DL := .cache_test_bootstrap

# Bootstrap from the local graft checkout so the test runs offline and without
# depending on the commit being pushed yet. Pins to the working tree's HEAD,
# which is an advertised ref tip (so the SHA fetch works against a stock repo).
GRAFT_URL ?= $(abspath ..)
GRAFT_REV ?= $(shell git -C .. rev-parse HEAD)

$b/graft/graft.mk:
	@mkdir -p $(dir $@)
	@git -C $(dir $@) init -q
	@git -C $(dir $@) fetch -q --depth=1 $(GRAFT_URL) $(GRAFT_REV)
	@git -C $(dir $@) checkout -q FETCH_HEAD
include $b/graft/graft.mk

# Exercise a bootstrapped macro; checked at runtime (on the first parse pass the
# include is not yet built, so this would be empty — by the time `test` runs,
# Make has rebuilt the include and re-read this file with the macros defined).
MACRO_OK := $(call LOWER,ABC)

.PHONY: test
test: $b/graft/graft.mk
	@test -f $b/graft/graft.mk   || (echo "ERROR: graft.mk not bootstrapped" && exit 1)
	@test -f $b/graft/pidwatch.c || (echo "ERROR: pidwatch.c not fetched"    && exit 1)
	@test "$(MACRO_OK)" = "abc"  || (echo "ERROR: graft macros not loaded"   && exit 1)
	@got=$$(git -C $b/graft rev-parse HEAD); \
	  test "$$got" = "$(GRAFT_REV)" || (echo "ERROR: expected $(GRAFT_REV), got $$got" && exit 1)
	@echo "Self-bootstrap test: OK (pinned $(GRAFT_REV))"
