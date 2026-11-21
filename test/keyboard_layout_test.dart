import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/keyboard_layout.dart';
import 'package:trickster/src/state/keyboard_layout_bloc.dart';

const _devicesUs = '''
{"keyboards":[
 {"name":"keyboard-a","main":true,"layout":"us,ru","active_layout_index":0,"active_keymap":"English (US)"},
 {"name":"keyboard-b","main":false,"layout":"de","active_layout_index":0,"active_keymap":"German"}
]}''';

const _devicesRu = '''
{"keyboards":[
 {"name":"keyboard-a","main":true,"layout":"us,ru","active_layout_index":1,"active_keymap":"Russian"}
]}''';

const _devicesMainSecond = '''
{"keyboards":[
 {"name":"keyboard-a","main":false,"layout":"us","active_layout_index":0,"active_keymap":"English (US)"},
 {"name":"keyboard-b","main":true,"layout":"de","active_layout_index":0,"active_keymap":"German"}
]}''';

class _FakeHyprlandKeyboardServer {
  _FakeHyprlandKeyboardServer._(this.dir, this._ownsDir);

  final String dir;
  final bool _ownsDir;
  final replies = <String, List<int>>{};
  final commands = <String>[];
  ServerSocket? _requests;
  ServerSocket? _events;
  final _eventSinks = <Socket>{};
  final _clients = <Socket>{};

  static Future<_FakeHyprlandKeyboardServer> bind() async {
    final path = (await Directory.systemTemp.createTemp(
      'trickster-keyboard',
    )).path;
    final server = _FakeHyprlandKeyboardServer._(path, true)
      ..replies['j/devices'] = utf8.encode(_devicesUs);
    server._requests = await ServerSocket.bind(
      InternetAddress('$path/.socket.sock', type: InternetAddressType.unix),
      0,
    );
    server._requests!.listen(server._serveRequest);
    server._events = await ServerSocket.bind(
      InternetAddress('$path/.socket2.sock', type: InternetAddressType.unix),
      0,
    );
    server._events!.listen((socket) {
      server._eventSinks.add(socket);
      socket.done.then((_) => server._eventSinks.remove(socket));
    });
    return server;
  }

  Future<void> _serveRequest(Socket client) async {
    _clients.add(client);
    try {
      final command = utf8.decode(await client.first);
      commands.add(command);
      final reply = replies[command];
      if (reply != null) {
        client.add(reply);
        await client.flush();
      }
      await client.close();
    } on Object {
      try {
        await client.close();
      } on Object {
        // Teardown races are not test failures.
      }
    }
  }

  Future<void> fireEvent(String layoutName) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_eventSinks.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('backend never connected to .socket2.sock');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final line = utf8.encode('activelayout>>keyboard-a,$layoutName\n');
    for (final sink in _eventSinks) {
      sink.add(line);
    }
  }

  Future<void> dropEvents() async {
    for (final sink in _eventSinks.toList()) {
      await sink.close();
    }
  }

  Future<void> dispose() async {
    for (final client in _clients) {
      try {
        await client.close();
      } on Object {
        // Already gone.
      }
    }
    for (final sink in _eventSinks.toList()) {
      try {
        await sink.close();
      } on Object {
        // Already gone.
      }
    }
    await _requests?.close();
    await _events?.close();
    if (_ownsDir) {
      await Directory(dir).delete(recursive: true);
    }
  }
}

Future<void> _waitUntil(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('parses the main keyboard and its active layout', () {
    final state = parseHyprlandDevices(jsonDecode(_devicesUs));
    expect(state, isNotNull);
    expect(state!.available, isTrue);
    expect(state.backend, 'hyprland');
    expect(state.active, 'US');
    expect(state.index, 0);
    expect(state.names, ['us', 'ru']);
  });

  test('prefers the main keyboard over the first keyboard', () {
    final state = parseHyprlandDevices(jsonDecode(_devicesMainSecond));
    expect(state!.active, 'DE');
    expect(state.names, ['de']);
  });

  test('missing keyboards or malformed documents are unavailable', () {
    expect(
      parseHyprlandDevices(const <String, dynamic>{}),
      const KeyboardLayoutState(backend: 'hyprland'),
    );
    expect(parseHyprlandDevices(null), isNull);
    expect(parseHyprlandDevices('bad'), isNull);
    expect(
      parseHyprlandDevices(const {'keyboards': <Object?>[]}),
      const KeyboardLayoutState(backend: 'hyprland'),
    );
  });

  test('queries devices once and emits the initial layout', () async {
    final server = await _FakeHyprlandKeyboardServer.bind();
    final backend = HyprlandKeyboardLayout(socketDir: server.dir);
    final states = <KeyboardLayoutState>[];
    final subscription = backend.snapshots.listen(states.add);
    addTearDown(() async {
      await subscription.cancel();
      await backend.dispose();
      await server.dispose();
    });

    await backend.start();
    await _waitUntil(() => states.isNotEmpty);
    expect(states.single.active, 'US');
    expect(states.single.index, 0);
    expect(states.single.names, ['us', 'ru']);
    expect(server.commands, contains('j/devices'));
  });

  test('activelayout events re-query and deduplicate', () async {
    final server = await _FakeHyprlandKeyboardServer.bind();
    final backend = HyprlandKeyboardLayout(socketDir: server.dir);
    final states = <KeyboardLayoutState>[];
    final subscription = backend.snapshots.listen(states.add);
    addTearDown(() async {
      await subscription.cancel();
      await backend.dispose();
      await server.dispose();
    });

    await backend.start();
    await _waitUntil(() => states.isNotEmpty);
    expect(states.last.active, 'US');

    server.replies['j/devices'] = utf8.encode(_devicesRu);
    await server.fireEvent('Russian');
    await _waitUntil(() => states.any((state) => state.active == 'RU'));
    final count = states.length;

    await server.fireEvent('Russian');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(states.length, count);
  });

  test('reconnects after the event socket drops', () async {
    final server = await _FakeHyprlandKeyboardServer.bind();
    final backend = HyprlandKeyboardLayout(socketDir: server.dir);
    final states = <KeyboardLayoutState>[];
    final subscription = backend.snapshots.listen(states.add);
    addTearDown(() async {
      await subscription.cancel();
      await backend.dispose();
      await server.dispose();
    });

    await backend.start();
    await _waitUntil(() => states.isNotEmpty);
    server.replies['j/devices'] = utf8.encode(_devicesRu);
    await server.dropEvents();
    await _waitUntil(
      () => states.any((state) => state.active == 'RU'),
      // The re-query on reconnect observes the updated devices document.
    );
    expect(states.last.active, 'RU');
  });

  test(
    'a missing socket emits unavailable without opening a second path',
    () async {
      final dir = (await Directory.systemTemp.createTemp(
        'trickster-keyboard-empty',
      )).path;
      addTearDown(() => Directory(dir).delete(recursive: true));
      final backend = HyprlandKeyboardLayout(socketDir: dir);
      final states = <KeyboardLayoutState>[];
      final subscription = backend.snapshots.listen(states.add);
      addTearDown(() async {
        await subscription.cancel();
        await backend.dispose();
      });

      await backend.start();
      await _waitUntil(() => states.isNotEmpty);
      expect(states.single.available, isFalse);
      expect(states.single.names, isEmpty);
      expect(states.single.backend, 'hyprland');
    },
  );

  test('bloc stop is terminal and disposes the backend once', () async {
    final backend = _FakeKeyboardBackend();
    final bloc = KeyboardLayoutBloc(backend: backend);
    final seen = <KeyboardLayoutState>[];
    final subscription = bloc.stream.listen(seen.add);

    bloc.add(const KeyboardLayoutStarted());
    await pumpEventQueue();
    backend.controller.add(
      const KeyboardLayoutState(
        available: true,
        backend: 'hyprland',
        active: 'US',
        index: 0,
        names: ['us'],
      ),
    );
    await pumpEventQueue();
    expect(seen.single.active, 'US');

    bloc.add(const KeyboardLayoutStopped());
    await pumpEventQueue();
    expect(backend.disposed, isTrue);
    expect(backend.controller.isClosed, isTrue);

    bloc.add(
      const KeyboardLayoutChanged(
        KeyboardLayoutState(available: true, active: 'RU'),
      ),
    );
    bloc.add(const KeyboardLayoutStarted());
    await pumpEventQueue();
    expect(seen, hasLength(1));
    await bloc.close();
    expect(backend.disposeCount, 1);
    await subscription.cancel();
  });
}

class _FakeKeyboardBackend implements KeyboardLayoutBackend {
  final controller = StreamController<KeyboardLayoutState>.broadcast();
  var disposed = false;
  var disposeCount = 0;

  @override
  Stream<KeyboardLayoutState> get snapshots => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    disposeCount += 1;
    await controller.close();
  }
}
