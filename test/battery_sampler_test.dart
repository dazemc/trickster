import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/battery.dart';

Future<Directory> _temporaryRoot() async {
  final root = await Directory.systemTemp.createTemp('trickster-battery');
  addTearDown(() => root.delete(recursive: true));
  return root;
}

void _writeBattery(Directory root, String capacity, {String? status}) {
  final battery = Directory('${root.path}/BAT0')..createSync();
  File('${battery.path}/capacity').writeAsStringSync('$capacity\n');
  if (status != null) {
    File('${battery.path}/status').writeAsStringSync('$status\n');
  }
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test('reads capacity and charging state asynchronously', () async {
    final root = await _temporaryRoot();
    _writeBattery(root, '87', status: 'Charging');
    final sampler = BatterySampler(
      interval: const Duration(milliseconds: 10),
      root: root,
    );
    final samples = <BatteryStatus>[];
    final subscription = sampler.snapshots.listen(samples.add);
    addTearDown(() async {
      await subscription.cancel();
      sampler.dispose();
    });

    sampler.start();
    await _waitFor(() => samples.isNotEmpty);
    expect(samples.single.capacity, 87);
    expect(samples.single.charging, isTrue);
    expect(sampler.isRunning, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(samples, hasLength(1), reason: 'equal status is deduplicated');
  });

  test('an absent root and a partial battery fall back safely', () async {
    final root = await _temporaryRoot();
    final sampler = BatterySampler(
      interval: const Duration(milliseconds: 10),
      root: root,
    );
    final samples = <BatteryStatus>[];
    final subscription = sampler.snapshots.listen(samples.add);
    addTearDown(() async {
      await subscription.cancel();
      sampler.dispose();
    });

    sampler.start();
    await _waitFor(() => samples.isNotEmpty);
    expect(samples.single.capacity, isNull);
    expect(samples.single.charging, isFalse);

    _writeBattery(root, '50');
    await _waitFor(() => samples.length == 2);
    expect(samples.last.capacity, 50);
    expect(samples.last.charging, isFalse);
  });

  test('a changed reading emits after deduplication', () async {
    final root = await _temporaryRoot();
    _writeBattery(root, '87', status: 'Charging');
    final sampler = BatterySampler(
      interval: const Duration(milliseconds: 10),
      root: root,
    );
    final samples = <BatteryStatus>[];
    final subscription = sampler.snapshots.listen(samples.add);
    addTearDown(() async {
      await subscription.cancel();
      sampler.dispose();
    });

    sampler.start();
    await _waitFor(() => samples.isNotEmpty);
    _writeBattery(root, '42', status: 'Discharging');
    await _waitFor(() => samples.length == 2);
    expect(samples.last.capacity, 42);
    expect(samples.last.charging, isFalse);
  });

  test('a paused start runs no timer until resumed', () async {
    final root = await _temporaryRoot();
    _writeBattery(root, '87', status: 'Charging');
    final sampler = BatterySampler(
      interval: const Duration(milliseconds: 10),
      root: root,
    );
    final samples = <BatteryStatus>[];
    final subscription = sampler.snapshots.listen(samples.add);
    addTearDown(() async {
      await subscription.cancel();
      sampler.dispose();
    });

    sampler.start(paused: true);
    expect(sampler.isRunning, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(samples, isEmpty);

    sampler.resume();
    await _waitFor(() => samples.isNotEmpty);
    expect(samples.single.capacity, 87);
    expect(sampler.isRunning, isTrue);
  });

  test(
    'a read in flight when paused is dropped, then resume samples',
    () async {
      final root = await _temporaryRoot();
      final gate = Completer<BatteryStatus>();
      final sampler = BatterySampler(
        interval: const Duration(hours: 1),
        root: root,
        readStatus: () => gate.future,
      );
      final samples = <BatteryStatus>[];
      final subscription = sampler.snapshots.listen(samples.add);
      addTearDown(() async {
        await subscription.cancel();
        sampler.dispose();
      });

      sampler.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sampler.pause();
      gate.complete(const BatteryStatus(capacity: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(samples, isEmpty);

      sampler.resume();
      await _waitFor(() => samples.isNotEmpty);
      expect(samples.single.capacity, 50);
      expect(sampler.isRunning, isTrue);
    },
  );

  test('dispose while paused never revives the sampler', () async {
    final root = await _temporaryRoot();
    _writeBattery(root, '87', status: 'Charging');
    final sampler = BatterySampler(
      interval: const Duration(milliseconds: 10),
      root: root,
    );
    final samples = <BatteryStatus>[];
    final subscription = sampler.snapshots.listen(samples.add);
    addTearDown(subscription.cancel);

    sampler.start();
    await _waitFor(() => samples.isNotEmpty);
    sampler.pause();
    sampler.dispose();
    final disposedCount = samples.length;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(samples, hasLength(disposedCount));
    expect(sampler.isRunning, isFalse);
  });
}
