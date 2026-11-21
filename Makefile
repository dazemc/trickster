.PHONY: release install

# Build the AOT bundle and overwrite the local /usr/lib/trickster install.
# The install script self-escalates with sudo; every run replaces the old
# binary and its data/lib beside it.
release:
	flutter build linux --release
	./packaging/install-local.sh

install:
	./packaging/install-local.sh
