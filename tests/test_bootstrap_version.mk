# Test: the versioned self-bootstrap. The bootstrap clones graft into a
# version-stamped dir (graft-<ver>), so bumping the pinned version clones the new
# copy ALONGSIDE the old one. Updating graft never requires deleting the old dir.
#
# The bootstrap source is a throwaway git repo built here from the working-tree
# graft.mk + pidwatch.c, with two tags (va, vb). Building our own remote keeps the
# test offline and independent of the surrounding checkout's refs (CI checkouts are
# shallow and tagless, so cloning the checkout by tag would fail).
b := build_test_bootstrap_version

GRAFT_SRC := $b/graft-src

# Throwaway graft "remote" with two tags to bootstrap.
$(GRAFT_SRC)/.git/HEAD:
	@rm -rf $(GRAFT_SRC) && mkdir -p $(GRAFT_SRC)
	@cp ../graft.mk ../pidwatch.c $(GRAFT_SRC)/
	@git -C $(GRAFT_SRC) init -q
	@git -C $(GRAFT_SRC) add -A
	@git -C $(GRAFT_SRC) -c user.email=t@t.test -c user.name=test commit -qm graft
	@git -C $(GRAFT_SRC) tag va && git -C $(GRAFT_SRC) tag vb

# The bootstrap rule under test: clone tag <ver> into a version-stamped dir.
$b/graft-%/graft.mk: | $(GRAFT_SRC)/.git/HEAD
	@git clone -q -b $* $(GRAFT_SRC) $(dir $@)

.PHONY: test
test: $b/graft-va/graft.mk $b/graft-vb/graft.mk
	@test -f $b/graft-va/graft.mk || (echo "ERROR: first version missing" && exit 1)
	@echo "  bootstrap version va: OK"
	@test -f $b/graft-vb/graft.mk || (echo "ERROR: bumped version not cloned" && exit 1)
	@echo "  bump to version vb: OK"
	@# Both versions coexist, so the bump needed no deletion of the old checkout.
	@test -f $b/graft-va/graft.mk && test -f $b/graft-vb/graft.mk \
	  || (echo "ERROR: versions do not coexist" && exit 1)
	@test -f $b/graft-va/pidwatch.c || (echo "ERROR: full graft tree not cloned" && exit 1)
	@echo "Versioned bootstrap (coexist, no delete) test: OK"
