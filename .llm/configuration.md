# Trickster configuration (Denial mirror)

File style is Denial-style `KEY=VALUE` with `#` comments.

- `/etc/trickster/session.conf` (`TRICKSTER_*`): machine env — config-path
  override, layer, namespace, keyboard interactivity, accent override, log
  filter. Packaged template, `backup=`-preserved. Parsed by the Dart
  bootstrap at startup.
- `$XDG_CONFIG_HOME/trickster/outputs.conf`: bar placement with Denial's
  `system_bar=` grammar verbatim (`top,32`; `bottom,40,eDP-1`; `hidden`).
  Template copied to the user config on first launch, never overwritten.
  Strip math is ported from Denial's `display_layout.dart`; the "work area"
  becomes the layer-shell exclusive zone.
- `$XDG_CONFIG_HOME/trickster/settings.json`: versioned settings document.
  Port Denial's `settings_store.dart` (`NativeSettingsStore` +
  `SettingsDocumentTransport`) nearly verbatim — one async write queue,
  `expectedRevision` check-and-retry, full-document push into the settings
  bloc. Transport v1 is direct-file (single owner); keep the transport interface
  so a socket transport can slot in later unchanged. Retain only the current
  revision and one last-good snapshot. Never keep a document history.
- CLI mirrors `denial-session`/`denialctl`: `trickster --check` (layer-shell
  advertised? gtk-layer-shell loadable? outputs visible? config parseable?),
  `--version`, `--config PATH`, one-shot overrides; `tricksterctl
  status|reload|version` over `$XDG_RUNTIME_DIR/trickster/control.sock`.

Live reload: `dart:io` watcher on the config dir (200ms debounce). Hot keys
(accent, module list/order, clock format, thresholds) rebuild providers.
Disruptive keys (edge, layer, exclusive size, output set) destroy and
recreate only the affected layer surface. Invalid files keep last-good state
and log; never crash the bar.
