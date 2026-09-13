import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/control/control_server.dart';
import 'package:trickster/src/platform/control_socket.dart';

void main() {
  test('control server round-trips a request and cleans up', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-control-server',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/control.sock';
    // A stale socket path from a crashed bar must not break the bind.
    File(path).writeAsStringSync('stale');
    final server = ControlServer(
      socketPath: path,
      handler: (request) async => <String, Object?>{
        'ok': true,
        'echo': request['command'],
      },
    );
    await server.start();

    final reply = await controlRequest(<String, Object?>{
      'command': 'version',
    }, socketPath: path);
    expect(reply['ok'], isTrue);
    expect(reply['echo'], 'version');

    await server.dispose();
    expect(File(path).existsSync(), isFalse);
  });

  test('a handler error becomes a clean error reply', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-control-error',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/control.sock';
    final server = ControlServer(
      socketPath: path,
      handler: (_) => throw StateError('boom'),
    );
    await server.start();
    addTearDown(server.dispose);

    final reply = await controlRequest(<String, Object?>{
      'command': 'status',
    }, socketPath: path);
    expect(reply['ok'], isFalse);
    expect('${reply['error']}', contains('boom'));
  });

  test('a non-object request becomes a clean error reply', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-control-malformed',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/control.sock';
    final server = ControlServer(
      socketPath: path,
      handler: (_) => <String, Object?>{'ok': true},
    );
    await server.start();
    addTearDown(server.dispose);

    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    socket.write('[]\n');
    final reply = await utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .first;
    await socket.close();
    expect(reply, contains('false'));
  });
}
