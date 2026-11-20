import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/background_worker.dart';
import 'package:trickster/src/services/nvidia.dart';

@pragma('vm:entry-point')
void _nvmlWorker(List<SendPort> bootstrap) {
  serveBackgroundWorker(bootstrap, (operation, payload) {
    if (operation != 1) {
      throw UnsupportedError('Unknown operation $operation');
    }
    return <Object?>[
      null,
      <Object?>[
        <Object?>[0, 0.5, 'Test GPU'],
      ],
    ];
  });
}

@pragma('vm:entry-point')
void _wedgedNvmlWorker(List<SendPort> bootstrap) {
  final never = Completer<void>();
  serveBackgroundWorker(bootstrap, (operation, payload) async {
    await never.future;
    return null;
  });
}

void main() {
  test('decodes a normal NVML worker reading', () async {
    final worker = BackgroundWorker(
      entrypoint: _nvmlWorker,
      debugName: 'trickster-test-nvml-worker',
      requestTimeout: const Duration(seconds: 1),
    );
    final reader = NvmlReader(
      worker: worker,
      requestTimeout: const Duration(seconds: 1),
    );
    addTearDown(reader.dispose);

    final read = await reader.read();
    expect(read.error, isNull);
    expect(read.samples, hasLength(1));
    expect(read.samples.single.index, 0);
    expect(read.samples.single.usage, closeTo(0.5, 0.0001));
    expect(read.samples.single.name, 'Test GPU');
  });

  test('a timeout enters cooldown instead of respawning immediately', () async {
    final worker = BackgroundWorker(
      entrypoint: _wedgedNvmlWorker,
      debugName: 'trickster-test-wedged-nvml-worker',
      requestTimeout: const Duration(milliseconds: 100),
    );
    final reader = NvmlReader(
      worker: worker,
      requestTimeout: const Duration(milliseconds: 100),
      cooldown: const Duration(seconds: 10),
    );
    addTearDown(reader.dispose);

    final first = await reader.read();
    expect(first.samples, isEmpty);
    expect(first.error, contains('timed out'));

    final watch = Stopwatch()..start();
    final second = await reader.read();
    watch.stop();
    expect(second.samples, isEmpty);
    expect(second.error, contains('cooling down'));
    expect(
      watch.elapsed,
      lessThan(const Duration(milliseconds: 50)),
      reason: 'cooldown must skip the wedged worker and its request timeout',
    );
  });
}
