import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/platform/control_socket.dart';

class _FakeControlServer {
  _FakeControlServer._(this._server, this.path);

  final ServerSocket _server;
  final String path;
  int revision = 1;
  String document = const BarSettings().encode();
  var rejectNextWrite = false;
  final commands = <String>[];

  static Future<_FakeControlServer> bind(Directory directory) async {
    final path = '${directory.path}/control.sock';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final fake = _FakeControlServer._(server, path);
    server.listen(fake._onConnection);
    return fake;
  }

  void _onConnection(Socket socket) {
    socket.listen((data) async {
      final line = utf8.decode(data).trim();
      if (line.isEmpty) {
        return;
      }
      final request = jsonDecode(line) as Map<String, Object?>;
      commands.add('${request['command']}');
      final Map<String, Object?> reply;
      switch (request['command']) {
        case 'settings.read':
          reply = <String, Object?>{
            'ok': true,
            'revision': revision,
            'document': document,
          };
        case 'settings.write':
          final expected = (request['expectedRevision'] as num?)?.toInt() ?? -1;
          if (rejectNextWrite || expected != revision) {
            rejectNextWrite = false;
            reply = <String, Object?>{
              'ok': false,
              'error': 'revision mismatch',
            };
          } else {
            revision += 1;
            document = '${request['document']}';
            reply = <String, Object?>{
              'ok': true,
              'revision': revision,
              'document': document,
            };
          }
        default:
          reply = <String, Object?>{'ok': false, 'error': 'unknown command'};
      }
      socket.write('${jsonEncode(reply)}\n');
      await socket.flush();
      await socket.close();
    }, onError: (_) {});
  }

  Future<void> dispose() => _server.close();
}

Future<Directory> _temporaryDir() async {
  final directory = await Directory.systemTemp.createTemp('trickster-control');
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

void main() {
  test('control socket path follows XDG_RUNTIME_DIR', () {
    expect(
      controlSocketPath(
        environment: const {'XDG_RUNTIME_DIR': '/run/user/1000'},
      ),
      '/run/user/1000/trickster/control.sock',
    );
    expect(
      controlSocketPath(environment: const {'XDG_RUNTIME_DIR': ''}),
      '/tmp/trickster/control.sock',
    );
  });

  test('socket transport round-trips settings documents', () async {
    final directory = await _temporaryDir();
    final server = await _FakeControlServer.bind(directory);
    addTearDown(server.dispose);
    final transport = SocketSettingsTransport(socketPath: server.path);

    final first = await transport.read();
    expect(first.revision, 1);
    expect(BarSettings.decode(first.json).revision, 1);

    final written = await transport.write(
      expectedRevision: 1,
      document: const BarSettings(
        revision: 2,
        accent: Color(0xffff0000),
      ).encode(),
    );
    expect(written.revision, 2);
    expect(BarSettings.decode(written.json).accent, const Color(0xffff0000));
  });

  test('the store retries once after a revision mismatch', () async {
    final directory = await _temporaryDir();
    final server = await _FakeControlServer.bind(directory);
    addTearDown(server.dispose);
    final store = NativeSettingsStore(
      SocketSettingsTransport(socketPath: server.path),
    );

    await store.read();
    server.rejectNextWrite = true;
    await store.write(const BarSettings(modules: ['clock']));

    expect(server.revision, 2);
    expect(
      server.commands.where((command) => command == 'settings.write'),
      hasLength(2),
    );
  });

  test('an absent socket is a clean error', () async {
    final directory = await _temporaryDir();
    final transport = SocketSettingsTransport(
      socketPath: '${directory.path}/missing.sock',
    );
    await expectLater(
      transport.read(),
      throwsA(
        isA<ControlSocketException>().having(
          (error) => error.message,
          'message',
          contains('unavailable'),
        ),
      ),
    );
  });

  test('a malformed reply is a clean error', () async {
    final directory = await _temporaryDir();
    final path = '${directory.path}/bad.sock';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    addTearDown(server.close);
    server.listen((socket) async {
      await socket.first;
      socket.write('not json\n');
      await socket.flush();
      await socket.close();
    });

    final transport = SocketSettingsTransport(socketPath: path);
    await expectLater(transport.read(), throwsA(isA<ControlSocketException>()));
  });
}
