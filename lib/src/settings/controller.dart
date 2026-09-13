import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/paths.dart';
import '../config/settings.dart';
import '../config/store.dart';
import '../platform/control_socket.dart';

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
  }) : _socket = socket ?? SocketSettingsTransport(),
       _file = file ?? FileSettingsTransport(File(ConfigPaths().settings));

  final SettingsDocumentTransport _socket;
  final SettingsDocumentTransport _file;

  NativeSettingsStore? _store;
  BarSettings _settings = const BarSettings();
  String? _error;
  var _busy = false;
  var _usingSocket = false;
  var _disposed = false;

  BarSettings get settings => _settings;
  String? get error => _error;
  bool get busy => _busy;

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
    _busy = false;
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
