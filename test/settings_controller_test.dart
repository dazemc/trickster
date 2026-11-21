import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/settings/bloc.dart';

/// A bloc wired to no real socket, no real outputs file, and no real display:
/// tests must never wait on the live session.
SettingsAppBloc _bloc({
  required SettingsDocumentTransport socket,
  required Directory directory,
  File? settingsFile,
}) {
  return SettingsAppBloc(
    socket: socket,
    file: FileSettingsTransport(
      settingsFile ?? File('${directory.path}/unused-settings.json'),
    ),
    outputsSocket: SocketOutputsTransport(
      socketPath: '${directory.path}/no-bar.sock',
    ),
    outputsFile: FileOutputsTransport(File('${directory.path}/outputs.conf')),
    layerShell: _FakeLayerShell(),
  );
}

Future<void> _load(SettingsAppBloc bloc) async {
  bloc.add(const SettingsAppLoadRequested());
  await bloc.stream.firstWhere((state) => state.loaded);
}

Future<void> _save(SettingsAppBloc bloc, BarSettings settings) async {
  bloc.add(SettingsAppSaveRequested(settings));
  await bloc.stream.firstWhere((state) => !state.busy);
}

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell() : super(channel: const MethodChannel('test/trickster'));

  @override
  Future<List<LayerOutput>> outputs() async => const <LayerOutput>[];
}

class _GatedSettingsTransport implements SettingsDocumentTransport {
  final _read = Completer<SettingsDocument>();
  var reads = 0;

  @override
  Future<SettingsDocument> read() {
    reads += 1;
    return _read.future;
  }

  void complete(SettingsDocument document) => _read.complete(document);

  void fail(Object error) => _read.completeError(error);

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async => throw UnimplementedError();
}

class _GatedOutputsTransport implements OutputsDocumentTransport {
  final _read = Completer<String>();
  var reads = 0;

  @override
  Future<String> read() {
    reads += 1;
    return _read.future;
  }

  void complete(String document) => _read.complete(document);

  void fail(Object error) => _read.completeError(error);

  @override
  Future<String> write(String document) async => throw UnimplementedError();
}

class _GatedLayerShell extends LayerShell {
  _GatedLayerShell() : super(channel: const MethodChannel('test/trickster'));

  final _outputs = Completer<List<LayerOutput>>();
  var calls = 0;

  @override
  Future<List<LayerOutput>> outputs() {
    calls += 1;
    return _outputs.future;
  }

  void complete(List<LayerOutput> outputs) => _outputs.complete(outputs);

  void fail(Object error) => _outputs.completeError(error);
}

/// A fake bar control socket serving the settings document like the real
/// handler does, including revision conflicts.
class _FakeBar {
  _FakeBar._(this._server, this.path);

  final ServerSocket _server;
  final String path;
  final List<String> commands = <String>[];
  String document = const BarSettings(revision: 3).encode();
  int revision = 3;
  var _closed = false;

  /// Fails this many writes with a revision mismatch before succeeding.
  int conflicts = 0;

  static Future<_FakeBar> start() async {
    final directory = await Directory.systemTemp.createTemp('trickster-app');
    final path = '${directory.path}/control.sock';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final bar = _FakeBar._(server, path);
    server.listen(bar._handle);
    return bar;
  }

  Future<void> _handle(Socket socket) async {
    final lines = utf8.decoder.bind(socket).transform(const LineSplitter());
    await for (final line in lines) {
      final request = (jsonDecode(line) as Map).cast<String, Object?>();
      final command = request['command'];
      commands.add('$command');
      if (command == 'settings.read') {
        socket.write(
          '${jsonEncode({'ok': true, 'revision': revision, 'document': document})}\n',
        );
      } else if (command == 'settings.write') {
        final expected = request['expectedRevision'];
        final payload = request['document'];
        if (conflicts > 0) {
          conflicts -= 1;
          revision += 1;
          document = const BarSettings(
            revision: 4,
            accent: Color(0xff00ff00),
          ).encode();
          socket.write(
            '${jsonEncode({'ok': false, 'error': 'settings revision $revision != expected $expected'})}\n',
          );
        } else if (expected != revision) {
          socket.write(
            '${jsonEncode({'ok': false, 'error': 'settings revision $revision != expected $expected'})}\n',
          );
        } else {
          revision += 1;
          document = payload! as String;
          socket.write(
            '${jsonEncode({'ok': true, 'revision': revision, 'document': document})}\n',
          );
        }
      } else {
        socket.write(
          '${jsonEncode({'ok': false, 'error': 'unknown command: $command'})}\n',
        );
      }
      await socket.flush();
    }
  }

  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _server.close();
    final directory = Directory(path).parent;
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  const accent = Color(0xffd0bcff);

  test('round-trips the document over the bar socket', () async {
    final bar = await _FakeBar.start();
    addTearDown(bar.dispose);
    final bloc = _bloc(
      socket: SocketSettingsTransport(socketPath: bar.path),
      directory: Directory.systemTemp,
    );
    addTearDown(bloc.close);

    await _load(bloc);
    expect(bloc.usingSocket, isTrue);
    expect(bloc.error, isNull);
    expect(bloc.settings.revision, 3);

    await _save(bloc, bloc.settings.copyWith(accent: accent));
    expect(bloc.error, isNull);
    expect(bloc.settings.accent, accent);
    expect(bloc.settings.revision, 4);
    expect(bar.revision, 4);
    expect(bar.document, contains('d0bcff'));
    // The write response is the new document; no read-after-write round trip.
    expect(
      bar.commands.where((command) => command == 'settings.read'),
      hasLength(1),
    );
    expect(
      bar.commands.where((command) => command == 'settings.write'),
      hasLength(1),
    );
  });

  test(
    'surfaces a revision conflict and keeps the latest disk document',
    () async {
      final bar = await _FakeBar.start();
      addTearDown(bar.dispose);
      final bloc = _bloc(
        socket: SocketSettingsTransport(socketPath: bar.path),
        directory: Directory.systemTemp,
      );
      addTearDown(bloc.close);

      await _load(bloc);
      bar.conflicts = 1;
      await _save(bloc, bloc.settings.copyWith(accent: accent));

      expect(bloc.error, contains('changed elsewhere'));
      expect(bloc.settings.accent, const Color(0xff00ff00));
      expect(bloc.settings.revision, 4);
      expect(bar.revision, 4);
      expect(bar.document, contains('00ff00'));
      expect(bar.document, isNot(contains('d0bcff')));
    },
  );

  test(
    'a save after a conflict writes against the reloaded revision',
    () async {
      final bar = await _FakeBar.start();
      addTearDown(bar.dispose);
      final bloc = _bloc(
        socket: SocketSettingsTransport(socketPath: bar.path),
        directory: Directory.systemTemp,
      );
      addTearDown(bloc.close);

      await _load(bloc);
      bar.conflicts = 1;
      await _save(bloc, bloc.settings.copyWith(accent: accent));
      expect(bloc.error, contains('changed elsewhere'));

      // The user retries after seeing the loaded document; this is a fresh
      // snapshot at the adopted revision, not a silent resend.
      await _save(
        bloc,
        bloc.settings.copyWith(accent: const Color(0xff112233)),
      );
      expect(bloc.error, isNull);
      expect(bar.revision, 5);
      expect(bar.document, contains('112233'));
    },
  );

  test('initial document and output reads start together', () async {
    final settings = _GatedSettingsTransport();
    final outputs = _GatedOutputsTransport();
    final layer = _GatedLayerShell();
    final bloc = SettingsAppBloc(
      socket: settings,
      file: FileSettingsTransport(File('/unused/settings.json')),
      outputsSocket: outputs,
      outputsFile: FileOutputsTransport(File('/unused/outputs.conf')),
      layerShell: layer,
    );
    addTearDown(bloc.close);

    bloc.add(const SettingsAppLoadRequested());
    await _waitFor(
      () => settings.reads == 1 && outputs.reads == 1 && layer.calls == 1,
    );
    expect(bloc.loaded, isFalse);

    final loaded = bloc.stream.firstWhere((state) => state.loaded);
    outputs.complete(const OutputsConfig().encode());
    layer.complete(const <LayerOutput>[
      LayerOutput(name: 'eDP-1', width: 1920, height: 1080),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(bloc.loaded, isFalse);

    settings.complete(
      SettingsDocument(
        revision: 2,
        json: const BarSettings(revision: 2).encode(),
      ),
    );
    final state = await loaded;
    expect(state.settings.revision, 2);
    expect(state.availableOutputs.single.name, 'eDP-1');
    expect(state.error, isNull);
    expect(state.outputsError, isNull);
  });

  test('initial read errors stay per field', () async {
    final settings = _GatedSettingsTransport();
    final outputs = _GatedOutputsTransport();
    final layer = _GatedLayerShell();
    final bloc = SettingsAppBloc(
      socket: settings,
      file: FileSettingsTransport(File('/unused/settings.json')),
      outputsSocket: outputs,
      outputsFile: FileOutputsTransport(File('/unused/outputs.conf')),
      layerShell: layer,
    );
    addTearDown(bloc.close);

    bloc.add(const SettingsAppLoadRequested());
    await _waitFor(
      () => settings.reads == 1 && outputs.reads == 1 && layer.calls == 1,
    );
    final loaded = bloc.stream.firstWhere((state) => state.loaded);
    settings.fail(StateError('settings down'));
    outputs.fail(StateError('outputs down'));
    layer.complete(const <LayerOutput>[]);

    final state = await loaded;
    expect(state.loaded, isTrue);
    expect(state.error, contains('settings down'));
    expect(state.outputsError, contains('outputs down'));
    expect(state.availableOutputs, isEmpty);
  });

  test('falls back to the file when no bar answers', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-file');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings.json')
      ..writeAsStringSync(const BarSettings(revision: 7).encode());
    final bloc = _bloc(
      socket: SocketSettingsTransport(
        socketPath: '${directory.path}/gone.sock',
      ),
      directory: directory,
      settingsFile: file,
    );
    addTearDown(bloc.close);

    await _load(bloc);
    expect(bloc.usingSocket, isFalse);
    expect(bloc.error, isNull);
    expect(bloc.settings.revision, 7);

    await _save(bloc, bloc.settings.copyWith(accent: accent));
    expect(bloc.error, isNull);
    expect(file.readAsStringSync(), contains('d0bcff'));
  });

  test('a save falls back to the file after the bar exits', () async {
    final bar = await _FakeBar.start();
    addTearDown(bar.dispose);
    final directory = await Directory.systemTemp.createTemp(
      'trickster-fallback',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/settings.json')
      ..writeAsStringSync(bar.document);
    final bloc = _bloc(
      socket: SocketSettingsTransport(socketPath: bar.path),
      directory: directory,
      settingsFile: file,
    );
    addTearDown(bloc.close);

    await _load(bloc);
    expect(bloc.usingSocket, isTrue);
    expect(bloc.settings.revision, 3);

    await bar.dispose();
    await _save(bloc, bloc.settings.copyWith(accent: accent));

    expect(bloc.error, isNull);
    expect(bloc.usingSocket, isFalse);
    expect(bloc.settings.revision, 4);
    expect(bloc.settings.accent, accent);
    final saved = BarSettings.decode(file.readAsStringSync());
    expect(saved.revision, 4);
    expect(saved.accent, accent);
    expect(File('${file.path}.prev').existsSync(), isTrue);
    expect(File('${file.path}.tmp').existsSync(), isFalse);

    await _save(bloc, bloc.settings.copyWith(accent: const Color(0xff00ff00)));
    expect(bloc.error, isNull);
    expect(bloc.usingSocket, isFalse);
    expect(bloc.settings.revision, 5);
    expect(BarSettings.decode(file.readAsStringSync()).revision, 5);
  });
}
