import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/status_notifier_models.dart';
import 'package:trickster/src/services/status_notifier_protocol.dart';
import 'package:trickster/src/services/status_notifier_worker.dart';
import 'package:trickster/src/services/status_notifier_worker_proxy.dart';
import 'package:trickster/src/services/tray_icon_decoder.dart';
import 'package:trickster/src/state/tray_bloc.dart';

class _FakeWorker {
  _FakeWorker() {
    _commandSubscription = _commands.listen(
      (message) => sent.add((message! as List<Object?>).cast<Object?>()),
    );
  }

  final ReceivePort _commands = ReceivePort();
  final StreamController<Object?> _events = StreamController<Object?>.broadcast(
    sync: true,
  );
  final StreamController<Object?> _errors = StreamController<Object?>.broadcast(
    sync: true,
  );
  final StreamController<Object?> _exits = StreamController<Object?>.broadcast(
    sync: true,
  );
  late final StreamSubscription<Object?> _commandSubscription;
  final List<List<Object?>> sent = <List<Object?>>[];
  var killed = false;
  var closed = false;

  StatusNotifierWorkerConnection get connection =>
      StatusNotifierWorkerConnection(
        commands: Future<SendPort>.value(_commands.sendPort),
        events: _events.stream,
        errors: _errors.stream,
        exits: _exits.stream,
        kill: () => killed = true,
        close: () {
          if (closed) {
            return;
          }
          closed = true;
          unawaited(_commandSubscription.cancel());
          _commands.close();
          _events.close();
          _errors.close();
          _exits.close();
        },
      );

  void reply(int index, {bool ok = true, Object? result, String? error}) {
    final command = sent[index];
    _events.add(
      ok
          ? <Object?>[command[0], true, result]
          : <Object?>[command[0], false, error ?? 'worker error', 'stack'],
    );
  }

  void state(List<StatusNotifierSnapshotItem> items) {
    _events.add(StatusNotifierSnapshot(items).toMessage());
  }
}

class _FakeIconDecoder {
  final Map<String, Completer<SystemTrayIconPixmap?>> calls =
      <String, Completer<SystemTrayIconPixmap?>>{};
  final Map<String, int> counts = <String, int>{};

  Future<SystemTrayIconPixmap?> decode(String path) {
    counts[path] = (counts[path] ?? 0) + 1;
    return (calls[path] ??= Completer<SystemTrayIconPixmap?>()).future;
  }
}

class _Harness {
  _Harness({StatusNotifierStartPayload? startPayload}) {
    proxy = StatusNotifierWorkerProxy(
      spawner: _spawn,
      startPayload: startPayload,
      iconDecoder: TrayIconDecoder(decode: icons.decode),
      requestTimeout: const Duration(milliseconds: 500),
      startupTimeout: const Duration(milliseconds: 500),
      disposeTimeout: const Duration(milliseconds: 20),
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 20),
    );
  }

  final _FakeIconDecoder icons = _FakeIconDecoder();
  late final StatusNotifierWorkerProxy proxy;
  late _FakeWorker worker;
  var spawns = 0;

  Future<StatusNotifierWorkerConnection> _spawn() async {
    spawns += 1;
    worker = _FakeWorker();
    return worker.connection;
  }

  Future<void> start() async {
    final started = proxy.start();
    await pumpEventQueue();
    final command = await _waitCommand(worker, 0);
    expect(command[1], StatusNotifierWorkerOperation.start.index);
    worker.reply(
      0,
      result: const StatusNotifierStartResult(
        isolateName: 'trickster-sni-worker',
        protocolVersion: StatusNotifierProtocolLimits.protocolVersion,
      ).toJson(),
    );
    await started;
  }
}

Future<List<Object?>> _waitCommand(_FakeWorker worker, int index) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (worker.sent.length <= index) {
    if (DateTime.now().isAfter(deadline)) {
      fail('StatusNotifier worker command $index was not sent');
    }
    await Future<void>.delayed(Duration.zero);
  }
  return worker.sent[index];
}

StatusNotifierSnapshotItem _item({
  String id = 'item',
  String title = 'Item',
  StatusNotifierIcon? icon,
  bool menuAvailable = false,
  String menuPath = '',
}) {
  return StatusNotifierSnapshotItem(
    id: id,
    title: title,
    status: SystemTrayStatus.active,
    iconName: 'icon',
    iconThemePath: '/tmp/icons',
    icon: icon ?? StatusNotifierIcon.none(),
    menuAvailable: menuAvailable,
    primaryOpensMenu: false,
    menuPath: menuPath,
  );
}

StatusNotifierIcon _rgba({int width = 2, int height = 1}) {
  return StatusNotifierIcon.rgba(
    width: width,
    height: height,
    digest: 7,
    rgba: Uint8List.fromList(<int>[
      for (var i = 0; i < width * height * 4; i++) i & 0xff,
    ]),
  );
}

SystemTrayMenuEntry _menuEntry(int id, String label) {
  return SystemTrayMenuEntry(
    id: id,
    label: label,
    enabled: true,
    visible: true,
    separator: false,
    toggleType: SystemTrayMenuToggleType.none,
    toggleState: 0,
    destructive: false,
    children: const <SystemTrayMenuEntry>[],
  );
}

void main() {
  test(
    'the proxy spawns only when start runs and reports the isolate',
    () async {
      final harness = _Harness();
      addTearDown(harness.proxy.dispose);

      await pumpEventQueue();
      expect(harness.spawns, 0);
      expect(harness.proxy.current, isEmpty);
      expect(harness.proxy.workerIsolateName, isNull);

      await harness.start();
      expect(harness.spawns, 1);
      expect(harness.proxy.workerIsolateName, 'trickster-sni-worker');
    },
  );

  test('start forwards the fake-bus address and test timings', () async {
    final harness = _Harness(
      startPayload: const StatusNotifierStartPayload(
        address: 'unix:path=/tmp/trickster-sni-bus',
        heartbeatInterval: Duration(milliseconds: 20),
        recoveryBackoff: <Duration>[Duration(milliseconds: 10)],
      ),
    );
    addTearDown(harness.proxy.dispose);

    final started = harness.proxy.start();
    await pumpEventQueue();
    final command = await _waitCommand(harness.worker, 0);
    expect(command[2], <String, Object?>{
      'address': 'unix:path=/tmp/trickster-sni-bus',
      'heartbeat_ms': 20,
      'recovery_backoff_ms': <int>[10],
    });
    harness.worker.reply(
      0,
      result: const StatusNotifierStartResult(
        isolateName: 'trickster-sni-worker',
        protocolVersion: StatusNotifierProtocolLimits.protocolVersion,
      ).toJson(),
    );
    await started;
  });

  test('state snapshots decode into tray items', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();

    final seen = <List<SystemTrayItem>>[];
    final subscription = harness.proxy.snapshots.listen(seen.add);
    addTearDown(subscription.cancel);

    harness.worker.state(<StatusNotifierSnapshotItem>[
      _item(id: 'one', title: 'First'),
      _item(id: 'two', title: 'Second'),
    ]);
    await pumpEventQueue();

    expect(harness.proxy.current.map((item) => item.title), <String>[
      'First',
      'Second',
    ]);
    expect(seen, hasLength(1));
    expect(seen.single, harness.proxy.current);
  });

  test('rgba icons decode immediately and unchanged reuses them', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();

    final seen = <List<SystemTrayItem>>[];
    final subscription = harness.proxy.snapshots.listen(seen.add);
    addTearDown(subscription.cancel);

    harness.worker.state(<StatusNotifierSnapshotItem>[_item(icon: _rgba())]);
    await pumpEventQueue();
    final first = harness.proxy.current.single.iconPixmap!;
    expect(first.width, 2);
    expect(first.height, 1);

    harness.worker.state(<StatusNotifierSnapshotItem>[
      _item(icon: StatusNotifierIcon.unchanged()),
    ]);
    await pumpEventQueue();
    expect(harness.proxy.current.single.iconPixmap, same(first));
    expect(seen, hasLength(1));
  });

  test('file icons merge after the UI decode and drop stale paths', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();

    harness.worker.state(<StatusNotifierSnapshotItem>[
      _item(icon: StatusNotifierIcon.file('/tmp/a.png')),
    ]);
    await pumpEventQueue();
    expect(harness.proxy.current.single.iconPixmap, isNull);
    expect(harness.icons.counts['/tmp/a.png'], 1);

    harness.worker.state(<StatusNotifierSnapshotItem>[
      _item(icon: StatusNotifierIcon.file('/tmp/b.png')),
    ]);
    await pumpEventQueue();
    expect(harness.icons.counts['/tmp/b.png'], 1);

    harness.icons.calls['/tmp/b.png']!.complete(
      SystemTrayIconPixmap(width: 3, height: 1, rgba: Uint8List(12)),
    );
    await pumpEventQueue();
    final current = harness.proxy.current.single.iconPixmap!;
    expect(current.width, 3);

    // A decode for the superseded path must not overwrite the new icon.
    harness.icons.calls['/tmp/a.png']!.complete(
      SystemTrayIconPixmap(width: 9, height: 9, rgba: Uint8List(9 * 9 * 4)),
    );
    await pumpEventQueue();
    expect(harness.proxy.current.single.iconPixmap!.width, 3);
  });

  test('the same icon path is decoded once for two items', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();

    harness.worker.state(<StatusNotifierSnapshotItem>[
      _item(id: 'one', icon: StatusNotifierIcon.file('/tmp/shared.png')),
      _item(id: 'two', icon: StatusNotifierIcon.file('/tmp/shared.png')),
    ]);
    await pumpEventQueue();

    expect(harness.icons.counts['/tmp/shared.png'], 1);
    harness.icons.calls['/tmp/shared.png']!.complete(
      SystemTrayIconPixmap(width: 2, height: 2, rgba: Uint8List(16)),
    );
    await pumpEventQueue();
    expect(harness.proxy.current, hasLength(2));
    expect(
      harness.proxy.current.every((item) => item.iconPixmap?.width == 2),
      isTrue,
    );
  });

  test('invoke, loadMenu, and activateMenuEntry forward and decode', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();
    harness.worker.state(<StatusNotifierSnapshotItem>[
      _item(menuAvailable: true, menuPath: '/Menu'),
    ]);
    await pumpEventQueue();
    final item = harness.proxy.current.single;

    final invoked = harness.proxy.invoke(
      item,
      SystemTrayAction.contextMenu,
      const Offset(12.5, -3.25),
    );
    await pumpEventQueue();
    final invokeCommand = await _waitCommand(harness.worker, 1);
    expect(invokeCommand[1], StatusNotifierWorkerOperation.invoke.index);
    expect(invokeCommand[2], <Object?>[
      'item',
      SystemTrayAction.contextMenu.index,
      12.5,
      -3.25,
    ]);
    harness.worker.reply(1, result: true);
    expect(await invoked, isTrue);

    final loaded = harness.proxy.loadMenu(item);
    await pumpEventQueue();
    final menuCommand = await _waitCommand(harness.worker, 2);
    expect(menuCommand[1], StatusNotifierWorkerOperation.loadMenu.index);
    expect(menuCommand[2], 'item');
    harness.worker.reply(
      2,
      result: encodeStatusNotifierMenuEntries(<SystemTrayMenuEntry>[
        _menuEntry(10, 'Quit'),
      ]),
    );
    expect((await loaded)!.single.label, 'Quit');

    final activated = harness.proxy.activateMenuEntry(item, 10);
    await pumpEventQueue();
    final activateCommand = await _waitCommand(harness.worker, 3);
    expect(
      activateCommand[1],
      StatusNotifierWorkerOperation.activateMenuEntry.index,
    );
    expect(activateCommand[2], <Object?>['item', 10]);
    harness.worker.reply(3, result: true);
    expect(await activated, isTrue);
  });

  test(
    'malformed state is ignored and a worker error event does not respawn',
    () async {
      final harness = _Harness();
      addTearDown(harness.proxy.dispose);
      await harness.start();

      harness.worker.state(<StatusNotifierSnapshotItem>[
        _item(title: 'Before'),
      ]);
      await pumpEventQueue();
      expect(harness.proxy.current.single.title, 'Before');

      harness.worker._events.add(<Object?>[
        'state',
        <Object?>[
          <Object?>['too', 'short'],
        ],
      ]);
      await pumpEventQueue();
      expect(harness.proxy.current.single.title, 'Before');

      harness.worker._events.add(<Object?>['error', 'D-Bus hiccup']);
      await pumpEventQueue();
      expect(harness.proxy.current.single.title, 'Before');
      expect(harness.spawns, 1);
    },
  );

  test(
    'isolate failure emits empty state and respawns with capped backoff',
    () async {
      final harness = _Harness();
      addTearDown(harness.proxy.dispose);
      await harness.start();
      harness.worker.state(<StatusNotifierSnapshotItem>[
        _item(title: 'Before crash'),
      ]);
      await pumpEventQueue();
      expect(harness.proxy.current, isNotEmpty);

      harness.worker._errors.add(<Object?>['boom']);
      await pumpEventQueue();
      expect(harness.proxy.current, isEmpty);
      expect(harness.proxy.nextRetryDelay, const Duration(milliseconds: 20));

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(harness.spawns, 2);
      final command = await _waitCommand(harness.worker, 0);
      expect(command[1], StatusNotifierWorkerOperation.start.index);
      harness.worker.reply(
        0,
        result: const StatusNotifierStartResult(
          isolateName: 'trickster-sni-worker',
          protocolVersion: StatusNotifierProtocolLimits.protocolVersion,
        ).toJson(),
      );
      await pumpEventQueue();
      expect(harness.proxy.nextRetryDelay, const Duration(milliseconds: 10));
    },
  );

  test('dispose sends the worker dispose command and cannot revive', () async {
    final harness = _Harness();
    await harness.start();

    var done = false;
    final subscription = harness.proxy.snapshots.listen(
      (_) {},
      onDone: () => done = true,
    );
    addTearDown(subscription.cancel);

    final disposed = harness.proxy.dispose();
    await pumpEventQueue();
    final command = await _waitCommand(harness.worker, 1);
    expect(command[1], StatusNotifierWorkerOperation.dispose.index);
    await disposed;
    await pumpEventQueue();

    expect(harness.worker.killed, isTrue);
    expect(harness.worker.closed, isTrue);
    expect(done, isTrue);

    await harness.proxy.dispose();
    await harness.proxy.start();
    await pumpEventQueue();
    expect(harness.spawns, 1);
  });

  test('TrayBloc accepts the proxy through its service seam', () async {
    final harness = _Harness();
    final bloc = TrayBloc(service: harness.proxy);
    await bloc.close();
    expect(harness.spawns, 0);
  });

  test('the UI proxy source has no D-Bus client or local service', () {
    for (final path in <String>[
      'lib/src/services/status_notifier_worker_proxy.dart',
      'lib/src/services/status_notifier_protocol.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('package:dbus')));
      expect(source, isNot(contains('DBusClient')));
      expect(source, isNot(contains('DBusObject')));
      expect(source, isNot(contains('DBusRemoteObject')));
      expect(source, isNot(contains('StatusNotifierWatcherEndpoint')));
      expect(source, isNot(contains('StatusNotifierService(')));
    }

    final blocSource = File('lib/src/state/tray_bloc.dart').readAsStringSync();
    expect(
      blocSource,
      contains('StatusNotifierService(iconFileDecoder: decodeTrayIconFile)'),
    );
    expect(blocSource, isNot(contains('StatusNotifierWorkerProxy')));
  });
}
