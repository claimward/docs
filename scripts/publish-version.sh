#!/bin/sh
# Publish one documentation build into a checkout of the gh-pages branch.
#
#   scripts/publish-version.sh <version> <built site> <gh-pages checkout>
#
# <version> is "dev" (the build of main) or a strict semver tag vX.Y.Z. The
# build replaces <gh-pages>/<version>/ and nothing else: every other version
# already published -- the MkDocs-built v0.1.0 among them -- is kept as it is.
# Then, from the directories present:
#
#   versions.json   rewritten in mike's format ({version, title, aliases,
#                   properties}), dev first, then releases newest first; the
#                   version selectors of the Hugo builds and of the MkDocs
#                   v0.1.0 both read it;
#   latest          a symbolic link to the newest release (as mike made it);
#   index.html      the root, redirecting to latest/ (dev/ until a release).
#
# Needs jq. Commits nothing: the workflow does.
set -eu

die() { echo "publish-version.sh: $*" >&2; exit 1; }

[ $# -eq 3 ] || die "usage: $0 <version> <built site> <gh-pages checkout>"
version=$1
site=$2
pages=$3
dev=dev
semver='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

if [ "$version" != "$dev" ] && ! printf '%s\n' "$version" | grep -Eq "$semver"; then
	die "version must be \"$dev\" or vMAJOR.MINOR.PATCH, not \"$version\""
fi
[ -f "$site/index.html" ] || die "$site/index.html is missing: build the site first"
[ -d "$pages" ] || die "$pages is not a directory"
command -v jq >/dev/null || die "jq is required"

# The version's own directory, replaced whole. A real directory: if it was a
# link (an alias), the link goes, not what it pointed to.
[ -L "$pages/$version" ] && rm "$pages/$version"
mkdir -p "$pages/$version"
rsync -a --delete "$site/" "$pages/$version/"

# The releases present, newest first.
releases=$(cd "$pages" && for d in v*; do
	[ -d "$d" ] && [ ! -L "$d" ] && printf '%s\n' "$d" | grep -Eq "$semver" && printf '%s\n' "$d"
done | sed 's/^v//' | sort -t. -k1,1nr -k2,2nr -k3,3nr | sed 's/^/v/')
latest=$(printf '%s\n' "$releases" | sed -n 1p)

# versions.json: dev (if published), then the releases; the newest carries
# the alias "latest".
{
	if [ -d "$pages/$dev" ] && [ ! -L "$pages/$dev" ]; then
		jq -n --arg v "$dev" '{version: $v, title: $v, aliases: [], properties: {development: true}}'
	fi
	for r in $releases; do
		if [ "$r" = "$latest" ]; then
			jq -n --arg v "$r" '{version: $v, title: $v, aliases: ["latest"]}'
		else
			jq -n --arg v "$r" '{version: $v, title: $v, aliases: []}'
		fi
	done
} | jq -s . >"$pages/versions.json.tmp"
mv "$pages/versions.json.tmp" "$pages/versions.json"

# latest -> the newest release, and the root redirect.
target=${latest:-$dev}
if [ -n "$latest" ]; then
	rm -rf "$pages/latest"
	ln -s "$latest" "$pages/latest"
	target=latest
fi
cat >"$pages/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Redirecting</title>
  <noscript>
    <meta http-equiv="refresh" content="1; url=$target/" />
  </noscript>
  <script>
    window.location.replace(
      "$target/" + window.location.search + window.location.hash
    );
  </script>
</head>
<body>
  Redirecting to <a href="$target/">$target/</a>...
</body>
</html>
EOF
touch "$pages/.nojekyll"

echo "published $version; latest is ${latest:-none}; versions: $(jq -r '[.[].version] | join(", ")' "$pages/versions.json")"
