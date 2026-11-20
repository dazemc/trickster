import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/background_worker.dart';

@pragma('vm:entry-point')
void _echoWorker(List<SendPort> bootstrap) {
  serveBackgroundWorker(bootstrap, (operation, payload) {
    if (operation != 1) {
      throw UnsupportedError('Unknown operation $operation');
    }
    return <Object?>[payload, 42];
  });
}

@pragma('vm:entry-point')
void _slowWorker(List<SendPort> bootstrap) {
  // Publish the command port late so close() lands during startup.
  Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
    serveBackgroundWorker(bootstrap, (operation, payload) => payload);
  });
}

@pragma('vm:entry-point')
void _wedgedWorker(List<SendPort> bootstrap) {
  final never = Completer<void>();
  serveBackgroundWorker(bootstrap, (operation, payload) async {
    if (operation == 1) {
      await never.future;
    }
    return payload;
  });
}

void main() {
  test('close during startup cannot be undone by the pending start', () async {
    final worker = BackgroundWorker(
      entrypoint: _slowWorker,
      debugName: 'trickster-test-slow-worker',
      startupTimeout: const Duration(milliseconds: 200),
    );
    final pending = worker.invoke<Object?>(
      operation: 1,
      decode: (response) => response,
    );
    await worker.close();
    await expectLater(pending, throwsA(isA<Object>()));
    await expectLater(
      worker.invoke<Object?>(operation: 1, decode: (response) => response),
      throwsA(isA<StateError>()),
    );
  });

  test('invoke round-trips payloads and surfaces worker errors', () async {
    final worker = BackgroundWorker(
      entrypoint: _echoWorker,
      debugName: 'trickster-test-worker',
    );
    try {
      final result = await worker.invoke<List<Object?>>(
        operation: 1,
        payload: 'hello',
        decode: (response) => response! as List<Object?>,
      );
      expect(result, ['hello', 42]);

      await expectLater(
        worker.invoke<Object?>(operation: 2, decode: (response) => response),
        throwsA(isA<BackgroundWorkerException>()),
      );
    } finally {
      await worker.close();
    }
  });

  test(
    'a wedged invoke times out and the next invoke gets a fresh isolate',
    () async {
      final worker = BackgroundWorker(
        entrypoint: _wedgedWorker,
        debugName: 'trickster-test-wedged-worker',
        requestTimeout: const Duration(milliseconds: 100),
      );
      try {
        await expectLater(
          worker.invoke<Object?>(operation: 1, decode: (response) => response),
          throwsA(isA<TimeoutException>()),
        );

        final result = await worker.invoke<Object?>(
          operation: 2,
          payload: 'fresh',
          decode: (response) => response,
        );
        expect(result, 'fresh');
      } finally {
        await worker.close();
      }
    },
  );

  test(
    'a timed-out generation fails concurrent pending requests cleanly',
    () async {
      final worker = BackgroundWorker(
        entrypoint: _wedgedWorker,
        debugName: 'trickster-test-concurrent-worker',
        requestTimeout: const Duration(milliseconds: 100),
      );
      try {
        final wedged = worker.invoke<Object?>(
          operation: 1,
          decode: (response) => response,
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final queued = worker.invoke<Object?>(
          operation: 2,
          payload: 'queued',
          decode: (response) => response,
        );

        await expectLater(wedged, throwsA(isA<TimeoutException>()));
        await expectLater(
          queued,
          throwsA(
            anyOf(
              isA<TimeoutException>(),
              isA<StateError>(),
              isA<BackgroundWorkerException>(),
            ),
          ),
        );

        final fresh = await worker.invoke<Object?>(
          operation: 2,
          payload: 'after',
          decode: (response) => response,
        );
        expect(fresh, 'after');
      } finally {
        await worker.close();
      }
    },
  );

  test('close after a timeout remains terminal', () async {
    final worker = BackgroundWorker(
      entrypoint: _wedgedWorker,
      debugName: 'trickster-test-terminal-worker',
      requestTimeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      worker.invoke<Object?>(operation: 1, decode: (response) => response),
      throwsA(isA<TimeoutException>()),
    );
    await worker.close();
    await expectLater(
      worker.invoke<Object?>(operation: 2, decode: (response) => response),
      throwsA(isA<StateError>()),
    );
  });
}
