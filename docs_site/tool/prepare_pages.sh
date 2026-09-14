#!/usr/bin/env bash
# Adapts the static build to a GitHub Pages project path.
#
# Jaspr emits `<base href="/"/>` plus root-absolute URLs. A Pages project
# site serves under /<repo>/, so move the base to that prefix and make every
# root-absolute href/src document-relative; the browser and Jaspr's client
# binding (which reads document.baseURI) resolve them through the base.
set -euo pipefail

base="${1:-/trickster/}"
build="${2:-build/jaspr}"

[[ "$base" == /* ]] || base="/$base"
[[ "$base" == */ ]] || base="$base/"

find "$build" -name '*.html' -print0 |
  xargs -0 perl -pi -e "s{(href|src)=\"/(?!/)}{\$1=\"}g; s{<base href=\"\"/>}{<base href=\"$base\"/>}g"
