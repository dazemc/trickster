import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/mpris_worker.dart';
import 'package:trickster/src/services/mpris_worker_proxy.dart';

MprisPlaybackState _playing() => MprisPlaybackState(
  serviceName: 'org.mpris.MediaPlayer2.demo',
  identity: 'Demo Player',
  title: 'Song',
  artists: const <String>['Artist'],
  album: 'Album',
  artUrl: 'file:///tmp/cover.png',
  length: const Duration(minutes: 3),
  position: const Duration(seconds: 42),
  observedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  status: MprisPlaybackStatus.playing,
  canGoNext: true,
  canGoPrevious: true,
  canPlay: true,
  canPause: true,
);

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

  MediaPlayerWorkerConnection get connection => MediaPlayerWorkerConnection(
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
}

class _Harness {
  late final MediaPlayerWorkerProxy proxy = MediaPlayerWorkerProxy(
    spawner: _spawn,
    requestTimeout: const Duration(milliseconds: 500),
  );
  late _FakeWorker worker;
  var spawns = 0;

  Future<MediaPlayerWorkerConnection> _spawn() async {
    spawns += 1;
    worker = _FakeWorker();
    return worker.connection;
  }

  Future<void> start({bool paused = false}) async {
    final started = proxy.start(paused: paused);
    await pumpEventQueue();
    final command = await _waitCommand(worker, 0);
    expect(command[1], MediaPlayerWorkerOperation.start.index);
    worker._events.add(<Object?>[command[0], true, null]);
    await started;
  }
}

Future<List<Object?>> _waitCommand(_FakeWorker worker, int index) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (worker.sent.length <= index) {
    if (DateTime.now().isAfter(deadline)) {
      fail('MPRIS worker command $index was not sent');
    }
    await Future<void>.delayed(Duration.zero);
  }
  return worker.sent[index];
}

Future<void> _reply(
  _FakeWorker worker,
  int index, {
  bool ok = true,
  String error = 'worker error',
}) async {
  final command = await _waitCommand(worker, index);
  worker._events.add(<Object?>[
    command[0],
    ok,
    ok ? null : error,
    if (!ok) 'remote stack',
  ]);
}

void main() {
  test('the worker starts only when the media module starts', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);

    await pumpEventQueue();
    expect(harness.spawns, 0);
    expect(harness.proxy.current.available, isFalse);

    await harness.start();
    expect(harness.spawns, 1);
    expect(harness.proxy.current.available, isFalse);
  });

  test('start forwards the paused flag', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);

    final started = harness.proxy.start(paused: true);
    await pumpEventQueue();
    final command = await _waitCommand(harness.worker, 0);
    expect(command[1], MediaPlayerWorkerOperation.start.index);
    expect(command[2], <String, Object?>{'paused': true});
    harness.worker._events.add(<Object?>[command[0], true, null]);
    await started;
  });

  test('worker snapshots deserialize into playback state', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();

    final seen = <MprisPlaybackState>[];
    final subscription = harness.proxy.snapshots.listen(seen.add);
    addTearDown(subscription.cancel);

    final state = _playing();
    harness.worker._events.add(<Object?>['state', state.toJson()]);
    await pumpEventQueue();

    expect(harness.proxy.current, state);
    expect(seen, <MprisPlaybackState>[state]);
  });

  test('controls forward in order and complete', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();

    final controls = <(MediaPlayerWorkerOperation, Future<void> Function())>[
      (MediaPlayerWorkerOperation.playPause, harness.proxy.playPause),
      (MediaPlayerWorkerOperation.next, harness.proxy.next),
      (MediaPlayerWorkerOperation.previous, harness.proxy.previous),
    ];
    for (var index = 0; index < controls.length; index++) {
      final (operation, invoke) = controls[index];
      final completed = invoke();
      final command = await _waitCommand(harness.worker, index + 1);
      expect(command[1], operation.index);
      harness.worker._events.add(<Object?>[command[0], true, null]);
      await completed;
    }
  });

  test('recovery pause and resume forward to the worker', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();

    harness.proxy.pauseRecovery();
    final paused = await _waitCommand(harness.worker, 1);
    expect(paused[1], MediaPlayerWorkerOperation.pauseRecovery.index);
    harness.worker._events.add(<Object?>[paused[0], true, null]);

    final resumed = harness.proxy.resumeRecovery();
    final command = await _waitCommand(harness.worker, 2);
    expect(command[1], MediaPlayerWorkerOperation.resumeRecovery.index);
    harness.worker._events.add(<Object?>[command[0], true, null]);
    await resumed;
  });

  test('a worker command failure surfaces as unavailable', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);

    final started = harness.proxy.start();
    await pumpEventQueue();
    await _reply(harness.worker, 0, ok: false);
    await started;

    expect(harness.proxy.current, MprisPlaybackState.unavailable());
  });

  test(
    'a worker error marks playback unavailable and stops controls',
    () async {
      final harness = _Harness();
      addTearDown(harness.proxy.dispose);
      await harness.start();

      final seen = <MprisPlaybackState>[];
      final subscription = harness.proxy.snapshots.listen(seen.add);
      addTearDown(subscription.cancel);
      harness.worker._events.add(<Object?>['state', _playing().toJson()]);
      await pumpEventQueue();
      expect(harness.proxy.current.available, isTrue);

      harness.worker._errors.add(<Object?>['worker crashed', 'remote stack']);
      await pumpEventQueue();

      expect(harness.proxy.current, MprisPlaybackState.unavailable());
      expect(seen.last, MprisPlaybackState.unavailable());
      final commands = harness.worker.sent.length;
      await harness.proxy.playPause();
      expect(harness.worker.sent.length, commands);
    },
  );

  test(
    'dispose kills the worker, closes the stream, and never revives',
    () async {
      final harness = _Harness();
      await harness.start();
      var done = false;
      final subscription = harness.proxy.snapshots.listen(
        (_) {},
        onDone: () => done = true,
      );
      addTearDown(subscription.cancel);

      await harness.proxy.dispose();
      await pumpEventQueue();

      expect(harness.worker.killed, isTrue);
      expect(harness.worker.closed, isTrue);
      expect(done, isTrue);

      await harness.proxy.start();
      await harness.proxy.playPause();
      await pumpEventQueue();
      expect(harness.spawns, 1);
    },
  );

  test('the UI proxy source never constructs a D-Bus client', () {
    final source = File(
      'lib/src/services/mpris_worker_proxy.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('DBusClient')));
    expect(source, isNot(contains('MediaPlayerService(')));
  });
}
