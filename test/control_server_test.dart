import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/session.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/control/control_handler.dart';
import 'package:trickster/src/control/control_server.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/services/disk.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/ram.dart';
import 'package:trickster/src/services/temperature.dart';
import 'package:trickster/src/state/disk_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/ram_bloc.dart';
import 'package:trickster/src/state/seat_idle_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/temperature_bloc.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';

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

  test(
    'a second server neither steals nor removes a live control socket',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'trickster-control-owner',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/control.sock';
      final first = ControlServer(
        socketPath: path,
        handler: (request) async => <String, Object?>{
          'ok': true,
          'owner': 'first',
        },
      );
      expect(await first.start(), isTrue);
      addTearDown(first.dispose);

      final second = ControlServer(
        socketPath: path,
        handler: (request) async => <String, Object?>{
          'ok': true,
          'owner': 'second',
        },
      );
      expect(await second.start(), isFalse);
      await second.dispose();

      // The first server still owns the path and answers after the second exits.
      expect(File(path).existsSync(), isTrue);
      final reply = await controlRequest(<String, Object?>{
        'command': 'version',
      }, socketPath: path);
      expect(reply['owner'], 'first');
    },
  );

  test('an accept listener error rebinds and serves requests again', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-control-retry',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/control.sock';
    late void Function(Object, StackTrace) failListener;
    var listens = 0;
    final server = ControlServer(
      socketPath: path,
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 40),
      handler: (request) async => <String, Object?>{
        'ok': true,
        'listens': listens,
        'echo': request['command'],
      },
      acceptListener: (server, onSocket, onError, onDone) {
        listens += 1;
        failListener = onError;
        return server.listen(onSocket, onError: onError, onDone: onDone);
      },
    );
    addTearDown(server.dispose);
    expect(await server.start(), isTrue);

    failListener(StateError('accept failed'), StackTrace.current);
    await _waitUntil(() => listens == 2);

    expect(server.hasPendingRetry, isFalse);
    final reply = await controlRequest(<String, Object?>{
      'command': 'version',
    }, socketPath: path);
    expect(reply['ok'], isTrue);
    expect(reply['listens'], 2);
    expect(reply['echo'], 'version');
  });

  test('a closed accept stream rebinds and serves requests again', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-control-done',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/control.sock';
    late void Function() closeListener;
    var listens = 0;
    final server = ControlServer(
      socketPath: path,
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 40),
      handler: (_) async => <String, Object?>{'ok': true, 'listens': listens},
      acceptListener: (server, onSocket, onError, onDone) {
        listens += 1;
        closeListener = onDone;
        return server.listen(onSocket, onError: onError, onDone: onDone);
      },
    );
    addTearDown(server.dispose);
    expect(await server.start(), isTrue);

    closeListener();
    await _waitUntil(() => listens == 2);

    final reply = await controlRequest(<String, Object?>{
      'command': 'version',
    }, socketPath: path);
    expect(reply['listens'], 2);
  });

  test('dispose cancels a pending retry and removes the owned path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-control-retry-dispose',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/control.sock';
    late void Function(Object, StackTrace) failListener;
    var listens = 0;
    final server = ControlServer(
      socketPath: path,
      retryDelay: const Duration(milliseconds: 200),
      retryDelayMax: const Duration(seconds: 1),
      handler: (_) async => <String, Object?>{'ok': true},
      acceptListener: (server, onSocket, onError, onDone) {
        listens += 1;
        failListener = onError;
        return server.listen(onSocket, onError: onError, onDone: onDone);
      },
    );
    addTearDown(server.dispose);
    expect(await server.start(), isTrue);

    failListener(StateError('accept failed'), StackTrace.current);
    await _waitUntil(() => server.hasPendingRetry);

    await server.dispose();
    expect(server.hasPendingRetry, isFalse);
    expect(File(path).existsSync(), isFalse);

    // A cancelled timer must not resurrect the socket after its delay.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(File(path).existsSync(), isFalse);
    expect(listens, 1);
    await expectLater(
      controlRequest(<String, Object?>{'command': 'version'}, socketPath: path),
      throwsA(isA<ControlSocketException>()),
    );
  });

  test('dispose during bind closes the new listener', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-control-bind-race',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/control.sock';
    late final ControlServer server;
    Future<void>? disposing;
    server = ControlServer(
      socketPath: path,
      handler: (_) async => <String, Object?>{'ok': true},
      acceptListener: (socket, onSocket, onError, onDone) {
        final subscription = socket.listen(
          onSocket,
          onError: onError,
          onDone: onDone,
        );
        disposing ??= server.dispose();
        return subscription;
      },
    );
    addTearDown(server.dispose);

    expect(await server.start(), isFalse);
    await disposing;
    expect(server.hasPendingRetry, isFalse);
    expect(File(path).existsSync(), isFalse);
    await expectLater(
      controlRequest(<String, Object?>{'command': 'version'}, socketPath: path),
      throwsA(isA<ControlSocketException>()),
    );
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
            create: (_) =>
                SessionBloc(const SessionConfig(accent: Color(0xffd0bcff))),
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

  testWidgets('status exposes the sampled wallpaper accent', (tester) async {
    final settings = FileSettingsTransport(File('settings.json'));
    final outputs = FileOutputsTransport(File('outputs.conf'));
    late final BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(create: (_) => SessionBloc()),
          BlocProvider<SettingsBloc>(create: (_) => SettingsBloc()),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
          BlocProvider<WallpaperAccentBloc>(
            create: (_) => WallpaperAccentBloc(
              watch: false,
              initial: const WallpaperAccentState(
                enabled: true,
                color: Color(0xff39445f),
                accents: <String, Color?>{'HDMI-A-1': Color(0xff4e4c65)},
              ),
            ),
          ),
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

    final wallpaper = (reply['state'] as Map)['wallpaper'] as Map;
    expect(wallpaper['enabled'], isTrue);
    expect(wallpaper['color'], '#39445f');
    expect((wallpaper['accents'] as Map)['HDMI-A-1'], '#4e4c65');
    expect(jsonEncode(reply), isA<String>());
  });

  testWidgets('status exposes seat idle only when a sampler is configured', (
    tester,
  ) async {
    final settings = FileSettingsTransport(File('settings.json'));
    final outputs = FileOutputsTransport(File('outputs.conf'));
    late final BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(create: (_) => SessionBloc()),
          BlocProvider<SettingsBloc>(
            create: (_) => SettingsBloc(const BarSettings(modules: ['cpu'])),
          ),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
          BlocProvider<SeatIdleBloc>(
            create: (_) => SeatIdleBloc(
              initial: const SeatIdleState(idle: true),
              changes: () => const Stream<bool>.empty(),
            ),
          ),
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

    final state = reply['state']! as Map<String, Object?>;
    expect(state['seat_idle'], {'idle': true});
    expect(jsonEncode(reply), isA<String>());
  });

  testWidgets('status exposes the RAM sample and its idle gate', (
    tester,
  ) async {
    final settings = FileSettingsTransport(File('settings.json'));
    final outputs = FileOutputsTransport(File('outputs.conf'));
    late final BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(create: (_) => SessionBloc()),
          BlocProvider<SettingsBloc>(
            create: (_) => SettingsBloc(const BarSettings(modules: ['ram'])),
          ),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
          BlocProvider<RamBloc>(
            create: (_) => RamBloc(
              initial: const RamSample(
                usedBytes: 6 * 1024 * 1024,
                totalBytes: 8 * 1024 * 1024,
                history: [0.5, 0.75],
              ),
            ),
          ),
          BlocProvider<SeatIdleBloc>(
            create: (_) => SeatIdleBloc(
              initial: const SeatIdleState(idle: false),
              changes: () => const Stream<bool>.empty(),
            ),
          ),
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

    final state = reply['state']! as Map<String, Object?>;
    expect(state['ram'], {
      'current': 0.75,
      'used_bytes': 6 * 1024 * 1024,
      'total_bytes': 8 * 1024 * 1024,
      'history': [0.5, 0.75],
    });
    expect(state['seat_idle'], {'idle': false});
    expect(jsonEncode(reply), isA<String>());
  });

  testWidgets('status carries VRAM inside the shared gpu state', (
    tester,
  ) async {
    final settings = FileSettingsTransport(File('settings.json'));
    final outputs = FileOutputsTransport(File('outputs.conf'));
    late final BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(create: (_) => SessionBloc()),
          BlocProvider<SettingsBloc>(
            create: (_) => SettingsBloc(const BarSettings(modules: ['vram'])),
          ),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
          BlocProvider<GpuBloc>(
            create: (_) => GpuBloc(
              initial: const GpuState([
                GpuLoad(
                  id: 'card0',
                  label: 'AMD0',
                  usage: 0.4,
                  history: [0.4],
                  memoryUsedBytes: 500,
                  memoryTotalBytes: 1000,
                  memoryHistory: [0.5],
                ),
              ]),
            ),
          ),
          BlocProvider<SeatIdleBloc>(
            create: (_) => SeatIdleBloc(
              initial: const SeatIdleState(idle: false),
              changes: () => const Stream<bool>.empty(),
            ),
          ),
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

    final state = reply['state']! as Map<String, Object?>;
    expect(state.containsKey('vram'), isFalse);
    final gpu = (state['gpu']! as Map<String, Object?>)['gpus']! as List;
    final load = gpu.single as Map<String, Object?>;
    expect(load['memory_used_bytes'], 500);
    expect(load['memory_total_bytes'], 1000);
    expect(load['memory_history'], [0.5]);
    expect(state['seat_idle'], {'idle': false});
    expect(jsonEncode(reply), isA<String>());
  });

  testWidgets('status exposes the temperature sample and its idle gate', (
    tester,
  ) async {
    final settings = FileSettingsTransport(File('settings.json'));
    final outputs = FileOutputsTransport(File('outputs.conf'));
    late final BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(create: (_) => SessionBloc()),
          BlocProvider<SettingsBloc>(
            create: (_) =>
                SettingsBloc(const BarSettings(modules: ['temperature'])),
          ),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
          BlocProvider<TemperatureBloc>(
            create: (_) => TemperatureBloc(
              initial: const TemperatureSample(
                celsius: 55,
                label: 'Tctl',
                chip: 'k10temp',
                isCpu: true,
                history: [50, 55],
              ),
            ),
          ),
          BlocProvider<SeatIdleBloc>(
            create: (_) => SeatIdleBloc(
              initial: const SeatIdleState(idle: false),
              changes: () => const Stream<bool>.empty(),
            ),
          ),
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

    final state = reply['state']! as Map<String, Object?>;
    expect(state['temperature'], {
      'current': 55.0,
      'label': 'Tctl',
      'chip': 'k10temp',
      'is_cpu': true,
      'history': [50.0, 55.0],
    });
    expect(state['seat_idle'], {'idle': false});
    expect(jsonEncode(reply), isA<String>());
  });

  testWidgets('status exposes the disk sample and its idle gate', (
    tester,
  ) async {
    final settings = FileSettingsTransport(File('settings.json'));
    final outputs = FileOutputsTransport(File('outputs.conf'));
    late final BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(create: (_) => SessionBloc()),
          BlocProvider<SettingsBloc>(
            create: (_) => SettingsBloc(const BarSettings(modules: ['disk'])),
          ),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
          BlocProvider<DiskBloc>(
            create: (_) => DiskBloc(
              initial: const DiskSample(
                path: '/',
                usedBytes: 600,
                totalBytes: 1000,
                freeBytes: 300,
              ),
            ),
          ),
          BlocProvider<SeatIdleBloc>(
            create: (_) => SeatIdleBloc(
              initial: const SeatIdleState(idle: false),
              changes: () => const Stream<bool>.empty(),
            ),
          ),
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

    final state = reply['state']! as Map<String, Object?>;
    expect(state['disk'], {
      'path': '/',
      'used_bytes': 600,
      'total_bytes': 1000,
      'free_bytes': 300,
      'fraction': 0.6,
    });
    expect(state['seat_idle'], {'idle': false});
    expect(jsonEncode(reply), isA<String>());
  });

  testWidgets('status does not create the idle service when it is unused', (
    tester,
  ) async {
    final settings = FileSettingsTransport(File('settings.json'));
    final outputs = FileOutputsTransport(File('outputs.conf'));
    late final BuildContext context;
    var created = 0;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SessionBloc>(create: (_) => SessionBloc()),
          BlocProvider<SettingsBloc>(
            create: (_) => SettingsBloc(const BarSettings(modules: ['clock'])),
          ),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
          BlocProvider<SeatIdleBloc>(
            create: (_) {
              created += 1;
              return SeatIdleBloc(changes: () => const Stream<bool>.empty());
            },
          ),
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

    expect(
      (reply['state']! as Map<String, Object?>).containsKey('seat_idle'),
      isFalse,
    );
    expect(created, 0);
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

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before the timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
