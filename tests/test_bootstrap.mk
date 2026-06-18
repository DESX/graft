# Test: self-bootstrapping graft — one-line shallow clone of a ref, then include.
b := build_test_bootstrap
DL := .cache_test_bootstrap

# Bootstrap from the local graft checkout so the test runs offline and without
# depending on a release tag being pushed yet. `main` always exists locally; the
# clone mechanism is identical for a vX.Y.Z tag (what the docs recommend).
GRAFT_URL ?= $(abspath ..)
GRAFT_REV ?= main

$b/graft/graft.mk:; @git clone -q --depth=1 -b $(GRAFT_REV) $(GRAFT_URL) $(dir $@)
include $b/graft/graft.mk

# Exercise a bootstrapped macro; checked at runtime (on the first parse pass the
# include is not yet built, so this would be empty — by the time `test` runs,
# Make has rebuilt the include and re-read this file with the macros defined).
MACRO_OK := $(call GRAFT_LOWER,ABC)

.PHONY: test
test: $b/graft/graft.mk
	@test -f $b/graft/graft.mk   || (echo "ERROR: graft.mk not bootstrapped" && exit 1)
	@test -f $b/graft/pidwatch.c || (echo "ERROR: pidwatch.c not fetched"    && exit 1)
	@test "$(MACRO_OK)" = "abc"  || (echo "ERROR: graft macros not loaded"   && exit 1)
	@got=$$(git -C $b/graft rev-parse HEAD); \
	  want=$$(git -C .. rev-parse $(GRAFT_REV)); \
	  test "$$got" = "$$want" || (echo "ERROR: expected $(GRAFT_REV) ($$want), got $$got" && exit 1)
	@echo "Self-bootstrap test: OK (cloned $(GRAFT_REV))"
