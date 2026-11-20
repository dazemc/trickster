import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/battery.dart';

void main() {
  testWidgets('paused start does no work; resume samples once and resumes', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('trickster-battery');
    addTearDown(() => root.deleteSync(recursive: true));
    final battery = Directory('${root.path}/BAT0')..createSync();
    File('${battery.path}/capacity').writeAsStringSync('87\n');
    File('${battery.path}/status').writeAsStringSync('Charging\n');

    final sampler = BatterySampler(
      interval: const Duration(milliseconds: 20),
      root: root,
    );
    final samples = <BatteryStatus>[];
    final subscription = sampler.snapshots.listen(samples.add);
    addTearDown(subscription.cancel);
    addTearDown(sampler.dispose);

    sampler.start(paused: true);
    expect(sampler.isRunning, isFalse);
    await tester.pump(const Duration(milliseconds: 50));
    expect(samples, isEmpty);

    sampler.resume();
    await tester.pump();
    expect(samples, hasLength(1));
    expect(samples.single.capacity, 87);
    expect(samples.single.charging, isTrue);
    expect(sampler.isRunning, isTrue);

    await tester.pump(const Duration(milliseconds: 20));
    expect(samples, hasLength(2));

    sampler.pause();
    sampler.pause();
    expect(sampler.isRunning, isFalse);
    final pausedCount = samples.length;
    await tester.pump(const Duration(milliseconds: 50));
    expect(samples, hasLength(pausedCount));

    sampler.resume();
    await tester.pump();
    expect(samples, hasLength(pausedCount + 1));

    sampler.dispose();
    final disposedCount = samples.length;
    await tester.pump(const Duration(milliseconds: 50));
    expect(samples, hasLength(disposedCount));
    expect(sampler.isRunning, isFalse);
  });

  testWidgets('a second start does not create a second timer', (tester) async {
    final root = Directory.systemTemp.createTempSync('trickster-battery');
    addTearDown(() => root.deleteSync(recursive: true));
    final battery = Directory('${root.path}/BAT0')..createSync();
    File('${battery.path}/capacity').writeAsStringSync('50\n');
    File('${battery.path}/status').writeAsStringSync('Discharging\n');
    final sampler = BatterySampler(
      interval: const Duration(milliseconds: 20),
      root: root,
    );
    final samples = <BatteryStatus>[];
    final subscription = sampler.snapshots.listen(samples.add);
    addTearDown(subscription.cancel);
    addTearDown(sampler.dispose);

    sampler.start();
    await tester.pump();
    expect(samples, hasLength(1));
    sampler.start();
    await tester.pump(const Duration(milliseconds: 20));
    expect(samples, hasLength(2));
  });
}
