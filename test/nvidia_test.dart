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
    var includeUsage = true;
    var includeMemory = true;
    if (payload is List<Object?> && payload.length == 2) {
      includeUsage = payload[0] != false;
      includeMemory = payload[1] != false;
    }
    return <Object?>[
      null,
      <Object?>[
        <Object?>[
          0,
          includeUsage ? 0.5 : null,
          'Test GPU',
          includeMemory ? 100 : null,
          includeMemory ? 200 : null,
        ],
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
    expect(read.samples.single.usedBytes, 100);
    expect(read.samples.single.totalBytes, 200);

    final memoryOnly = await reader.read(
      includeUsage: false,
      includeMemory: true,
    );
    expect(memoryOnly.samples.single.usage, isNull);
    expect(memoryOnly.samples.single.usedBytes, 100);
    expect(memoryOnly.samples.single.totalBytes, 200);

    final usageOnly = await reader.read(
      includeUsage: true,
      includeMemory: false,
    );
    expect(usageOnly.samples.single.usage, closeTo(0.5, 0.0001));
    expect(usageOnly.samples.single.usedBytes, isNull);
    expect(usageOnly.samples.single.totalBytes, isNull);
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
