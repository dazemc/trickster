import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/cpu.dart';

const _initialStat = 'cpu  100 0 100 800 0 0 0 0 0 0\n';
const _busyStat = 'cpu  150 0 150 900 0 0 0 0 0 0\n';
const _loadavg = '0.84 0.71 0.62 1/100 1234\n';
const _online = '0-15\n';

typedef _Fixture = ({
  CpuSampler sampler,
  File stat,
  List<CpuSample> samples,
  Future<void> Function() dispose,
});

_Fixture _fixture({
  Duration interval = const Duration(hours: 1),
  Duration resumePrime = const Duration(milliseconds: 10),
  String? loadavgContents = _loadavg,
  String? onlineContents = _online,
}) {
  final root = Directory.systemTemp.createTempSync('trickster-cpu');
  final cpuInfo = File('${root.path}/cpuinfo')
    ..writeAsStringSync('model name\t: Test CPU\n');
  final stat = File('${root.path}/stat')..writeAsStringSync(_initialStat);
  final loadavg = File('${root.path}/loadavg');
  if (loadavgContents != null) {
    loadavg.writeAsStringSync(loadavgContents);
  }
  final online = File('${root.path}/online');
  if (onlineContents != null) {
    online.writeAsStringSync(onlineContents);
  }
  final sampler = CpuSampler(
    interval: interval,
    resumePrime: resumePrime,
    cpuInfoPath: cpuInfo.path,
    statPath: stat.path,
    loadavgPath: loadavg.path,
    onlineCpusPath: online.path,
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
  test('load average parses the first three fields', () {
    final parsed = parseLoadAverage(_loadavg);
    expect(parsed, isNotNull);
    expect(parsed!.load1, closeTo(0.84, 1e-9));
    expect(parsed.load5, closeTo(0.71, 1e-9));
    expect(parsed.load15, closeTo(0.62, 1e-9));

    expect(parseLoadAverage('0.1 0.2\n'), isNull);
    expect(parseLoadAverage('nope 0.2 0.3\n'), isNull);
    expect(parseLoadAverage('-1 0 0\n'), isNull);
    expect(parseLoadAverage('NaN 0 0\n'), isNull);
    expect(parseLoadAverage('Infinity 0 0\n'), isNull);
  });

  test('online cpu ranges count arithmetically', () {
    expect(parseOnlineCpuCount('0-15\n'), 16);
    expect(parseOnlineCpuCount('0-3,8-11\n'), 8);
    expect(parseOnlineCpuCount('0'), 1);
    expect(parseOnlineCpuCount('0-0\n'), 1);
    expect(parseOnlineCpuCount(''), isNull);
    expect(parseOnlineCpuCount('0-,2'), isNull);
    expect(parseOnlineCpuCount('3-1'), isNull);
    expect(parseOnlineCpuCount('-1'), isNull);
    expect(parseOnlineCpuCount('0-1,'), isNull);
  });

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
    final load = f.samples.single.loadAverage;
    expect(load, isNotNull);
    expect(load!.onlineCores, 16);
    expect(load.load1, closeTo(0.84, 1e-9));
    expect(load.load1Fraction, closeTo(0.0525, 1e-9));
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

  testWidgets('missing load data leaves the CPU sample usable', (tester) async {
    final noLoad = _fixture(
      interval: const Duration(milliseconds: 10),
      loadavgContents: null,
    );
    addTearDown(noLoad.dispose);
    noLoad.sampler.start();
    noLoad.stat.writeAsStringSync(_busyStat);
    await tester.pump(const Duration(milliseconds: 11));
    expect(noLoad.samples, hasLength(1));
    expect(noLoad.samples.single.current, closeTo(0.5, 1e-9));
    expect(noLoad.samples.single.loadAverage, isNull);

    final noCores = _fixture(
      interval: const Duration(milliseconds: 10),
      onlineContents: null,
    );
    addTearDown(noCores.dispose);
    noCores.sampler.start();
    noCores.stat.writeAsStringSync(_busyStat);
    await tester.pump(const Duration(milliseconds: 11));
    expect(noCores.samples, hasLength(1));
    expect(noCores.samples.single.current, closeTo(0.5, 1e-9));
    expect(noCores.samples.single.loadAverage, isNull);
  });

  testWidgets('malformed load files do not break the CPU sample', (
    tester,
  ) async {
    final f = _fixture(
      interval: const Duration(milliseconds: 10),
      loadavgContents: 'nope\n',
      onlineContents: '3-1\n',
    );
    addTearDown(f.dispose);

    f.sampler.start();
    f.stat.writeAsStringSync(_busyStat);
    await tester.pump(const Duration(milliseconds: 11));
    expect(tester.takeException(), isNull);
    expect(f.samples, hasLength(1));
    expect(f.samples.single.current, closeTo(0.5, 1e-9));
    expect(f.samples.single.loadAverage, isNull);
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
