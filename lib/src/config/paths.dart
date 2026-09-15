import 'dart:io';

class ConfigPaths {
  ConfigPaths({
    String? configHome,
    String? outputOverride,
    this.sessionOverride,
  }) : configHome =
           configHome ??
           Platform.environment['XDG_CONFIG_HOME'] ??
           '${Platform.environment['HOME']}/.config',
       outputOverride =
           outputOverride ?? Platform.environment['TRICKSTER_OUTPUT_CONFIG'];

  final String configHome;
  final String? outputOverride;
  final String? sessionOverride;

  String get root => '$configHome/trickster';
  String get outputs => outputOverride ?? '$root/outputs.conf';
  String get settings => '$root/settings.json';
  String get session => sessionOverride ?? '/etc/trickster/session.conf';

  Directory get directory => Directory(root);
}
