import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/bands.dart';

import 'support/fake_pipewire.dart';

/// Interleaved stereo tone, shaped like the runner's frames.
Float32List _sine({required double hz, int frames = 1024, int channels = 2}) {
  final samples = Float32List(frames * channels);
  for (var frame = 0; frame < frames; frame++) {
    final value = 0.5 * math.sin(2 * math.pi * hz * frame / 48000);
    for (var channel = 0; channel < channels; channel++) {
      samples[frame * channels + channel] = value;
    }
  }
  return samples;
}

ReceivePort? _idleKeeper;

/// Stays alive without publishing a command port, so startup times out.
@pragma('vm:entry-point')
void _idleWorker(List<Object?> bootstrap) {
  _idleKeeper = ReceivePort();
  _idleKeeper!.listen((_) {});
}

/// The production worker protocol, for a successful start after a failure.
@pragma('vm:entry-point')
void _testBandsWorker(List<Object?> bootstrap) {
  final ready = bootstrap[0] as SendPort;
  final results = bootstrap[1] as SendPort;
  final bands = bootstrap[2] as int;
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.listen((message) {
    if (message is! List || message.length != 3) {
      return;
    }
    final samples = message[0];
    final rate = message[1];
    final channels = message[2];
    if (samples is! Float32List || rate is! int || channels is! int) {
      return;
    }
    results.send(
      analyzeBands(samples, rate: rate, channels: channels, bands: bands),
    );
  });
}

/// Publishes its command port and exits immediately, reproducing a worker
/// crash after startup.
@pragma('vm:entry-point')
void _readyThenExitWorker(List<Object?> bootstrap) {
  final ready = bootstrap[0] as SendPort;
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  commands.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a running analyzer turns frames into levels', () async {
    final capture = FakePipeWireCapture();
    final analyzer = BandAnalyzer(capture: capture);
    addTearDown(analyzer.dispose);

    expect(await analyzer.start(), isTrue);
    expect(analyzer.isRunning, isTrue);

    final next = analyzer.levels.first;
    capture.emit(_sine(hz: 1000));
    final levels = await next.timeout(const Duration(seconds: 10));

    expect(levels, hasLength(bandCount));
    expect(levels[6], greaterThan(0.5));
  });

  test('stop kills the worker and closes the monitor', () async {
    final capture = FakePipeWireCapture();
    final analyzer = BandAnalyzer(capture: capture);
    addTearDown(analyzer.dispose);

    await analyzer.start();
    await analyzer.stop();

    expect(analyzer.isRunning, isFalse);
    expect(capture.stops, hasLength(1));
  });

  test('a refused capture leaves the analyzer stopped', () async {
    final capture = FakePipeWireCapture(startResult: false);
    final analyzer = BandAnalyzer(capture: capture);
    addTearDown(analyzer.dispose);

    expect(await analyzer.start(), isFalse);
    expect(analyzer.isRunning, isFalse);
    expect(capture.starts, hasLength(1));
  });

  test('a failed spawn cleans up and a later start runs', () async {
    final capture = FakePipeWireCapture();
    var calls = 0;

    Future<Isolate> spawn({
      required SendPort ready,
      required SendPort results,
      required SendPort errors,
      required SendPort exits,
      required int bands,
    }) async {
      calls += 1;
      if (calls == 1) {
        throw StateError('worker spawn failed');
      }
      return Isolate.spawn<List<Object?>>(
        _testBandsWorker,
        <Object?>[ready, results, bands],
        debugName: 'trickster-test-bands',
        errorsAreFatal: true,
        onError: errors,
        onExit: exits,
      );
    }

    final analyzer = BandAnalyzer(capture: capture, spawnWorker: spawn);
    addTearDown(analyzer.dispose);

    expect(await analyzer.start(), isFalse);
    expect(analyzer.isRunning, isFalse);
    expect(capture.starts, hasLength(1));
    expect(capture.stops, hasLength(1));

    expect(await analyzer.start(), isTrue);
    expect(analyzer.isRunning, isTrue);
    expect(capture.starts, hasLength(2));

    final next = analyzer.levels.first;
    capture.emit(_sine(hz: 1000));
    final levels = await next.timeout(const Duration(seconds: 10));
    expect(levels, hasLength(bandCount));
    expect(levels[6], greaterThan(0.5));
  });

  test('a worker that never publishes ready is killed', () async {
    final capture = FakePipeWireCapture();
    final exited = ReceivePort();
    Isolate? idle;

    Future<Isolate> spawn({
      required SendPort ready,
      required SendPort results,
      required SendPort errors,
      required SendPort exits,
      required int bands,
    }) async {
      idle = await Isolate.spawn<List<Object?>>(
        _idleWorker,
        <Object?>[ready, results, bands],
        debugName: 'trickster-test-idle-bands',
        errorsAreFatal: true,
        onError: errors,
        onExit: exited.sendPort,
      );
      return idle!;
    }

    final analyzer = BandAnalyzer(
      capture: capture,
      spawnWorker: spawn,
      startupTimeout: const Duration(milliseconds: 150),
    );
    addTearDown(() async {
      idle?.kill(priority: Isolate.immediate);
      exited.close();
      await analyzer.dispose();
    });

    expect(await analyzer.start(), isFalse);
    expect(analyzer.isRunning, isFalse);
    expect(capture.stops, hasLength(1));
    await exited.first.timeout(const Duration(seconds: 2));
  });

  test('stop during startup closes the attempt', () async {
    final capture = FakePipeWireCapture();
    final exited = ReceivePort();
    final entered = Completer<void>();
    final spawned = Completer<Isolate>();
    Isolate? idle;

    Future<Isolate> spawn({
      required SendPort ready,
      required SendPort results,
      required SendPort errors,
      required SendPort exits,
      required int bands,
    }) async {
      idle = await Isolate.spawn<List<Object?>>(
        _idleWorker,
        <Object?>[ready, results, bands],
        debugName: 'trickster-test-idle-bands',
        errorsAreFatal: true,
        onError: errors,
        onExit: exited.sendPort,
      );
      entered.complete();
      return spawned.future;
    }

    final analyzer = BandAnalyzer(
      capture: capture,
      spawnWorker: spawn,
      startupTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(() async {
      idle?.kill(priority: Isolate.immediate);
      exited.close();
      await analyzer.dispose();
    });

    final starting = analyzer.start();
    await entered.future;
    await analyzer.stop();
    spawned.complete(idle!);

    expect(await starting, isFalse);
    expect(analyzer.isRunning, isFalse);
    expect(capture.stops, hasLength(1));
    await exited.first.timeout(const Duration(seconds: 2));
  });

  test(
    'a worker exit after ready fails once, stops capture, and can restart',
    () async {
      final capture = FakePipeWireCapture();
      final failures = <void>[];
      final failed = Completer<void>();
      var calls = 0;

      Future<Isolate> spawn({
        required SendPort ready,
        required SendPort results,
        required SendPort errors,
        required SendPort exits,
        required int bands,
      }) {
        calls += 1;
        if (calls == 1) {
          return Isolate.spawn<List<Object?>>(
            _readyThenExitWorker,
            <Object?>[ready],
            debugName: 'trickster-test-ready-exit',
            errorsAreFatal: true,
            onError: errors,
            onExit: exits,
          );
        }
        return Isolate.spawn<List<Object?>>(
          _testBandsWorker,
          <Object?>[ready, results, bands],
          debugName: 'trickster-test-bands',
          errorsAreFatal: true,
          onError: errors,
          onExit: exits,
        );
      }

      final analyzer = BandAnalyzer(capture: capture, spawnWorker: spawn);
      final levels = <List<double>>[];
      final levelSubscription = analyzer.levels.listen(levels.add);
      final failureSubscription = analyzer.failures.listen((_) {
        failures.add(null);
        if (!failed.isCompleted) {
          failed.complete();
        }
      });
      addTearDown(() async {
        await failureSubscription.cancel();
        await levelSubscription.cancel();
        await analyzer.dispose();
      });

      expect(await analyzer.start(), isTrue);
      await failed.future.timeout(const Duration(seconds: 5));

      expect(failures, hasLength(1));
      expect(analyzer.isRunning, isFalse);
      expect(capture.stops, isNotEmpty);
      expect(levels, isNotEmpty);
      expect(levels.last, everyElement(0.0));

      final afterExit = levels.length;
      capture.emit(_sine(hz: 1000));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(levels, hasLength(afterExit));

      expect(await analyzer.start(), isTrue);
      final next = analyzer.levels.firstWhere(
        (batch) => batch.any((level) => level > 0),
      );
      capture.emit(_sine(hz: 1000));
      expect(
        await next.timeout(const Duration(seconds: 10)),
        hasLength(bandCount),
      );
    },
  );

  test('an intentional stop emits no failure', () async {
    final capture = FakePipeWireCapture();
    final analyzer = BandAnalyzer(capture: capture);
    final failures = <void>[];
    final subscription = analyzer.failures.listen(failures.add);
    addTearDown(() async {
      await subscription.cancel();
      await analyzer.dispose();
    });

    expect(await analyzer.start(), isTrue);
    await analyzer.stop();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(failures, isEmpty);
    expect(capture.stops, hasLength(1));
  });

  test('dispose closes both analyzer streams', () async {
    final capture = FakePipeWireCapture();
    final analyzer = BandAnalyzer(capture: capture);
    final levelsDone = analyzer.levels.isEmpty;
    final failuresDone = analyzer.failures.isEmpty;

    await analyzer.start();
    await analyzer.dispose();

    expect(await levelsDone, isTrue);
    expect(await failuresDone, isTrue);
    expect(capture.stops, hasLength(1));
  });

  test('start closes every attempt-local port when it fails', () {
    final source = File('lib/src/services/bands.dart').readAsStringSync();
    final startIndex = source.indexOf('Future<bool> start()');
    final stopIndex = source.indexOf('Future<void> stop()');
    expect(startIndex, isNonNegative, reason: 'start method not found');
    expect(stopIndex, greaterThan(startIndex), reason: 'stop method missing');
    final start = source.substring(startIndex, stopIndex);
    final ports = RegExp(
      r'final (\w+) = ReceivePort\([^)]*\);',
    ).allMatches(start).map((match) => match.group(1)!).toList();
    expect(ports, hasLength(4));
    for (final name in ports) {
      expect(
        start,
        contains('$name.close();'),
        reason: '$name must be closed on the start failure path',
      );
    }
    expect(start, contains('isolate?.kill(priority: Isolate.immediate);'));
  });
}
