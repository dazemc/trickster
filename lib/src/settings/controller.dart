import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/platform/layer_shell.dart';

/// Loads and saves the bar's settings document for the settings application.
///
/// The running bar owns the document and serves it over the control socket;
/// when no bar answers, the app falls back to the file transport. Both paths
/// ride [NativeSettingsStore], so revision check-and-retry behaves the same
/// whether the bar is up or down.
class SettingsAppController extends ChangeNotifier {
  SettingsAppController({
    SettingsDocumentTransport? socket,
    SettingsDocumentTransport? file,
    OutputsDocumentTransport? outputsSocket,
    OutputsDocumentTransport? outputsFile,
    LayerShell? layerShell,
  }) : _socket = socket ?? SocketSettingsTransport(),
       _file = file ?? FileSettingsTransport(File(ConfigPaths().settings)),
       _outputsSocket = outputsSocket ?? SocketOutputsTransport(),
       _outputsFile =
           outputsFile ?? FileOutputsTransport(File(ConfigPaths().outputs)),
       _layerShell = layerShell ?? LayerShell();

  final SettingsDocumentTransport _socket;
  final SettingsDocumentTransport _file;
  final OutputsDocumentTransport _outputsSocket;
  final OutputsDocumentTransport _outputsFile;
  final LayerShell _layerShell;

  NativeSettingsStore? _store;
  OutputsDocumentTransport? _outputsTransport;
  BarSettings _settings = const BarSettings();
  OutputsConfig _outputs = const OutputsConfig();
  List<LayerOutput> _availableOutputs = const <LayerOutput>[];
  String? _error;
  String? _outputsError;
  var _busy = false;
  var _usingSocket = false;
  var _loaded = false;
  var _disposed = false;

  BarSettings get settings => _settings;
  OutputsConfig get outputs => _outputs;

  /// The connectors reported by the host, for the displays page.
  List<LayerOutput> get availableOutputs => _availableOutputs;
  String? get error => _error;
  String? get outputsError => _outputsError;
  bool get busy => _busy;

  /// Whether at least one load finished (successfully or not).
  bool get loaded => _loaded;

  /// Whether the running bar owns the document this session.
  bool get usingSocket => _usingSocket;

  /// Reads the document, preferring the bar's socket. A missing or refused
  /// socket falls back to the single-writer file; a parse failure surfaces
  /// as [error] and keeps the defaults.
  Future<void> load() async {
    _busy = true;
    _error = null;
    _notify();
    var store = NativeSettingsStore(_socket);
    var usingSocket = true;
    try {
      _settings = await store.read();
    } on ControlSocketException {
      store = NativeSettingsStore(_file);
      usingSocket = false;
      try {
        _settings = await store.read();
      } on Object catch (error) {
        _error = '$error';
      }
    } on Object catch (error) {
      _error = '$error';
    }
    _store = store;
    _usingSocket = usingSocket;

    var outputsTransport = _outputsSocket;
    try {
      _outputs = OutputsConfig.parse(await outputsTransport.read());
      _outputsError = null;
    } on ControlSocketException {
      outputsTransport = _outputsFile;
      try {
        _outputs = OutputsConfig.parse(await outputsTransport.read());
        _outputsError = null;
      } on Object catch (error) {
        _outputsError = '$error';
      }
    } on Object catch (error) {
      _outputsError = '$error';
    }
    _outputsTransport = outputsTransport;
    try {
      _availableOutputs = await _layerShell.outputs();
    } on Object {
      _availableOutputs = const <LayerOutput>[];
    }

    _busy = false;
    _loaded = true;
    _notify();
  }

  /// Updates the outputs config in memory without writing.
  void previewOutputs(OutputsConfig outputs) {
    _outputs = outputs;
    _notify();
  }

  /// Writes [outputs] through the active transport (socket when the bar
  /// runs, file otherwise) and keeps the parsed result.
  Future<void> saveOutputs(OutputsConfig outputs) async {
    final transport = _outputsTransport;
    if (transport == null) {
      return;
    }
    _busy = true;
    _outputsError = null;
    _notify();
    try {
      _outputs = OutputsConfig.parse(await transport.write(outputs.encode()));
    } on Object catch (error) {
      _outputsError = '$error';
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Updates the in-memory settings without writing, for live previews while
  /// a control is being dragged.
  void preview(BarSettings settings) {
    _settings = settings;
    _notify();
  }

  /// Writes [settings] through the active store; the revision retry can
  /// absorb one concurrent save before [error] is set.
  Future<void> save(BarSettings settings) async {
    final store = _store;
    if (store == null) {
      return;
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      await store.write(settings);
      _settings = await store.read();
    } on Object catch (error) {
      _error = '$error';
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
