#!/usr/bin/env bash
# Installs the current Flutter release bundle over the local package at
# /usr/lib/trickster. Run `make release` to build first; the script asks for
# sudo because the package directory is root-owned.
set -euo pipefail

prefix="${PREFIX:-/usr}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bundle="$root/build/linux/x64/release/bundle"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo --preserve-env=PREFIX -- "$0" "$@"
fi

for required in \
  "$bundle/trickster" \
  "$bundle/data/icudtl.dat" \
  "$bundle/data/flutter_assets/AssetManifest.bin" \
  "$bundle/lib/libapp.so" \
  "$bundle/lib/libflutter_linux_gtk.so"; do
  if [[ ! -f "$required" ]]; then
    echo "missing release bundle component: $required" >&2
    echo "run 'flutter build linux --release' first" >&2
    exit 1
  fi
done

install -d -m 0755 "$prefix/lib/trickster" "$prefix/bin"
install -m 0755 "$bundle/trickster" "$prefix/lib/trickster/trickster"
# data/lib are resolved relative to the executable, so replace them whole.
rm -rf "$prefix/lib/trickster/data" "$prefix/lib/trickster/lib"
cp -a "$bundle/data" "$bundle/lib" "$prefix/lib/trickster/"
# Preserve the package's separately compiled control client; this bundle does
# not carry it.
ln -sfn ../lib/trickster/trickster "$prefix/bin/trickster"
ln -sfn trickster "$prefix/bin/trickster-settings"

echo "installed $(stat -c '%y' "$bundle/trickster") -> $prefix/lib/trickster/trickster"
