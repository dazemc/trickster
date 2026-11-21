import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/temperature.dart';

Directory _createRoot() {
  final root = Directory.systemTemp.createTempSync('trickster-temperature');
  addTearDown(() => root.deleteSync(recursive: true));
  return root;
}

void _sensor(
  Directory root,
  int index, {
  required String name,
  required Map<String, int> inputs,
  Map<String, String> labels = const {},
}) {
  final directory = Directory('${root.path}/hwmon$index')
    ..createSync(recursive: true);
  File('${directory.path}/name').writeAsStringSync('$name\n');
  inputs.forEach((key, value) {
    File('${directory.path}/$key').writeAsStringSync('$value\n');
  });
  labels.forEach((key, value) {
    File('${directory.path}/$key').writeAsStringSync('$value\n');
  });
}

typedef _Fixture = ({
  TemperatureSampler sampler,
  List<TemperatureSample> samples,
  Future<void> Function() dispose,
});

_Fixture _fixture(
  Directory root, {
  Duration interval = const Duration(hours: 1),
}) {
  final sampler = TemperatureSampler(interval: interval, hwmonRoot: root.path);
  final samples = <TemperatureSample>[];
  final subscription = sampler.snapshots.listen(samples.add);
  return (
    sampler: sampler,
    samples: samples,
    dispose: () async {
      await subscription.cancel();
      sampler.dispose();
    },
  );
}

void main() {
  testWidgets('prefers a CPU sensor and its Tctl reading', (tester) async {
    final root = _createRoot();
    _sensor(
      root,
      0,
      name: 'nvme',
      inputs: {'temp1_input': 40000},
      labels: {'temp1_label': 'Composite'},
    );
    _sensor(
      root,
      1,
      name: 'k10temp',
      inputs: {'temp1_input': 55000, 'temp2_input': 50000},
      labels: {'temp1_label': 'Tctl', 'temp2_label': 'Tdie'},
    );
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples, hasLength(1));
    expect(f.samples.single.celsius, closeTo(55, 1e-9));
    expect(f.samples.single.chip, 'k10temp');
    expect(f.samples.single.label, 'Tctl');
    expect(f.samples.single.isCpu, isTrue);
  });

  testWidgets('prefers a Package sensor over cores on coretemp', (
    tester,
  ) async {
    final root = _createRoot();
    _sensor(
      root,
      0,
      name: 'coretemp',
      inputs: {'temp1_input': 60000, 'temp2_input': 50000},
      labels: {'temp1_label': 'Package id 0', 'temp2_label': 'Core 0'},
    );
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.celsius, closeTo(60, 1e-9));
    expect(f.samples.single.label, 'Package id 0');
    expect(f.samples.single.isCpu, isTrue);
  });

  testWidgets('falls back to the hottest readable sensor', (tester) async {
    final root = _createRoot();
    _sensor(
      root,
      0,
      name: 'nvme',
      inputs: {'temp1_input': 32000},
      labels: {'temp1_label': 'Composite'},
    );
    _sensor(root, 1, name: 'r8169', inputs: {'temp1_input': 45000});
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.celsius, closeTo(45, 1e-9));
    expect(f.samples.single.chip, 'r8169');
    expect(f.samples.single.isCpu, isFalse);
  });

  testWidgets('skips unreadable, malformed, and empty inputs', (tester) async {
    final root = _createRoot();
    _sensor(
      root,
      0,
      name: 'nvme',
      inputs: {'temp1_input': 0, 'temp2_input': 30000, 'temp3_input': 0},
      labels: {'temp1_label': 'Bad', 'temp2_label': 'Good'},
    );
    File('${root.path}/hwmon0/temp1_input').writeAsStringSync('not-a-number');
    File('${root.path}/hwmon0/temp3_input').writeAsStringSync('');
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.celsius, closeTo(30, 1e-9));
    expect(f.samples.single.label, 'Good');
  });

  testWidgets('a root without readers emits no sample', (tester) async {
    final root = _createRoot();
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples, isEmpty);
    expect(f.sampler.isRunning, isTrue);
  });

  testWidgets('start samples immediately and pause stops the timer', (
    tester,
  ) async {
    final root = _createRoot();
    _sensor(
      root,
      0,
      name: 'k10temp',
      inputs: {'temp1_input': 50000},
      labels: {'temp1_label': 'Tctl'},
    );
    final f = _fixture(root, interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples, hasLength(1));
    expect(f.samples.single.celsius, closeTo(50, 1e-9));

    f.sampler.pause();
    expect(f.sampler.isRunning, isFalse);
    File('${root.path}/hwmon0/temp1_input').writeAsStringSync('60000\n');
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.samples, hasLength(1));

    f.sampler.resume();
    await tester.pump();
    expect(f.samples, hasLength(2));
    expect(f.samples.last.celsius, closeTo(60, 1e-9));
    expect(f.samples.last.history, hasLength(2));
  });

  testWidgets('a paused start does no work until resumed', (tester) async {
    final root = _createRoot();
    _sensor(root, 0, name: 'k10temp', inputs: {'temp1_input': 50000});
    final f = _fixture(root, interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.start(paused: true);
    expect(f.sampler.isRunning, isFalse);
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.samples, isEmpty);

    f.sampler.resume();
    await tester.pump();
    expect(f.samples, hasLength(1));
    expect(f.sampler.isRunning, isTrue);
  });

  testWidgets('dispose is terminal and never revives the sampler', (
    tester,
  ) async {
    final root = _createRoot();
    _sensor(root, 0, name: 'k10temp', inputs: {'temp1_input': 50000});
    final f = _fixture(root, interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    f.sampler.dispose();
    f.sampler.dispose();
    f.sampler.resume();
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.sampler.isRunning, isFalse);
    expect(f.samples, hasLength(1));
  });

  testWidgets('removing the only sensor clears a previously visible reading', (
    tester,
  ) async {
    final root = _createRoot();
    _sensor(root, 0, name: 'k10temp', inputs: {'temp1_input': 50000});
    final f = _fixture(root, interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.celsius, closeTo(50, 1e-9));

    Directory('${root.path}/hwmon0').deleteSync(recursive: true);
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.samples, hasLength(2));
    expect(f.samples.last.celsius, isNull);
  });

  test('the series keeps the Celsius cap and appends newest last', () {
    var sample = const TemperatureSample();
    for (var i = 0; i < TemperatureSample.capacity + 5; i++) {
      sample = sample.append(i.toDouble());
    }
    expect(sample.history.length, TemperatureSample.capacity);
    expect(sample.history.first, 5);
    expect(sample.history.last, TemperatureSample.capacity + 4);
    expect(sample.meterHistory.first, closeTo(0.05, 1e-9));
    expect(sample.celsius, TemperatureSample.capacity + 4);
  });

  test('temperature json round-trips', () {
    const sample = TemperatureSample(
      celsius: 55,
      label: 'Tctl',
      chip: 'k10temp',
      isCpu: true,
      history: [50, 55],
    );
    final decoded = TemperatureSample.fromJson(
      Map<String, dynamic>.from(sample.toJson()),
    );
    expect(decoded, sample);
    expect(decoded.toJson()['current'], 55);
    expect(decoded.meterHistory, [0.5, 0.55]);
  });
}
