import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/network.dart';
import 'package:trickster/src/services/temperature.dart';
import 'package:trickster/src/settings/availability.dart';
import 'package:trickster/src/settings/availability_loader.dart';

List<String> _modules(List<ModuleAvailability> list) => [
  for (final entry in list) entry.module,
];

void main() {
  test('probe reports every missing reason in strip order', () {
    final unavailable = probeModuleAvailability(
      settings: const BarSettings(
        disk: DiskOptions(path: '/definitely/missing'),
        network: NetworkOptions(interface: 'missing0'),
      ),
      hasBattery: () => false,
      hasVram: () => false,
      hasTemperature: () => false,
      hasDisk: () => false,
      hasNetwork: () => false,
      hasHyprland: () => false,
    );
    expect(_modules(unavailable), [
      'vram',
      'temperature',
      'disk',
      'keyboard_layout',
      'battery',
      'network',
    ]);
    expect(unavailable.map((entry) => entry.reason), [
      ModuleUnavailableReason.noVram,
      ModuleUnavailableReason.noTemperature,
      ModuleUnavailableReason.noDisk,
      ModuleUnavailableReason.noHyprland,
      ModuleUnavailableReason.noBattery,
      ModuleUnavailableReason.noNetwork,
    ]);
  });

  test('probe is empty when every seam reports available', () {
    expect(
      probeModuleAvailability(
        hasBattery: () => true,
        hasVram: () => true,
        hasTemperature: () => true,
        hasDisk: () => true,
        hasNetwork: () => true,
        hasHyprland: () => true,
      ),
      isEmpty,
    );
  });

  test('probe isolates a single missing sensor', () {
    final unavailable = probeModuleAvailability(
      hasBattery: () => true,
      hasVram: () => true,
      hasTemperature: () => false,
      hasDisk: () => true,
      hasNetwork: () => true,
      hasHyprland: () => true,
    );
    expect(_modules(unavailable), ['temperature']);
    expect(unavailable.single.reason, ModuleUnavailableReason.noTemperature);
  });

  test('bar status overrides the ambient keyboard probe', () async {
    const offlineProbe = <ModuleAvailability>[
      ModuleAvailability(
        module: 'keyboard_layout',
        reason: ModuleUnavailableReason.noHyprland,
      ),
    ];
    final online = await loadModuleAvailability(
      settings: const BarSettings(),
      probe: (_) => offlineProbe,
      request: () async => <String, Object?>{
        'ok': true,
        'state': {
          'keyboard_layout': {'available': true},
        },
      },
    );
    expect(online, isEmpty);

    final offline = await loadModuleAvailability(
      settings: const BarSettings(),
      probe: (_) => const <ModuleAvailability>[],
      request: () async => <String, Object?>{
        'ok': true,
        'state': {
          'keyboard_layout': {'available': false},
        },
      },
    );
    expect(_modules(offline), ['keyboard_layout']);

    final fallback = await loadModuleAvailability(
      settings: const BarSettings(),
      probe: (_) => offlineProbe,
      request: () async => throw StateError('no bar'),
    );
    expect(fallback, offlineProbe);
  });

  test('bar status applies only a well-formed keyboard state', () {
    const offline = <ModuleAvailability>[
      ModuleAvailability(
        module: 'keyboard_layout',
        reason: ModuleUnavailableReason.noHyprland,
      ),
    ];
    expect(
      _modules(
        applyBarAvailability(offline, {
          'ok': true,
          'state': {
            'keyboard_layout': {'available': true},
          },
        }),
      ),
      isEmpty,
    );
    expect(
      _modules(
        applyBarAvailability(const <ModuleAvailability>[], {
          'ok': true,
          'state': {
            'keyboard_layout': {'available': false},
          },
        }),
      ),
      ['keyboard_layout'],
    );
    expect(applyBarAvailability(const <ModuleAvailability>[], null), isEmpty);
  });

  test('temperature probe reads a hwmon input', () {
    final root = Directory.systemTemp.createTempSync('trickster-hwmon');
    addTearDown(() => root.deleteSync(recursive: true));
    final chip = Directory('${root.path}/hwmon0')..createSync();
    expect(TemperatureSampler.hasReadableSensor(hwmonRoot: root.path), isFalse);
    File('${chip.path}/temp1_input').writeAsStringSync('42000');
    expect(TemperatureSampler.hasReadableSensor(hwmonRoot: root.path), isTrue);
  });

  test('disk probe distinguishes a reachable and missing mount', () {
    final root = Directory.systemTemp.createTempSync('trickster-disk');
    addTearDown(() => root.deleteSync(recursive: true));
    expect(hasDiskMount(root.path), isTrue);
    expect(hasDiskMount('${root.path}/missing'), isFalse);
    expect(hasDiskMount('relative'), isFalse);
  });

  test('network probe accepts physical and pinned interfaces', () {
    final root = Directory.systemTemp.createTempSync('trickster-net');
    addTearDown(() => root.deleteSync(recursive: true));
    expect(hasNetworkInterface(netRoot: root.path), isFalse);

    final physical = Directory('${root.path}/enp1s0')..createSync();
    Directory('${physical.path}/device').createSync();
    expect(hasNetworkInterface(netRoot: root.path), isTrue);
    expect(hasNetworkInterface(netRoot: root.path, pinned: 'enp1s0'), isTrue);
    expect(hasNetworkInterface(netRoot: root.path, pinned: 'tun0'), isFalse);
    Directory('${root.path}/tun0').createSync();
    expect(hasNetworkInterface(netRoot: root.path, pinned: 'tun0'), isTrue);
  });
}
