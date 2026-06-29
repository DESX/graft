#!/bin/sh
# graft.sh — stateless cache helper invoked by graft.mk recipes.
#
# Make owns the dependency graph and decides WHAT to build and WHEN; this script
# only does HOW, over explicit file arguments. It never reads mtimes and knows
# nothing about the build graph, so every verb is a pure operation on the cache:
#
#   key_files/<keyhash>  text record: line 1 = the content's sha256, rest = metadata
#   hash_files/<sha256>  the bytes, named by their own full sha256
#   <NAME>_<file>        a human-named symlink (cache root) for manual inspection
#
# GRAFT_CACHE is read from the environment (graft.mk exports it).
set -eu

: "${GRAFT_CACHE:?graft.sh: GRAFT_CACHE is not set}"

# _store KEYFILE TMPFILE NAME VERBOSE META: content-address TMPFILE into
# hash_files/<sha>, write KEYFILE (sha on line 1, then metadata), drop the symlink.
_store() {
	kf=$1 tmp=$2 name=$3 verbose=$4 meta=$5
	mkdir -p "$GRAFT_CACHE/key_files" "$GRAFT_CACHE/hash_files"
	fh=$(sha256sum "$tmp" | cut -d' ' -f1)
	if [ -e "$GRAFT_CACHE/hash_files/$fh" ]; then rm -f "$tmp"; else mv -f "$tmp" "$GRAFT_CACHE/hash_files/$fh"; fi
	printf '%s\n%s\n' "$fh" "$meta" >"$kf"
	ln -sfn "hash_files/$fh" "$GRAFT_CACHE/$verbose"
}

# _resolve KEYFILE NAME: echo the content path, erroring if it is missing.
_resolve() {
	fh=$(head -1 "$1")
	cf="$GRAFT_CACHE/hash_files/$fh"
	[ -f "$cf" ] || { echo "graft: $2 cache content $fh missing; remove $1 and rebuild" >&2; exit 1; }
	echo "$cf"
}

verb=$1
shift
case "$verb" in
clone) # clone DEST GIT_URL COMMIT
	dest=$1 url=$2 commit=$3
	rm -rf "$dest" && mkdir -p "$dest"
	git -C "$dest" init -q
	git -C "$dest" remote add origin "$url"
	git -C "$dest" fetch -q --depth 1 origin "$commit"
	git -C "$dest" -c advice.detachedHead=false checkout -q FETCH_HEAD
	git -C "$dest" submodule update -q --init --recursive --depth 1
	;;
store-dir) # store-dir KEYFILE TREE NAME VERBOSE URL COMMIT BUILT
	kf=$1 tree=$2 name=$3 verbose=$4 url=$5 commit=$6 built=$7
	mkdir -p "$GRAFT_CACHE/key_files" "$GRAFT_CACHE/hash_files"
	part="$kf.part.$$"
	tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
		-C "$(dirname "$tree")" --exclude='.git*' -cf - "$(basename "$tree")" | gzip -n >"$part"
	_store "$kf" "$part" "$name" "$verbose" \
		"$(printf '# name=%s\n# file=%s\n# url=%s\n# commit=%s\n# built=%s' "$name" "$verbose" "$url" "$commit" "$built")"
	;;
fetch-file) # fetch-file KEYFILE URL NAME VERBOSE
	kf=$1 url=$2 name=$3 verbose=$4
	mkdir -p "$GRAFT_CACHE/key_files" "$GRAFT_CACHE/hash_files"
	part="$kf.part.$$"
	curl -fL --retry 3 "$url" >"$part"
	_store "$kf" "$part" "$name" "$verbose" \
		"$(printf '# name=%s\n# file=%s\n# url=%s' "$name" "$verbose" "$url")"
	;;
verify) # verify KEYFILE SHA NAME BUILT  (SHA empty => discovery)
	kf=$1 sha=$2 name=$3 built=$4
	fh=$(head -1 "$kf")
	if [ -z "$sha" ]; then
		printf 'graft: %s_SHA256 is empty — pin it by adding:\n    %s_SHA256 := %s\n' "$name" "$name" "$fh" >&2
		exit 1
	fi
	[ "$sha" = "$fh" ] && exit 0
	if [ -n "$built" ]; then
		printf 'graft: %s built output differs from the pinned hash (build may not be reproducible here).\n  %s_SHA256 := %s\n  actual    := %s\nIf this build is meant to be reproducible, fix it; otherwise update the hash.\n' "$name" "$name" "$sha" "$fh" >&2
	else
		printf 'graft: %s source no longer matches the pinned hash.\n  %s_SHA256 := %s\n  actual    := %s\nUpdate %s_SHA256 to the actual hash above.\n' "$name" "$name" "$sha" "$fh" "$name" >&2
	fi
	exit 1
	;;
extract) # extract KEYFILE DIR FMT DISC NAME  (DISC nonempty => discovery)
	kf=$1 dir=$2 fmt=$3 disc=$4 name=$5
	if [ -n "$disc" ]; then exec "$0" verify "$kf" "" "$name" ""; fi
	cf=$(_resolve "$kf" "$name")
	case "$fmt" in
	tar) tar -xf "$cf" --strip-components=1 -C "$dir" --touch ;;
	zip) abs=$(cd "$(dirname "$cf")" && pwd)/$(basename "$cf"); (cd "$dir" && unzip -o "$abs") ;;
	esac
	;;
place) # place KEYFILE TGT DISC NAME  (single-file install)
	kf=$1 tgt=$2 disc=$3 name=$4
	if [ -n "$disc" ]; then exec "$0" verify "$kf" "" "$name" ""; fi
	cf=$(_resolve "$kf" "$name")
	mkdir -p "$(dirname "$tgt")"
	cp "$cf" "$tgt"
	;;
unpack-pristine) # unpack-pristine KEYFILE DEST  (for name_patch's reference tree)
	tar -xf "$(_resolve "$1" patch)" --strip-components=1 -C "$2"
	;;
*)
	echo "graft.sh: unknown verb '$verb'" >&2
	exit 2
	;;
esac
