import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/ram.dart';

const _meminfo = '''
MemTotal:       1000 kB
MemFree:         100 kB
MemAvailable:    250 kB
Buffers:          50 kB
Cached:          100 kB
SReclaimable:     10 kB
Shmem:             5 kB
SwapTotal:      2000 kB
SwapFree:        500 kB
''';

const _fallbackMeminfo = '''
MemTotal:       1000 kB
MemFree:         100 kB
Buffers:          50 kB
Cached:          100 kB
SReclaimable:     10 kB
Shmem:             5 kB
''';

typedef _Fixture = ({
  RamSampler sampler,
  File meminfo,
  List<RamSample> samples,
  Future<void> Function() dispose,
});

_Fixture _fixture({
  Duration interval = const Duration(hours: 1),
  String contents = _meminfo,
}) {
  final root = Directory.systemTemp.createTempSync('trickster-ram');
  final meminfo = File('${root.path}/meminfo')..writeAsStringSync(contents);
  final sampler = RamSampler(interval: interval, meminfoPath: meminfo.path);
  final samples = <RamSample>[];
  final subscription = sampler.snapshots.listen(samples.add);
  return (
    sampler: sampler,
    meminfo: meminfo,
    samples: samples,
    dispose: () async {
      await subscription.cancel();
      sampler.dispose();
      root.deleteSync(recursive: true);
    },
  );
}

void main() {
  test('meminfo parses MemTotal and MemAvailable', () {
    final parsed = parseMeminfo(_meminfo);
    expect(parsed, isNotNull);
    expect(parsed!.total, 1000 * 1024);
    expect(parsed.available, 250 * 1024);
    expect(parsed.swapTotal, 2000 * 1024);
    expect(parsed.swapFree, 500 * 1024);
  });

  test('swap totals require a positive total and a free reading', () {
    final zero = parseMeminfo(
      'MemTotal: 1000 kB\nMemAvailable: 500 kB\n'
      'SwapTotal: 0 kB\nSwapFree: 0 kB\n',
    );
    expect(zero!.swapTotal, isNull);
    expect(zero.swapFree, isNull);

    final missingFree = parseMeminfo(
      'MemTotal: 1000 kB\nMemAvailable: 500 kB\nSwapTotal: 1000 kB\n',
    );
    expect(missingFree!.swapTotal, isNull);
    expect(missingFree.swapFree, isNull);

    final clamped = parseMeminfo(
      'MemTotal: 1000 kB\nMemAvailable: 500 kB\n'
      'SwapTotal: 1000 kB\nSwapFree: 1500 kB\n',
    );
    expect(clamped!.swapTotal, 1000 * 1024);
    expect(clamped.swapFree, 1000 * 1024);
  });

  test('the fallback sums free, buffers, cached, reclaimable, and shmem', () {
    final parsed = parseMeminfo(_fallbackMeminfo);
    expect(parsed, isNotNull);
    expect(parsed!.available, (100 + 50 + 100 + 10 - 5) * 1024);
    expect(parsed.swapTotal, isNull);
    expect(parsed.swapFree, isNull);
  });

  test('a present zero MemAvailable is not replaced by the fallback', () {
    final parsed = parseMeminfo(
      'MemTotal: 1000 kB\nMemAvailable: 0 kB\n'
      'MemFree: 900 kB\nBuffers: 10 kB\nCached: 20 kB\n',
    );
    expect(parsed!.available, 0);
  });

  test('malformed or empty meminfo yields no reading', () {
    expect(parseMeminfo('not a meminfo line\n'), isNull);
    expect(parseMeminfo('MemTotal: 0 kB\n'), isNull);
    expect(parseMeminfo('MemTotal: much kB\n'), isNull);
    expect(
      parseMeminfo('MemTotal: 1000 kB\nMemFree: 100 kB\n'),
      isNull,
      reason: 'the fallback needs free, buffers, and cached',
    );
  });

  test('the series keeps the cap and appends newest last', () {
    var sample = const RamSample();
    for (var i = 0; i < RamSample.capacity + 5; i++) {
      sample = sample.append(i / 100);
    }
    expect(sample.history.length, RamSample.capacity);
    expect(sample.history.first, closeTo(0.05, 1e-9));
    expect(sample.history.last, closeTo((RamSample.capacity + 4) / 100, 1e-9));
    expect(sample.current, isNull);
  });

  test('ram json round-trips including history and swap', () {
    const sample = RamSample(
      usedBytes: 4 * 1024 * 1024,
      totalBytes: 8 * 1024 * 1024,
      swapUsedBytes: 1024 * 1024,
      swapTotalBytes: 2 * 1024 * 1024,
      history: [0.25, 0.5],
    );
    final decoded = RamSample.fromJson(
      Map<String, dynamic>.from(sample.toJson()),
    );
    expect(decoded.usedBytes, 4 * 1024 * 1024);
    expect(decoded.totalBytes, 8 * 1024 * 1024);
    expect(decoded.swapUsedBytes, 1024 * 1024);
    expect(decoded.swapTotalBytes, 2 * 1024 * 1024);
    expect(decoded.swapFraction, 0.5);
    expect(decoded.hasSwap, isTrue);
    expect(decoded.history, [0.25, 0.5]);
    expect(decoded.current, 0.5);
    expect(decoded.toJson()['current'], 0.5);
    expect(decoded.toJson()['swap_current'], 0.5);
  });

  test('an old ram document decodes with no swap and append preserves it', () {
    final decoded = RamSample.fromJson(const <String, dynamic>{
      'used_bytes': 4,
      'total_bytes': 8,
      'history': [0.5],
    });
    expect(decoded.swapUsedBytes, isNull);
    expect(decoded.swapTotalBytes, isNull);
    expect(decoded.swapFraction, isNull);

    final sample = const RamSample(
      usedBytes: 4,
      totalBytes: 8,
      swapUsedBytes: 1,
      swapTotalBytes: 2,
    ).append(0.5);
    expect(sample.swapUsedBytes, 1);
    expect(sample.swapTotalBytes, 2);
    expect(sample.swapFraction, 0.5);
  });

  testWidgets('start samples immediately and pause stops the timer', (
    tester,
  ) async {
    final f = _fixture(interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.sampler.isRunning, isTrue);
    expect(f.samples, hasLength(1));
    expect(f.samples.single.current, closeTo(0.75, 1e-9));
    expect(f.samples.single.swapTotalBytes, 2000 * 1024);
    expect(f.samples.single.swapUsedBytes, 1500 * 1024);
    expect(f.samples.single.swapFraction, closeTo(0.75, 1e-9));
    expect(f.samples.single.history, hasLength(1));

    f.sampler.pause();
    expect(f.sampler.isRunning, isFalse);
    f.meminfo.writeAsStringSync(
      _meminfo.replaceFirst(
        'MemAvailable:    250 kB',
        'MemAvailable:    500 kB',
      ),
    );
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.samples, hasLength(1));

    f.sampler.resume();
    await tester.pump();
    expect(f.sampler.isRunning, isTrue);
    expect(f.samples, hasLength(2));
    expect(f.samples.last.current, closeTo(0.5, 1e-9));
    expect(f.samples.last.swapFraction, closeTo(0.75, 1e-9));
    expect(f.samples.last.history, hasLength(2));
  });

  testWidgets('a machine without swap emits no swap reading', (tester) async {
    final f = _fixture(contents: _fallbackMeminfo);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples, hasLength(1));
    expect(f.samples.single.current, isNotNull);
    expect(f.samples.single.swapUsedBytes, isNull);
    expect(f.samples.single.swapTotalBytes, isNull);
    expect(f.samples.single.swapFraction, isNull);
  });

  testWidgets('a paused start does no work until resumed', (tester) async {
    final f = _fixture(interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.start(paused: true);
    expect(f.sampler.isRunning, isFalse);
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.samples, isEmpty);
    expect(f.sampler.isRunning, isFalse);

    f.sampler.resume();
    await tester.pump();
    expect(f.sampler.isRunning, isTrue);
    expect(f.samples, hasLength(1));
    expect(f.samples.single.current, closeTo(0.75, 1e-9));
  });

  testWidgets('resume before start is a no-op', (tester) async {
    final f = _fixture(interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.resume();
    expect(f.sampler.isRunning, isFalse);
    expect(f.samples, isEmpty);

    f.sampler.start();
    await tester.pump();
    expect(f.samples, hasLength(1));
  });

  testWidgets('dispose is terminal and never revives the sampler', (
    tester,
  ) async {
    final f = _fixture(interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    f.sampler.pause();
    f.sampler.dispose();
    f.sampler.dispose();
    f.sampler.resume();
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.sampler.isRunning, isFalse);
    expect(f.samples, hasLength(1));
  });

  testWidgets('start after dispose stays terminal', (tester) async {
    final f = _fixture(interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.dispose();
    f.sampler.start();
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.sampler.isRunning, isFalse);
    expect(f.samples, isEmpty);
  });

  testWidgets('a missing meminfo file leaves the machine hidden', (
    tester,
  ) async {
    final sampler = RamSampler(
      interval: const Duration(hours: 1),
      meminfoPath: '/nonexistent/trickster-meminfo',
    );
    addTearDown(sampler.dispose);
    final samples = <RamSample>[];
    final subscription = sampler.snapshots.listen(samples.add);
    addTearDown(subscription.cancel);

    sampler.start();
    expect(sampler.isRunning, isTrue);
    expect(samples, isEmpty);
  });
}
