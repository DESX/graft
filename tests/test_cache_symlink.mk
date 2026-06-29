# Test: NAME_TAR / NAME_FILE name ONLY the human-readable inspection symlink in the
# cache root. The content store (hash_files/) and key store (key_files/) are ALWAYS
# named by hashes — NAME_TAR/NAME_FILE never leak into them.
b := build_test_cache_symlink
GRAFT_CACHE := .cache_test_cache_symlink

include ../graft.mk

MINIZ_TGT     := miniz.h
MINIZ_TAR     := my-custom-name.tgz        # only names the inspection symlink
MINIZ_COMMIT  := 3.0.2
MINIZ_GIT_URL := https://github.com/richgel999/miniz.git
$(eval $(call GRAFT_FETCH,MINIZ))

DIRS := $b $(GRAFT_CACHE) $(MINIZ_DIR)
$(foreach V,$(sort $(DIRS)),$(eval $(call GRAFT_MK_DIR,$V)))

.PHONY: test
test: $(MINIZ_TGT)
	@# The inspection symlink uses NAME_TAR's name and points into hash_files/.
	@test -L $(GRAFT_CACHE)/my-custom-name.tgz || (echo "ERROR: custom-named symlink not created" && exit 1)
	@readlink $(GRAFT_CACHE)/my-custom-name.tgz | grep -qE '^hash_files/[0-9a-f]{64}$$' \
	  || (echo "ERROR: symlink does not point at a hash file: '$$(readlink $(GRAFT_CACHE)/my-custom-name.tgz)'" && exit 1)
	@echo "  NAME_TAR names the inspection symlink: OK"
	@# Enforcement: the hash/key stores contain ONLY hashes, never the custom name.
	@! ls $(GRAFT_CACHE)/hash_files | grep -vqE '^[0-9a-f]{64}$$' || (echo "ERROR: non-hash entry in hash_files/" && exit 1)
	@! ls $(GRAFT_CACHE)/key_files  | grep -vqE '^[0-9a-f]{12}$$' || (echo "ERROR: non-hash entry in key_files/" && exit 1)
	@test ! -e $(GRAFT_CACHE)/hash_files/my-custom-name.tgz || (echo "ERROR: NAME_TAR leaked into hash_files/" && exit 1)
	@test ! -e $(GRAFT_CACHE)/key_files/my-custom-name.tgz  || (echo "ERROR: NAME_TAR leaked into key_files/" && exit 1)
	@echo "  hash_files/ and key_files/ hold only hashes: OK"
	@echo "Cache symlink-name test: OK"
