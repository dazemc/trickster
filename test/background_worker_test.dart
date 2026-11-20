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
}
