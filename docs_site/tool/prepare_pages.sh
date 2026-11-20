#!/usr/bin/env bash
# Adapts the static build to a GitHub Pages project path.
#
# Jaspr emits `<base href="/"/>` plus root-absolute URLs. A Pages project
# site serves under /<repo>/, so move the base to that prefix and make every
# root-absolute href/src document-relative; the browser and Jaspr's client
# binding (which reads document.baseURI) resolve them through the base.
#
# The rewrite is idempotent: a second run finds no `<base href="/"/>` and no
# root-absolute href/src left to change.
set -euo pipefail

base="${1:-/trickster/}"
build="${2:-build/jaspr}"

[[ "$base" == /* ]] || base="/$base"
[[ "$base" == */ ]] || base="$base/"

[[ -f "$build/index.html" ]] || {
  echo "missing $build/index.html; run jaspr build first" >&2
  exit 1
}

find "$build" -type f -name '*.html' -print0 |
  xargs -0 -r perl -pi -e "s{<base href=\"/\"/>}{<base href=\"$base\"/>}g; s{(?<!<base )(href|src)=\"/(?!/)}{\$1=\"}g"
