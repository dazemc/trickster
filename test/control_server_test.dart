import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/session.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/control/control_handler.dart';
import 'package:trickster/src/control/control_server.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';

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

  test('a second server neither steals nor removes a live control socket', ()
      async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-control-owner',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/control.sock';
    final first = ControlServer(
      socketPath: path,
      handler: (request) async => <String, Object?>{'ok': true, 'owner': 'first'},
    );
    expect(await first.start(), isTrue);
    addTearDown(first.dispose);

    final second = ControlServer(
      socketPath: path,
      handler: (request) async => <String, Object?>{'ok': true, 'owner': 'second'},
    );
    expect(await second.start(), isFalse);
    await second.dispose();

    // The first server still owns the path and answers after the second exits.
    expect(File(path).existsSync(), isTrue);
    final reply = await controlRequest(<String, Object?>{
      'command': 'version',
    }, socketPath: path);
    expect(reply['owner'], 'first');
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

  testWidgets('status reply json-encodes the configured session accent', (
    tester,
  ) async {
    // The status command never reads the transports; these paths are never
    // touched. Keeping I/O out of the fake-async test zone avoids a hang.
    final settings = FileSettingsTransport(File('settings.json'));
    final outputs = FileOutputsTransport(File('outputs.conf'));
    late final BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(
            create: (_) => SessionBloc(
              const SessionConfig(accent: Color(0xffd0bcff)),
            ),
          ),
          BlocProvider<SettingsBloc>(create: (_) => SettingsBloc()),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
        ],
        child: Builder(
          builder: (captured) {
            context = captured;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final reply = await handleControlRequest(
      context: context,
      settings: settings,
      outputs: outputs,
      reload: () => null,
      request: const <String, Object?>{'command': 'status'},
    );

    expect(reply['ok'], isTrue);
    expect(jsonEncode(reply), isA<String>());
    expect((reply['session'] as Map)['accent'], '#d0bcff');
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
