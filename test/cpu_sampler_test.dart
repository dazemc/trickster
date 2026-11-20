import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/cpu.dart';

const _initialStat = 'cpu  100 0 100 800 0 0 0 0 0 0\n';
const _busyStat = 'cpu  150 0 150 900 0 0 0 0 0 0\n';

typedef _Fixture = ({
  CpuSampler sampler,
  File stat,
  List<CpuSample> samples,
  Future<void> Function() dispose,
});

_Fixture _fixture({
  Duration interval = const Duration(hours: 1),
  Duration resumePrime = const Duration(milliseconds: 10),
}) {
  final root = Directory.systemTemp.createTempSync('trickster-cpu');
  final cpuInfo = File('${root.path}/cpuinfo')
    ..writeAsStringSync('model name\t: Test CPU\n');
  final stat = File('${root.path}/stat')..writeAsStringSync(_initialStat);
  final sampler = CpuSampler(
    interval: interval,
    resumePrime: resumePrime,
    cpuInfoPath: cpuInfo.path,
    statPath: stat.path,
  );
  final samples = <CpuSample>[];
  final subscription = sampler.snapshots.listen(samples.add);
  return (
    sampler: sampler,
    stat: stat,
    samples: samples,
    dispose: () async {
      await subscription.cancel();
      sampler.dispose();
      root.deleteSync(recursive: true);
    },
  );
}

void main() {
  testWidgets('pause stops the timer and resume takes one recent sample', (
    tester,
  ) async {
    final f = _fixture();
    addTearDown(f.dispose);

    f.sampler.start();
    expect(f.sampler.isRunning, isTrue);
    await tester.pump();
    // The first read is only the baseline for the delta calculation.
    expect(f.samples, isEmpty);

    f.sampler.pause();
    expect(f.sampler.isRunning, isFalse);
    f.sampler.pause(); // Repeated pauses are harmless.
    expect(f.sampler.isRunning, isFalse);

    f.sampler.resume();
    // resume() takes a baseline immediately; the one-shot prime window emits
    // the fresh post-idle reading.
    f.stat.writeAsStringSync(_busyStat);
    await tester.pump(const Duration(milliseconds: 10));
    expect(f.samples, hasLength(1));
    expect(f.samples.single.current, closeTo(0.5, 1e-9));
    expect(f.samples.single.name, 'Test CPU');
    expect(f.sampler.isRunning, isTrue);
  });

  testWidgets('a paused start does no work until resumed', (tester) async {
    final f = _fixture();
    addTearDown(f.dispose);

    f.sampler.start(paused: true);
    expect(f.sampler.isRunning, isFalse);
    f.sampler.pause();
    await tester.pump();
    expect(f.samples, isEmpty);

    f.sampler.resume();
    f.stat.writeAsStringSync(_busyStat);
    await tester.pump(const Duration(milliseconds: 10));
    expect(f.samples, hasLength(1));
    expect(f.samples.single.current, closeTo(0.5, 1e-9));
  });

  testWidgets('resume before start is a no-op', (tester) async {
    final f = _fixture();
    addTearDown(f.dispose);

    f.sampler.resume();
    await tester.pump();
    expect(f.sampler.isRunning, isFalse);
    expect(f.samples, isEmpty);

    f.sampler.start();
    expect(f.sampler.isRunning, isTrue);
    await tester.pump();
    expect(f.samples, isEmpty);
  });

  testWidgets('a second start does not add a second periodic timer', (
    tester,
  ) async {
    final f = _fixture(interval: const Duration(milliseconds: 20));
    addTearDown(f.dispose);

    f.sampler.start();
    f.sampler.start();
    f.stat.writeAsStringSync(_busyStat);
    await tester.pump(const Duration(milliseconds: 21));
    expect(f.samples, hasLength(1));
  });

  testWidgets('dispose while paused never revives the sampler', (tester) async {
    final f = _fixture();
    addTearDown(f.dispose);

    f.sampler.start();
    f.sampler.pause();
    f.sampler.dispose();
    f.sampler.resume();
    await tester.pump(const Duration(milliseconds: 20));
    expect(f.sampler.isRunning, isFalse);
    expect(f.samples, isEmpty);
  });

  testWidgets('dispose during the resume prime drops the pending sample', (
    tester,
  ) async {
    final f = _fixture();
    addTearDown(f.dispose);

    f.sampler.start(paused: true);
    f.sampler.resume();
    f.sampler.dispose();
    await tester.pump(const Duration(milliseconds: 20));
    expect(f.samples, isEmpty);
  });

  testWidgets('malformed, zero-delta, and reset counters are safe', (
    tester,
  ) async {
    final f = _fixture(interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.stat.writeAsStringSync('not a stat line\n');
    f.sampler.start();
    await tester.pump(const Duration(milliseconds: 11));
    expect(tester.takeException(), isNull);

    // Identical counters and a counter reset both yield no delta/negative
    // delta, which must be ignored rather than thrown or emitted.
    f.stat.writeAsStringSync(_initialStat);
    await tester.pump(const Duration(milliseconds: 11));
    f.stat.writeAsStringSync('cpu  1 0 1 1 0 0 0 0 0 0\n');
    await tester.pump(const Duration(milliseconds: 11));
    expect(tester.takeException(), isNull);
    expect(f.samples, isEmpty);
  });
}
