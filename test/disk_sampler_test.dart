import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/disk.dart';

class _FakeDiskReader implements DiskUsageReader {
  StatvfsUsage? result;
  var reads = 0;
  var disposed = false;

  @override
  Future<StatvfsUsage?> read(String path) async {
    reads += 1;
    return result;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

const _usage = StatvfsUsage(
  fragmentSize: 4096,
  blocks: 1000,
  blocksFree: 400,
  blocksAvailable: 300,
);

typedef _Fixture = ({
  DiskSampler sampler,
  _FakeDiskReader reader,
  List<DiskSample> samples,
  Future<void> Function() dispose,
});

_Fixture _fixture({
  StatvfsUsage? result = _usage,
  Duration interval = const Duration(milliseconds: 10),
}) {
  final reader = _FakeDiskReader()..result = result;
  final sampler = DiskSampler(
    interval: interval,
    path: '/data',
    reader: reader,
  );
  final samples = <DiskSample>[];
  final subscription = sampler.snapshots.listen(samples.add);
  return (
    sampler: sampler,
    reader: reader,
    samples: samples,
    dispose: () async {
      await subscription.cancel();
      await sampler.dispose();
    },
  );
}

void main() {
  test('statvfs block math maps to used, total, and free bytes', () {
    final sample = DiskSample.fromUsage('/data', _usage);
    expect(sample.path, '/data');
    expect(sample.usedBytes, 600 * 4096);
    expect(sample.totalBytes, 1000 * 4096);
    expect(sample.freeBytes, 300 * 4096);
    expect(sample.fraction, closeTo(0.6, 1e-9));
  });

  test('a zero-block statvfs reading is no sample', () {
    final sample = DiskSample.fromUsage(
      '/empty',
      const StatvfsUsage(
        fragmentSize: 4096,
        blocks: 0,
        blocksFree: 0,
        blocksAvailable: 0,
      ),
    );
    expect(sample.fraction, isNull);
  });

  test('disk json round-trips', () {
    const sample = DiskSample(
      path: '/data',
      usedBytes: 600,
      totalBytes: 1000,
      freeBytes: 300,
    );
    final decoded = DiskSample.fromJson(
      Map<String, dynamic>.from(sample.toJson()),
    );
    expect(decoded, sample);
    expect(decoded.fraction, 0.6);
    expect(decoded.toJson()['fraction'], 0.6);
  });

  test('a real statvfs read of / returns a positive reading', () async {
    final reader = SystemDiskUsageReader();
    addTearDown(reader.dispose);
    final usage = await reader.read('/');
    expect(usage, isNotNull);
    expect(usage!.blocks, greaterThan(0));
    expect(usage.fragmentSize, greaterThan(0));
    expect(
      DiskSample.fromUsage('/', usage).fraction,
      inInclusiveRange(0.0, 1.0),
    );
  });

  test('invalid mount paths are rejected before the worker', () {
    expect(() => DiskSampler(path: ''), throwsArgumentError);
    expect(() => DiskSampler(path: 'relative'), throwsArgumentError);
    expect(() => DiskSampler(path: '/data\n'), throwsArgumentError);
    expect(() => DiskSampler(path: '/data\u0000'), throwsArgumentError);
  });

  testWidgets('start samples immediately and pause stops the timer', (
    tester,
  ) async {
    final f = _fixture();
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.sampler.isRunning, isTrue);
    expect(f.samples, hasLength(1));
    expect(f.samples.single.fraction, closeTo(0.6, 1e-9));
    expect(f.reader.reads, 1);

    f.sampler.pause();
    expect(f.sampler.isRunning, isFalse);
    f.reader.result = null;
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.samples, hasLength(1));

    f.sampler.resume();
    await tester.pump();
    expect(f.samples, hasLength(2));
    expect(f.samples.last.fraction, isNull);
    expect(f.reader.reads, 2);
  });

  testWidgets('a paused start does no work until resumed', (tester) async {
    final f = _fixture();
    addTearDown(f.dispose);

    f.sampler.start(paused: true);
    expect(f.sampler.isRunning, isFalse);
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.samples, isEmpty);
    expect(f.reader.reads, 0);

    f.sampler.resume();
    await tester.pump();
    expect(f.samples, hasLength(1));
    expect(f.reader.reads, 1);
  });

  testWidgets('a missing mount hides a previously visible reading', (
    tester,
  ) async {
    final f = _fixture(interval: const Duration(seconds: 1));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.fraction, closeTo(0.6, 1e-9));

    f.reader.result = null;
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples, hasLength(2));
    expect(f.samples.last.fraction, isNull);
  });

  testWidgets('dispose is terminal and never revives the sampler', (
    tester,
  ) async {
    final f = _fixture();
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    await f.sampler.dispose();
    await f.sampler.dispose();
    f.sampler.resume();
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.sampler.isRunning, isFalse);
    expect(f.samples, hasLength(1));
    expect(f.reader.disposed, isTrue);
  });
}
