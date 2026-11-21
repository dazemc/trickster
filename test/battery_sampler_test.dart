import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/battery.dart';

Future<Directory> _temporaryRoot() async {
  final root = await Directory.systemTemp.createTemp('trickster-battery');
  addTearDown(() => root.delete(recursive: true));
  return root;
}

void _writeBattery(
  Directory root,
  String capacity, {
  String? status,
  int? energyNow,
  int? energyFull,
  int? powerNow,
  int? chargeNow,
  int? chargeFull,
  int? currentNow,
}) {
  final battery = Directory('${root.path}/BAT0')..createSync();
  void write(String name, Object value) =>
      File('${battery.path}/$name').writeAsStringSync('$value\n');
  write('capacity', capacity);
  if (status != null) {
    write('status', status);
  }
  if (energyNow != null) {
    write('energy_now', energyNow);
  }
  if (energyFull != null) {
    write('energy_full', energyFull);
  }
  if (powerNow != null) {
    write('power_now', powerNow);
  }
  if (chargeNow != null) {
    write('charge_now', chargeNow);
  }
  if (chargeFull != null) {
    write('charge_full', chargeFull);
  }
  if (currentNow != null) {
    write('current_now', currentNow);
  }
}

Future<BatteryStatus> _sampleOnce(Directory root) async {
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
  return samples.first;
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

  test('reads energy-based time to empty', () async {
    final root = await _temporaryRoot();
    _writeBattery(
      root,
      '60',
      status: 'Discharging',
      energyNow: 22400000,
      powerNow: 10000000,
    );

    final status = await _sampleOnce(root);
    expect(status.state, BatteryState.discharging);
    expect(status.charging, isFalse);
    expect(status.energyNow, 22400000);
    expect(status.powerNow, 10000000);
    expect(status.chargeNow, isNull);
    expect(status.currentNow, isNull);
    expect(status.timeToEmpty, const Duration(hours: 2, minutes: 14));
    expect(status.timeToFull, isNull);
  });

  test('reads charge-based time to full', () async {
    final root = await _temporaryRoot();
    _writeBattery(
      root,
      '40',
      status: 'Charging',
      chargeNow: 1000000,
      chargeFull: 3240000,
      currentNow: 1000000,
    );

    final status = await _sampleOnce(root);
    expect(status.state, BatteryState.charging);
    expect(status.charging, isTrue);
    expect(status.chargeNow, 1000000);
    expect(status.chargeFull, 3240000);
    expect(status.currentNow, 1000000);
    expect(status.timeToEmpty, isNull);
    expect(status.timeToFull, const Duration(hours: 2, minutes: 14));
  });

  test('time to full uses the remaining capacity', () async {
    final energyRoot = await _temporaryRoot();
    _writeBattery(
      energyRoot,
      '40',
      status: 'Charging',
      energyNow: 10000000,
      energyFull: 32400000,
      powerNow: 10000000,
    );
    expect(
      (await _sampleOnce(energyRoot)).timeToFull,
      const Duration(hours: 2, minutes: 14),
    );

    final fallbackRoot = await _temporaryRoot();
    _writeBattery(
      fallbackRoot,
      '40',
      status: 'Charging',
      energyNow: 10000000,
      powerNow: 10000000,
      chargeNow: 1000000,
      chargeFull: 3240000,
      currentNow: 1000000,
    );
    expect(
      (await _sampleOnce(fallbackRoot)).timeToFull,
      const Duration(hours: 2, minutes: 14),
    );

    final missingFullRoot = await _temporaryRoot();
    _writeBattery(
      missingFullRoot,
      '40',
      status: 'Charging',
      energyNow: 10000000,
      powerNow: 10000000,
    );
    expect((await _sampleOnce(missingFullRoot)).timeToFull, isNull);

    final atFullRoot = await _temporaryRoot();
    _writeBattery(
      atFullRoot,
      '100',
      status: 'Charging',
      energyNow: 10000000,
      energyFull: 10000000,
      powerNow: 10000000,
    );
    expect((await _sampleOnce(atFullRoot)).timeToFull, isNull);
  });

  test('prefers energy readings and falls back to charge', () async {
    final energyRoot = await _temporaryRoot();
    _writeBattery(
      energyRoot,
      '60',
      status: 'Discharging',
      energyNow: 22400000,
      powerNow: 10000000,
      chargeNow: 10000000,
      currentNow: 1000000,
    );
    expect(
      (await _sampleOnce(energyRoot)).timeToEmpty,
      const Duration(hours: 2, minutes: 14),
    );

    final fallbackRoot = await _temporaryRoot();
    _writeBattery(
      fallbackRoot,
      '60',
      status: 'Discharging',
      energyNow: 22400000,
      chargeNow: 2240000,
      currentNow: 1000000,
    );
    expect(
      (await _sampleOnce(fallbackRoot)).timeToEmpty,
      const Duration(hours: 2, minutes: 14),
    );
  });

  test('full, not charging, and unknown states omit a time', () async {
    final fullRoot = await _temporaryRoot();
    _writeBattery(
      fullRoot,
      '100',
      status: 'Full',
      energyNow: 22400000,
      powerNow: 10000000,
    );
    final full = await _sampleOnce(fullRoot);
    expect(full.state, BatteryState.full);
    expect(full.charging, isTrue);
    expect(full.timeToEmpty, isNull);
    expect(full.timeToFull, isNull);

    final idleRoot = await _temporaryRoot();
    _writeBattery(
      idleRoot,
      '80',
      status: 'Not charging',
      energyNow: 22400000,
      powerNow: 10000000,
    );
    final idle = await _sampleOnce(idleRoot);
    expect(idle.state, BatteryState.notCharging);
    expect(idle.charging, isFalse);
    expect(idle.timeToEmpty, isNull);
    expect(idle.timeToFull, isNull);

    final unknownRoot = await _temporaryRoot();
    _writeBattery(
      unknownRoot,
      '80',
      status: 'Unknown',
      energyNow: 22400000,
      powerNow: 10000000,
    );
    final unknown = await _sampleOnce(unknownRoot);
    expect(unknown.state, BatteryState.unknown);
    expect(unknown.timeToEmpty, isNull);
    expect(unknown.timeToFull, isNull);
  });

  test(
    'missing, zero, and negative readings do not synthesize a time',
    () async {
      final missingRoot = await _temporaryRoot();
      _writeBattery(
        missingRoot,
        '60',
        status: 'Discharging',
        energyNow: 22400000,
      );
      final missing = await _sampleOnce(missingRoot);
      expect(missing.powerNow, isNull);
      expect(missing.timeToEmpty, isNull);

      final zeroRoot = await _temporaryRoot();
      _writeBattery(
        zeroRoot,
        '60',
        status: 'Discharging',
        energyNow: 22400000,
        powerNow: 0,
      );
      expect((await _sampleOnce(zeroRoot)).timeToEmpty, isNull);

      final negativeRoot = await _temporaryRoot();
      _writeBattery(
        negativeRoot,
        '60',
        status: 'Discharging',
        energyNow: -1,
        powerNow: 10000000,
      );
      expect((await _sampleOnce(negativeRoot)).timeToEmpty, isNull);
    },
  );

  test('a negative rate uses its magnitude and rounds to minutes', () async {
    final root = await _temporaryRoot();
    _writeBattery(
      root,
      '60',
      status: 'Discharging',
      energyNow: 2230000,
      powerNow: -1000000,
    );
    expect(
      (await _sampleOnce(root)).timeToEmpty,
      const Duration(hours: 2, minutes: 14),
    );

    final tinyRoot = await _temporaryRoot();
    _writeBattery(
      tinyRoot,
      '60',
      status: 'Discharging',
      energyNow: 1000,
      powerNow: 1000000,
    );
    expect(
      (await _sampleOnce(tinyRoot)).timeToEmpty,
      const Duration(minutes: 1),
    );
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
