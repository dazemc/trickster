import 'dart:io';

/// Normalizes a config path for identity comparisons and file access.
///
/// The path becomes absolute and `.`/`..` segments and duplicate separators
/// collapse. Symbolic links are deliberately not resolved: watcher events
/// carry the spelling of the watched directory, so resolving links would
/// turn every path under a symlinked config root into a mismatch. The same
/// normalization on both sides makes a relative override, a `./` event path,
/// and a `dir/../dir` spelling compare equal.
String normalizeConfigPath(String path) {
  final absolute = File(path).absolute.path;
  final segments = <String>[];
  for (final segment in absolute.split(Platform.pathSeparator)) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(segment);
  }
  final prefix = absolute.startsWith(Platform.pathSeparator)
      ? Platform.pathSeparator
      : '';
  if (segments.isEmpty) {
    return prefix.isEmpty ? '.' : prefix;
  }
  return '$prefix${segments.join(Platform.pathSeparator)}';
}

class ConfigPaths {
  ConfigPaths({
    String? configHome,
    String? outputOverride,
    String? sessionOverride,
    Map<String, String>? environment,
  }) : configHome = normalizeConfigPath(
         configHome ?? _configHomeFrom(environment ?? Platform.environment),
       ),
       outputOverride = _normalizedOrNull(
         outputOverride ??
             (environment ?? Platform.environment)['TRICKSTER_OUTPUT_CONFIG'],
       ),
       sessionOverride = _normalizedOrNull(sessionOverride);

  final String configHome;
  final String? outputOverride;
  final String? sessionOverride;

  String get root => '$configHome/trickster';
  String get outputs => outputOverride ?? '$root/outputs.conf';
  String get settings => '$root/settings.json';
  String get session => sessionOverride ?? '/etc/trickster/session.conf';

  Directory get directory => Directory(root);

  /// Every directory a config watcher must cover: the settings root, plus the
  /// outputs file's parent when an override places it elsewhere (or nests it
  /// below the root). An override that shares the root needs one watch only.
  List<Directory> get watchDirectories {
    final outputsDirectory = File(outputs).parent.path;
    return <Directory>[
      directory,
      if (outputsDirectory != root) Directory(outputsDirectory),
    ];
  }

  static String _configHomeFrom(Map<String, String> environment) {
    return environment['XDG_CONFIG_HOME'] ?? '${environment['HOME']}/.config';
  }

  static String? _normalizedOrNull(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return normalizeConfigPath(value);
  }
}
