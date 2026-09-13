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

void main() {
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
        worker.invoke<Object?>(
          operation: 2,
          decode: (response) => response,
        ),
        throwsA(isA<BackgroundWorkerException>()),
      );
    } finally {
      await worker.close();
    }
  });
}
