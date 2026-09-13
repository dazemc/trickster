import 'dart:io';

/// Denial opens its own settings application's power page. A guest bar has no
/// settings application, so the honest replacement is the host desktop's power
/// settings. First candidate that starts wins.
const _candidates = <List<String>>[
  ['gnome-control-center', 'power'],
  ['systemsettings', 'kcm_powerdevilprofilesconfig'],
  ['xfce4-power-manager-settings'],
  ['mate-power-preferences'],
  ['cinnamon-settings', 'power'],
  ['cosmic-settings', 'power'],
  ['lxqt-config-powermanagement'],
];

Future<void> openPowerSettings() async {
  for (final candidate in _candidates) {
    try {
      await Process.start(
        candidate.first,
        candidate.sublist(1),
        mode: ProcessStartMode.detached,
      );
      return;
    } on ProcessException {
      continue;
    } on Object catch (error) {
      stderr.writeln('trickster: power settings: $error');
      return;
    }
  }
  stderr.writeln('trickster: no power settings application found');
}
