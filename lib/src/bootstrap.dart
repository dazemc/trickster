import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'config/paths.dart';
import 'config/session.dart';
import 'config/settings.dart';
import 'layout/system_bar.dart';

class RuntimeConfig {
  const RuntimeConfig({
    required this.paths,
    required this.session,
    required this.outputs,
    required this.settings,
  });

  final ConfigPaths paths;
  final SessionConfig session;
  final OutputsConfig outputs;
  final BarSettings settings;
}

class Bootstrap {
  static RuntimeConfig load({
    String? configPath,
    String? edge,
    bool strict = false,
  }) {
    final sessionFile = _session();
    final paths = ConfigPaths(
      outputOverride: configPath ?? sessionFile.outputConfig,
    );
    _seedUserConfig(paths);
    return RuntimeConfig(
      paths: paths,
      session: SessionConfig.fromEnvironment(defaults: sessionFile),
      outputs: _outputs(paths, edge: edge, strict: strict),
      settings: _settings(paths, strict: strict),
    );
  }

  static SessionConfig _session() {
    final file = File('/etc/trickster/session.conf');
    if (!file.existsSync()) {
      return const SessionConfig();
    }
    try {
      return SessionConfig.parse(file.readAsStringSync());
    } on FormatException {
      stderr.writeln('trickster: ignoring invalid session.conf');
      return const SessionConfig();
    }
  }

  static OutputsConfig _outputs(
    ConfigPaths paths, {
    String? edge,
    bool strict = false,
  }) {
    final file = File(paths.outputs);
    var config = const OutputsConfig();
    if (file.existsSync()) {
      try {
        config = OutputsConfig.parse(file.readAsStringSync());
      } on FormatException catch (error) {
        stderr.writeln('trickster: $error');
        if (strict) {
          rethrow;
        }
      }
    }
    if (edge != null) {
      config = OutputsConfig(
        side: SystemBarSideGeometry.parse(edge),
        thickness: config.thickness,
        connectors: config.connectors,
      );
    }
    return config;
  }

  static BarSettings _settings(ConfigPaths paths, {bool strict = false}) {
    final file = File(paths.settings);
    if (!file.existsSync()) {
      return const BarSettings();
    }
    try {
      return BarSettings.decode(file.readAsStringSync());
    } on FormatException catch (error) {
      stderr.writeln('trickster: $error');
      if (strict) {
        rethrow;
      }
      return const BarSettings();
    }
  }

  static void _seedUserConfig(ConfigPaths paths) {
    seedUserConfig(paths, outputsTemplate: _packagedOutputsTemplate);
  }

  /// The template the package installs at `/etc/trickster/outputs.conf`.
  /// Absent in a source checkout; the built-in header stands in then.
  static const _packagedOutputsTemplate = '/etc/trickster/outputs.conf';

  /// Seeds a session user's config directory on first launch. The per-user
  /// `outputs.conf` is written once from the packaged template and never
  /// overwritten after that.
  @visibleForTesting
  static void seedUserConfig(ConfigPaths paths, {String? outputsTemplate}) {
    paths.directory.createSync(recursive: true);
    final outputs = File(paths.outputs);
    if (!outputs.existsSync()) {
      outputs.writeAsStringSync(_outputsTemplate(outputsTemplate));
    }
    final settings = File(paths.settings);
    if (!settings.existsSync()) {
      settings.writeAsStringSync(const BarSettings().encode());
    }
  }

  static String _outputsTemplate(String? path) {
    if (path != null) {
      try {
        final packaged = File(path);
        if (packaged.existsSync()) {
          return packaged.readAsStringSync();
        }
      } on FileSystemException {
        // An unreadable template falls back to the built-in header.
      }
    }
    return '# Trickster output configuration\n# system_bar=top,32\n';
  }
}
