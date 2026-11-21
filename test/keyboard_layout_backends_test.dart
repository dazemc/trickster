import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/keyboard_layout.dart';

Future<void> _waitUntil(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const _swayUs = '''
[{"identifier":"1:1:kbd","name":"kbd","type":"keyboard",
  "xkb_layout_names":["English (US)","Russian"],
  "xkb_active_layout_index":0,
  "xkb_active_layout_name":"English (US)"},
 {"identifier":"2:2:mouse","name":"mouse","type":"pointer"}]''';

const _swayRu = '''
[{"identifier":"1:1:kbd","name":"kbd","type":"keyboard",
  "xkb_layout_names":["English (US)","Russian"],
  "xkb_active_layout_index":1,
  "xkb_active_layout_name":"Russian"},
 {"identifier":"2:2:mouse","name":"mouse","type":"pointer"}]''';

Uint8List _i3Frame(int type, List<int> payload) {
  final header = Uint8List(14);
  header.setAll(0, <int>[0x69, 0x33, 0x2d, 0x69, 0x70, 0x63]);
  final view = ByteData.sublistView(header);
  view.setUint32(6, payload.length, Endian.little);
  view.setUint32(10, type, Endian.little);
  return Uint8List.fromList([...header, ...payload]);
}

class _FakeSwayServer {
  _FakeSwayServer._(this.path);

  final String path;
  final clients = <Socket>{};
  final commands = <int>[];
  var inputs = _swayUs;
  ServerSocket? _server;

  static Future<_FakeSwayServer> bind() async {
    final dir = await Directory.systemTemp.createTemp('trickster-sway');
    final server = _FakeSwayServer._('${dir.path}/sway.sock');
    server._server = await ServerSocket.bind(
      InternetAddress(server.path, type: InternetAddressType.unix),
      0,
    );
    server._server!.listen(server._accept);
    return server;
  }

  void _accept(Socket socket) {
    clients.add(socket);
    final buffer = <int>[];
    socket.listen(
      (data) {
        buffer.addAll(data);
        var consumed = 0;
        while (buffer.length - consumed >= 14) {
          if (buffer[consumed] != 0x69 ||
              buffer[consumed + 1] != 0x33 ||
              buffer[consumed + 2] != 0x2d ||
              buffer[consumed + 3] != 0x69) {
            buffer.clear();
            return;
          }
          final view = ByteData.sublistView(Uint8List.fromList(buffer));
          final length = view.getUint32(consumed + 6, Endian.little);
          if (buffer.length - consumed < 14 + length) {
            break;
          }
          final type = view.getUint32(consumed + 10, Endian.little);
          consumed += 14 + length;
          commands.add(type);
          if (type == 100) {
            socket.add(_i3Frame(100, utf8.encode(inputs)));
          }
        }
        if (consumed > 0) {
          buffer.removeRange(0, consumed);
        }
      },
      onError: (_) {},
      onDone: () => clients.remove(socket),
    );
  }

  void fireInputEvent() {
    for (final client in clients) {
      client.add(_i3Frame(0x80000015, utf8.encode('{"change":"xkb_layout"}')));
    }
  }

  Future<void> dropClients() async {
    for (final client in clients.toList()) {
      await client.close();
    }
  }

  Future<void> dispose() async {
    await dropClients();
    await _server?.close();
    await Directory(File(path).parent.path).delete(recursive: true);
  }
}

class _FakeNiriServer {
  _FakeNiriServer._(this.path);

  final String path;
  final clients = <Socket>{};
  var names = const ['us', 'ru'];
  var index = 0;
  ServerSocket? _server;

  static Future<_FakeNiriServer> bind() async {
    final dir = await Directory.systemTemp.createTemp('trickster-niri');
    final server = _FakeNiriServer._('${dir.path}/niri.sock');
    server._server = await ServerSocket.bind(
      InternetAddress(server.path, type: InternetAddressType.unix),
      0,
    );
    server._server!.listen(server._accept);
    return server;
  }

  void _accept(Socket socket) {
    clients.add(socket);
    socket.listen(
      (_) {},
      onError: (_) {},
      onDone: () => clients.remove(socket),
    );
    _sendLayouts(socket);
  }

  void _sendLayouts(Socket socket) {
    socket.add(
      utf8.encode(
        '${jsonEncode({
          'KeyboardLayoutsChanged': {
            'keyboard_layouts': {'names': names, 'current_idx': index},
          },
        })}\n',
      ),
    );
  }

  void fireSwitched(int next) {
    index = next;
    for (final client in clients) {
      client.add(
        utf8.encode(
          '${jsonEncode({
            'KeyboardLayoutSwitched': {'idx': next},
          })}\n',
        ),
      );
    }
  }

  Future<void> dropClients() async {
    for (final client in clients.toList()) {
      await client.close();
    }
  }

  Future<void> dispose() async {
    await dropClients();
    await _server?.close();
    await Directory(File(path).parent.path).delete(recursive: true);
  }
}

void main() {
  test('parses sway inputs and normalizes the active short code', () {
    final state = parseSwayInputs(jsonDecode(_swayUs));
    expect(state!.available, isTrue);
    expect(state.backend, 'sway');
    expect(state.active, 'US');
    expect(state.index, 0);
    expect(state.names, ['English (US)', 'Russian']);
  });

  test('sway prefers the first keyboard that publishes a layout', () {
    final state = parseSwayInputs(
      jsonDecode('''
      [{"type":"keyboard","name":"bare"},
       {"type":"keyboard","xkb_layout_names":["German"],"xkb_active_layout_index":0}]
    '''),
    );
    expect(state!.names, ['German']);
    expect(state.active, 'DE');
  });

  test('detectKeyboardLayoutBackend follows Hyprland, Sway, niri order', () {
    expect(
      detectKeyboardLayoutBackend(
        environment: {
          'HYPRLAND_INSTANCE_SIGNATURE': 'sig',
          'XDG_RUNTIME_DIR': '/run/user/1',
          'SWAYSOCK': '/tmp/sway',
        },
      ),
      isA<HyprlandKeyboardLayout>(),
    );
    expect(
      detectKeyboardLayoutBackend(environment: {'SWAYSOCK': '/tmp/sway'}),
      isA<SwayKeyboardLayout>(),
    );
    expect(
      detectKeyboardLayoutBackend(environment: {'NIRI_SOCKET': '/tmp/niri'}),
      isA<NiriKeyboardLayout>(),
    );
    expect(detectKeyboardLayoutBackend(environment: {}), isNull);
  });

  test('sway initial state and input event switch the layout', () async {
    final server = await _FakeSwayServer.bind();
    final backend = SwayKeyboardLayout(socketPath: server.path);
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
    expect(states.last.backend, 'sway');

    server.inputs = _swayRu;
    server.fireInputEvent();
    await _waitUntil(() => states.any((state) => state.active == 'RU'));
    expect(states.last.index, 1);
  });

  test('sway reconnects after the compositor socket drops', () async {
    final server = await _FakeSwayServer.bind();
    final backend = SwayKeyboardLayout(socketPath: server.path);
    final states = <KeyboardLayoutState>[];
    final subscription = backend.snapshots.listen(states.add);
    addTearDown(() async {
      await subscription.cancel();
      await backend.dispose();
      await server.dispose();
    });

    await backend.start();
    await _waitUntil(() => states.isNotEmpty);
    server.inputs = _swayRu;
    await server.dropClients();
    await _waitUntil(() => states.any((state) => state.active == 'RU'));
    expect(states.last.active, 'RU');
  });

  test('sway missing socket is unavailable', () async {
    final dir = await Directory.systemTemp.createTemp('trickster-sway-empty');
    addTearDown(() => dir.delete(recursive: true));
    final backend = SwayKeyboardLayout(socketPath: '${dir.path}/missing');
    final states = <KeyboardLayoutState>[];
    final subscription = backend.snapshots.listen(states.add);
    addTearDown(() async {
      await subscription.cancel();
      await backend.dispose();
    });

    await backend.start();
    await _waitUntil(() => states.isNotEmpty);
    expect(states.single.available, isFalse);
    expect(states.single.backend, 'sway');
  });

  test('niri initial state and switched event update the layout', () async {
    final server = await _FakeNiriServer.bind();
    final backend = NiriKeyboardLayout(socketPath: server.path);
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
    expect(states.last.names, ['us', 'ru']);

    server.fireSwitched(1);
    await _waitUntil(() => states.any((state) => state.active == 'RU'));
    expect(states.last.index, 1);
  });

  test('niri reconnects and replays the layout state', () async {
    final server = await _FakeNiriServer.bind();
    final backend = NiriKeyboardLayout(socketPath: server.path);
    final states = <KeyboardLayoutState>[];
    final subscription = backend.snapshots.listen(states.add);
    addTearDown(() async {
      await subscription.cancel();
      await backend.dispose();
      await server.dispose();
    });

    await backend.start();
    await _waitUntil(() => states.isNotEmpty);
    server.index = 1;
    await server.dropClients();
    await _waitUntil(() => states.any((state) => state.active == 'RU'));
    expect(states.last.active, 'RU');
  });

  test('niri missing socket is unavailable', () async {
    final dir = await Directory.systemTemp.createTemp('trickster-niri-empty');
    addTearDown(() => dir.delete(recursive: true));
    final backend = NiriKeyboardLayout(socketPath: '${dir.path}/missing');
    final states = <KeyboardLayoutState>[];
    final subscription = backend.snapshots.listen(states.add);
    addTearDown(() async {
      await subscription.cancel();
      await backend.dispose();
    });

    await backend.start();
    await _waitUntil(() => states.isNotEmpty);
    expect(states.single.available, isFalse);
    expect(states.single.backend, 'niri');
  });
}
