# Test: DIR, TAR, and TMP all default when omitted. Only TGT (relative to DIR) and
# the source are given; GRAFT_FETCH populates the install dir (version-stamped),
# cache path, and clone scratch, and makes TGT absolute within DIR.
b := build_test_defaults
GRAFT_CACHE := .cache_test_defaults

include ../graft.mk

# A git dep with NO _DIR, _TAR, or _TMP set, and a relative TGT.
MINIZ_TGT     := miniz.h
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

# DIR/TGT are auto-populated by the call above, so they can be used here.
DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: $(MINIZ_TGT)
	@# DIR defaulted to $b/<name>-<ver>, so a version bump lands in a fresh dir.
	@test "$(MINIZ_DIR)" = "$b/miniz-3.0.2" || (echo "ERROR: DIR default wrong: '$(MINIZ_DIR)'" && exit 1)
	@# TGT was made absolute within DIR.
	@test "$(MINIZ_TGT)" = "$b/miniz-3.0.2/miniz.h" || (echo "ERROR: TGT not resolved within DIR: '$(MINIZ_TGT)'" && exit 1)
	@test -f $b/miniz-3.0.2/miniz.h || (echo "ERROR: miniz.h not found" && exit 1)
	@# KEY defaulted to the keyfile $(GRAFT_CACHE)/key_files/<12-hex keyhash>.
	@echo "$(MINIZ_KEY)" | grep -qE '^$(GRAFT_CACHE)/key_files/[0-9a-f]{12}$$' \
	  || (echo "ERROR: KEY default wrong: '$(MINIZ_KEY)'" && exit 1)
	@test -f $(MINIZ_KEY) || (echo "ERROR: keyfile not created" && exit 1)
	@# Its first line is the full sha256 of the content, stored in hash_files/.
	@fh=$$(head -1 $(MINIZ_KEY)); \
	  echo "$$fh" | grep -qE '^[0-9a-f]{64}$$' || (echo "ERROR: keyfile line 1 not a sha256: '$$fh'" && exit 1); \
	  test -f $(GRAFT_CACHE)/hash_files/$$fh || (echo "ERROR: content file missing" && exit 1)
	@# TMP defaulted to $b/graft-tmp/<name> (per-project scratch, removed by clean).
	@test "$(MINIZ_TMP)" = "$b/graft-tmp/miniz" || (echo "ERROR: TMP default wrong: '$(MINIZ_TMP)'" && exit 1)
	@echo "Defaults (versioned DIR, keyfile, TMP; relative TGT) test: OK"
