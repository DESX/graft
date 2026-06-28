# Test: self-bootstrapping graft — clone a ref, then include it and use a macro.
#
# The bootstrap source is a throwaway git repo built here from the working-tree
# graft.mk + pidwatch.c, with a tag (v0). This keeps the test offline AND
# independent of the surrounding checkout's refs: CI checkouts are shallow and
# carry no tags (and no `main` branch on a tag build), so cloning the checkout
# itself by ref would fail. The clone mechanism is identical to the real bootstrap.
b := build_test_bootstrap
GRAFT_CACHE := .cache_test_bootstrap

GRAFT_SRC := $b/graft-src

# Build the throwaway graft "remote" with a tag to clone by.
$(GRAFT_SRC)/.git/HEAD:
	@rm -rf $(GRAFT_SRC) && mkdir -p $(GRAFT_SRC)
	@cp ../graft.mk ../pidwatch.c $(GRAFT_SRC)/
	@git -C $(GRAFT_SRC) init -q
	@git -C $(GRAFT_SRC) add -A
	@git -C $(GRAFT_SRC) -c user.email=t@t.test -c user.name=test commit -qm graft
	@git -C $(GRAFT_SRC) tag v0

# The bootstrap one-liner under test: clone the pinned ref, then include it.
$b/graft/graft.mk: | $(GRAFT_SRC)/.git/HEAD
	@git clone -q -b v0 $(GRAFT_SRC) $(dir $@)
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
	@echo "Self-bootstrap test: OK"
