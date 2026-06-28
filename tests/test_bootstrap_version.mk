# Test: the versioned self-bootstrap. The bootstrap clones graft into a
# version-stamped dir (graft-$(GRAFT_VER)), so bumping the pinned version clones
# the new copy ALONGSIDE the old one. Updating graft never requires deleting the
# existing checkout first.
#
# Bootstraps from the local repo (offline, no published release needed). Both the
# `main` branch and the v1.5.0 tag exist locally; the mechanism is identical for
# any two refs.
b := build_test_bootstrap_version

GRAFT_URL ?= $(abspath ..)
GRAFT_VER ?= main
$b/graft-$(GRAFT_VER)/graft.mk:; @git clone -q --depth=1 -b $(GRAFT_VER) $(GRAFT_URL) $(dir $@)
include $b/graft-$(GRAFT_VER)/graft.mk

.PHONY: test
test:
	@# Bootstrap one version into its own dir.
	@$(MAKE) -s -f test_bootstrap_version.mk GRAFT_VER=main $b/graft-main/graft.mk
	@test -f $b/graft-main/graft.mk || (echo "ERROR: initial bootstrap missing" && exit 1)
	@echo "  bootstrap GRAFT_VER=main: OK"

	@# Bump the version: it must clone alongside, not over, the existing dir.
	@$(MAKE) -s -f test_bootstrap_version.mk GRAFT_VER=v1.5.0 $b/graft-v1.5.0/graft.mk
	@test -f $b/graft-v1.5.0/graft.mk || (echo "ERROR: bumped version not cloned" && exit 1)
	@echo "  bump GRAFT_VER=v1.5.0: OK"

	@# Both versions coexist, so the bump needed no deletion of the old checkout.
	@test -f $b/graft-main/graft.mk && test -f $b/graft-v1.5.0/graft.mk \
	  || (echo "ERROR: versions do not coexist" && exit 1)
	@test -f $b/graft-main/pidwatch.c || (echo "ERROR: full graft tree not cloned" && exit 1)
	@echo "Versioned bootstrap (coexist, no delete) test: OK"
