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
  _Harness({
    this.retryDelay = const Duration(milliseconds: 20),
    this.retryDelayMax = const Duration(milliseconds: 80),
  }) {
    proxy = MediaPlayerWorkerProxy(
      spawner: _spawn,
      requestTimeout: const Duration(milliseconds: 500),
      retryDelay: retryDelay,
      retryDelayMax: retryDelayMax,
    );
  }

  final Duration retryDelay;
  final Duration retryDelayMax;
  late final MediaPlayerWorkerProxy proxy;
  final List<_FakeWorker> workers = <_FakeWorker>[];
  var spawns = 0;

  _FakeWorker get worker => workers.last;

  Future<MediaPlayerWorkerConnection> _spawn() async {
    spawns += 1;
    final next = _FakeWorker();
    workers.add(next);
    return next.connection;
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

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met before the timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
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
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(harness.spawns, 1);
  });

  test('an in-worker error does not respawn the worker', () async {
    final harness = _Harness();
    addTearDown(harness.proxy.dispose);
    await harness.start();

    final seen = <MprisPlaybackState>[];
    final subscription = harness.proxy.snapshots.listen(seen.add);
    addTearDown(subscription.cancel);
    harness.worker._events.add(<Object?>['state', _playing().toJson()]);
    await pumpEventQueue();
    expect(harness.proxy.current.available, isTrue);

    harness.worker._events.add(<Object?>['error', 'D-Bus failed in worker']);
    await pumpEventQueue();

    expect(harness.proxy.current, MprisPlaybackState.unavailable());
    expect(seen.last, MprisPlaybackState.unavailable());
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(harness.spawns, 1);
  });

  test('an exited worker respawns and controls work again', () async {
    final harness = _Harness(
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 40),
    );
    addTearDown(harness.proxy.dispose);
    await harness.start();
    final first = harness.worker;
    final seen = <MprisPlaybackState>[];
    final subscription = harness.proxy.snapshots.listen(seen.add);
    addTearDown(subscription.cancel);
    first._events.add(<Object?>['state', _playing().toJson()]);
    await pumpEventQueue();
    expect(harness.proxy.current.available, isTrue);

    first._exits.add(<Object?>[0, 'exit']);
    await _waitUntil(() => harness.spawns == 2);
    final second = harness.worker;

    expect(second, isNot(same(first)));
    expect(first.killed, isTrue);
    expect(first.closed, isTrue);
    expect(harness.proxy.current, MprisPlaybackState.unavailable());
    expect(seen.last, MprisPlaybackState.unavailable());

    final start = await _waitCommand(second, 0);
    expect(start[1], MediaPlayerWorkerOperation.start.index);
    expect(start[2], <String, Object?>{'paused': false});
    second._events.add(<Object?>[start[0], true, null]);
    await pumpEventQueue();
    second._events.add(<Object?>['state', _playing().toJson()]);
    await pumpEventQueue();
    expect(harness.proxy.current, _playing());

    final controlled = harness.proxy.next();
    final command = await _waitCommand(second, 1);
    expect(command[1], MediaPlayerWorkerOperation.next.index);
    second._events.add(<Object?>[command[0], true, null]);
    await controlled;
  });

  test('a paused start is preserved across respawn', () async {
    final harness = _Harness(
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 40),
    );
    addTearDown(harness.proxy.dispose);
    await harness.start(paused: true);

    harness.worker._exits.add(<Object?>[0, 'exit']);
    await _waitUntil(() => harness.spawns == 2);
    final start = await _waitCommand(harness.worker, 0);

    expect(start[1], MediaPlayerWorkerOperation.start.index);
    expect(start[2], <String, Object?>{'paused': true});
    harness.worker._events.add(<Object?>[start[0], true, null]);
  });

  test('a later recovery pause is preserved across respawn', () async {
    final harness = _Harness(
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 40),
    );
    addTearDown(harness.proxy.dispose);
    await harness.start();

    harness.proxy.pauseRecovery();
    final paused = await _waitCommand(harness.worker, 1);
    expect(paused[1], MediaPlayerWorkerOperation.pauseRecovery.index);
    harness.worker._events.add(<Object?>[paused[0], true, null]);

    harness.worker._exits.add(<Object?>[0, 'exit']);
    await _waitUntil(() => harness.spawns == 2);
    final start = await _waitCommand(harness.worker, 0);
    expect(start[2], <String, Object?>{'paused': true});
    harness.worker._events.add(<Object?>[start[0], true, null]);
  });

  test('a valid state snapshot resets the retry backoff', () async {
    final harness = _Harness(
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 40),
    );
    addTearDown(harness.proxy.dispose);
    await harness.start();

    harness.worker._exits.add(<Object?>[0, 'exit']);
    await _waitUntil(() => harness.spawns == 2);
    final second = harness.worker;
    final start = await _waitCommand(second, 0);
    second._events.add(<Object?>[start[0], true, null]);
    await pumpEventQueue();
    expect(
      harness.proxy.nextRetryDelay,
      greaterThan(harness.retryDelay),
      reason: 'the first failure should have doubled the delay',
    );

    second._events.add(<Object?>['state', _playing().toJson()]);
    await pumpEventQueue();

    expect(harness.proxy.nextRetryDelay, harness.retryDelay);
  });

  test('repeated startup failures back off', () async {
    final spawnTimes = <DateTime>[];
    final proxy = MediaPlayerWorkerProxy(
      spawner: () async {
        spawnTimes.add(DateTime.now());
        throw StateError('worker failed to start');
      },
      retryDelay: const Duration(milliseconds: 20),
      retryDelayMax: const Duration(milliseconds: 80),
    );
    addTearDown(proxy.dispose);
    await proxy.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(spawnTimes.length, 3);
    expect(
      spawnTimes[1].difference(spawnTimes[0]).inMilliseconds,
      greaterThanOrEqualTo(15),
    );
    expect(
      spawnTimes[2].difference(spawnTimes[1]).inMilliseconds,
      greaterThanOrEqualTo(35),
    );
  });

  test('dispose cancels a pending respawn', () async {
    var spawns = 0;
    final proxy = MediaPlayerWorkerProxy(
      spawner: () async {
        spawns += 1;
        throw StateError('worker failed to start');
      },
      retryDelay: const Duration(milliseconds: 50),
      retryDelayMax: const Duration(milliseconds: 50),
    );
    addTearDown(proxy.dispose);
    await proxy.start();
    expect(spawns, 1);

    await proxy.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(spawns, 1);
  });

  test('the worker is not spawned before start', () async {
    var spawns = 0;
    final proxy = MediaPlayerWorkerProxy(
      spawner: () async {
        spawns += 1;
        throw StateError('worker failed to start');
      },
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 20),
    );
    addTearDown(proxy.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(spawns, 0);
  });

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
