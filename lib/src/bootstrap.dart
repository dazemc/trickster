import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/session.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/layout/system_bar.dart';

class RuntimeConfig {
  const RuntimeConfig({
    required this.paths,
    required this.session,
    required this.outputs,
    required this.settings,
    this.outputsError,
    this.settingsError,
  });

  final ConfigPaths paths;
  final SessionConfig session;
  final OutputsConfig outputs;
  final BarSettings settings;

  /// Parse errors for one document; the other document still loads.
  final String? outputsError;
  final String? settingsError;

  bool get hasErrors => outputsError != null || settingsError != null;

  String? get errorSummary {
    final errors = <String>[
      if (outputsError case final error?) 'outputs.conf: $error',
      if (settingsError case final error?) 'settings.json: $error',
    ];
    return errors.isEmpty ? null : errors.join('; ');
  }
}

class Bootstrap {
  static RuntimeConfig load({
    String? configPath,
    String? edge,
    bool strict = false,
    @visibleForTesting ConfigPaths? paths,
  }) {
    final sessionFile = _session();
    paths ??= ConfigPaths(
      outputOverride: configPath ?? sessionFile.outputConfig,
    );
    _seedUserConfig(paths);
    final (outputs, outputsError) = _outputs(paths, edge: edge);
    final (settings, settingsError) = _settings(paths, strict: strict);
    return RuntimeConfig(
      paths: paths,
      session: SessionConfig.fromEnvironment(defaults: sessionFile),
      outputs: outputs,
      settings: settings,
      outputsError: outputsError,
      settingsError: settingsError,
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

  static (OutputsConfig, String?) _outputs(ConfigPaths paths, {String? edge}) {
    final file = File(paths.outputs);
    var config = const OutputsConfig();
    String? error;
    if (file.existsSync()) {
      try {
        config = OutputsConfig.parse(file.readAsStringSync());
      } on Object catch (parseError) {
        stderr.writeln('trickster: $parseError');
        error = '$parseError';
      }
    }
    if (edge != null) {
      config = OutputsConfig(
        side: SystemBarSideGeometry.parse(edge),
        thickness: config.thickness,
        connectors: config.connectors,
      );
    }
    return (config, error);
  }

  static (BarSettings, String?) _settings(
    ConfigPaths paths, {
    bool strict = false,
  }) {
    final file = File(paths.settings);
    final previous = File('${file.path}.prev');
    if (!file.existsSync() && !previous.existsSync()) {
      return (const BarSettings(), null);
    }
    if (strict && file.existsSync()) {
      // A preflight validates the live document itself; `.prev` recovery is a
      // runtime courtesy, never an excuse to pass a corrupt file.
      try {
        return (BarSettings.decode(file.readAsStringSync()), null);
      } on Object catch (error) {
        // Decoders cast typed fields, so a wrong JSON scalar throws TypeError
        // rather than FormatException. Both mean "invalid document" here.
        stderr.writeln('trickster: $error');
        return (const BarSettings(), '$error');
      }
    }
    try {
      // Match the settings application: a torn or unreadable live file falls
      // back to `.prev` instead of discarding the user's document.
      return (
        BarSettings.decode(FileSettingsTransport(file).readSync().json),
        null,
      );
    } on Object catch (error) {
      stderr.writeln('trickster: $error');
      return (const BarSettings(), '$error');
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
    if (!settings.existsSync() && !File('${settings.path}.prev').existsSync()) {
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
