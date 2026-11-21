import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:trickster/src/config/outputs_store.dart';
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
    this.outputsWarning,
    this.settingsError,
  });

  final ConfigPaths paths;
  final SessionConfig session;
  final OutputsConfig outputs;
  final BarSettings settings;

  /// Parse errors for one document; the other document still loads.
  final String? outputsError;
  final String? settingsError;

  /// The live outputs document was invalid, but a valid `.prev` snapshot
  /// supplied [outputs]. The bar applies the recovered placement; a preflight
  /// still reports the live file as invalid.
  final String? outputsWarning;

  bool get hasErrors => outputsError != null || settingsError != null;

  bool get hasWarnings => outputsWarning != null;

  String? get errorSummary {
    final errors = <String>[
      if (outputsError case final error?) 'outputs.conf: $error',
      if (settingsError case final error?) 'settings.json: $error',
    ];
    return errors.isEmpty ? null : errors.join('; ');
  }

  String? get warningSummary =>
      outputsWarning == null ? null : 'outputs.conf: $outputsWarning';
}

class Bootstrap {
  /// Resolves the documents this process reads and writes.
  ///
  /// Precedence for the outputs document: the `--config` CLI override, then
  /// the process `TRICKSTER_OUTPUT_CONFIG`, then the same key in
  /// `/etc/trickster/session.conf`, then the per-user default under
  /// `$XDG_CONFIG_HOME/trickster`. An explicitly injected [paths] wins over
  /// every source so tests and embedded callers keep full control.
  static ConfigPaths resolvePaths({
    String? configPath,
    ConfigPaths? paths,
    Map<String, String>? environment,
    String? sessionPath,
  }) {
    if (paths != null) {
      return paths;
    }
    final env = environment ?? Platform.environment;
    final session = _session(path: sessionPath);
    return ConfigPaths(
      outputOverride: _firstNonEmpty(<String?>[
        configPath,
        env['TRICKSTER_OUTPUT_CONFIG'],
        session.outputConfig,
      ]),
      sessionOverride: sessionPath,
      environment: env,
    );
  }

  static RuntimeConfig load({
    String? configPath,
    String? edge,
    bool strict = false,
    ConfigPaths? paths,
  }) {
    paths ??= resolvePaths(configPath: configPath);
    final sessionFile = _session(path: paths.session);
    _seedUserConfig(paths);
    final (outputs, outputsError, outputsWarning) = _outputs(paths, edge: edge);
    final (settings, settingsError) = _settings(paths, strict: strict);
    return RuntimeConfig(
      paths: paths,
      session: SessionConfig.fromEnvironment(defaults: sessionFile),
      outputs: outputs,
      settings: settings,
      outputsError: outputsError,
      outputsWarning: outputsWarning,
      settingsError: settingsError,
    );
  }

  static SessionConfig _session({String? path}) {
    final file = File(path ?? '/etc/trickster/session.conf');
    if (!file.existsSync()) {
      return const SessionConfig();
    }
    try {
      return SessionConfig.parse(file.readAsStringSync());
    } on Object {
      stderr.writeln('trickster: ignoring invalid session.conf');
      return const SessionConfig();
    }
  }

  static String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static (OutputsConfig, String?, String?) _outputs(
    ConfigPaths paths, {
    String? edge,
  }) {
    final file = File(paths.outputs);
    final transport = FileOutputsTransport(file);
    OutputsConfig? parsed;
    String? liveError;
    if (file.existsSync()) {
      try {
        final document = file.readAsStringSync();
        if (document.trim().isEmpty) {
          liveError = 'outputs.conf is empty';
        } else {
          parsed = OutputsConfig.parse(document);
        }
      } on Object catch (parseError) {
        stderr.writeln('trickster: $parseError');
        liveError = '$parseError';
      }
    }
    // A valid live document always wins. A missing, unreadable, empty, or
    // corrupt live file recovers from the same `.prev` snapshot the settings
    // application reads instead of silently resetting placement to defaults.
    var config = parsed;
    String? warning;
    if (config == null) {
      final recovered = transport.readDocumentSync();
      if (recovered != null) {
        // The snapshot is a usable document. The live file's parse error is
        // reported separately as a warning: the bar applies the recovered
        // placement instead of keeping last-good state, while `--check`
        // still sees that the live document itself is invalid.
        config = OutputsConfig.parse(recovered);
        warning = liveError;
        liveError = null;
      } else {
        // Neither the live document nor its snapshot is usable: keep the
        // live-file error so `--check` and the reload path surface it.
        config = const OutputsConfig();
      }
    }
    if (edge != null) {
      final side = SystemBarSideGeometry.parse(edge);
      config = OutputsConfig(
        side: side,
        // A hidden document stores thickness 0. A one-shot edge override must
        // reactivate the strip at the default band instead of leaving a
        // zero-thickness, inactive bar.
        thickness: config.thickness > 0
            ? config.thickness
            : OutputsConfig.defaultThickness,
        connectors: config.connectors,
      );
    }
    return (config, liveError, warning);
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
  ///
  /// A valid `outputs.conf.prev` is already a recoverable document: writing
  /// the default live file over a missing live path would shadow the snapshot
  /// and discard the user's placement. Seeding is a courtesy and must never
  /// take the bar down: an unwritable config directory is logged and the bar
  /// continues with what it can read.
  @visibleForTesting
  static void seedUserConfig(ConfigPaths paths, {String? outputsTemplate}) {
    try {
      paths.directory.createSync(recursive: true);
    } on Object catch (error) {
      stderr.writeln('trickster: cannot create config directory: $error');
    }
    try {
      final outputs = File(paths.outputs);
      if (!outputs.existsSync() && !_hasValidPreviousOutputs(outputs)) {
        outputs.writeAsStringSync(_outputsTemplate(outputsTemplate));
      }
    } on Object catch (error) {
      stderr.writeln('trickster: cannot seed outputs.conf: $error');
    }
    try {
      final settings = File(paths.settings);
      if (!settings.existsSync() &&
          !File('${settings.path}.prev').existsSync()) {
        settings.writeAsStringSync(const BarSettings().encode());
      }
    } on Object catch (error) {
      stderr.writeln('trickster: cannot seed settings.json: $error');
    }
  }

  /// Whether the outputs snapshot beside [file] is a document the transport
  /// would accept as last-good. A snapshot that cannot decode is no better
  /// than no snapshot, so the default file is still written then.
  static bool _hasValidPreviousOutputs(File file) {
    final previous = File('${file.path}.prev');
    if (!previous.existsSync()) {
      return false;
    }
    try {
      return FileOutputsTransport.isValidDocument(previous.readAsStringSync());
    } on Object {
      return false;
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
