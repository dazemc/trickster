import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/network.dart';

class _FakeReader implements NetworkReader {
  NetworkKernelReading reading = NetworkKernelReading(
    counters: const {},
    interfaces: const {},
    defaultRouteInterfaces: const {},
  );
  var reads = 0;
  var disposed = 0;

  @override
  NetworkKernelReading read({String? selectedName, String? pinnedName}) {
    reads += 1;
    return reading;
  }

  @override
  void dispose() {
    disposed += 1;
  }
}

class _FakeMetadata implements NetworkMetadataSource {
  final controller = StreamController<NetworkMetadataSnapshot>.broadcast();

  NetworkMetadataSnapshot _current = const NetworkMetadataSnapshot.none();
  var starts = 0;
  var disposes = 0;

  @override
  Stream<NetworkMetadataSnapshot> get snapshots => controller.stream;

  @override
  NetworkMetadataSnapshot get current => _current;

  @override
  Future<void> start() async {
    starts += 1;
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> dispose() async {
    disposes += 1;
    await controller.close();
  }

  void emit(NetworkMetadataSnapshot snapshot) {
    _current = snapshot;
    controller.add(snapshot);
  }
}

NetworkInterfaceInfo _info(
  String name, {
  int ifindex = 2,
  bool physical = true,
  NetworkMedium medium = NetworkMedium.ethernet,
  bool adminUp = true,
  NetworkLink link = NetworkLink.up,
  int? speedMbps,
}) {
  return NetworkInterfaceInfo(
    name: name,
    ifindex: ifindex,
    physical: physical,
    medium: medium,
    adminUp: adminUp,
    link: link,
    speedMbps: speedMbps,
  );
}

NetworkKernelReading _reading({
  required Map<String, int> rx,
  required Map<String, int> tx,
  required Map<String, NetworkInterfaceInfo> interfaces,
  Set<String> routes = const {'enp42s0'},
}) {
  return NetworkKernelReading(
    counters: {
      for (final entry in rx.entries)
        entry.key: NetDevCounters(
          rxBytes: entry.value,
          txBytes: tx[entry.key] ?? 0,
        ),
    },
    interfaces: interfaces,
    defaultRouteInterfaces: routes,
  );
}

typedef _Fixture = ({
  NetworkSampler sampler,
  _FakeReader reader,
  List<NetworkSample> samples,
  int Function() now,
  void Function(int) setNow,
});

_Fixture _fixture({
  String? interface,
  NetworkMetadataSource? metadata,
  Duration interval = const Duration(seconds: 1),
}) {
  final reader = _FakeReader();
  var now = 0;
  final sampler = NetworkSampler(
    interval: interval,
    interface: interface,
    reader: reader,
    metadata: metadata,
    nowMicros: () => now,
    log: (_) {},
  );
  final samples = <NetworkSample>[];
  final subscription = sampler.snapshots.listen(samples.add);
  addTearDown(() async {
    await subscription.cancel();
    await sampler.dispose();
  });
  return (
    sampler: sampler,
    reader: reader,
    samples: samples,
    now: () => now,
    setNow: (value) => now = value,
  );
}

void main() {
  testWidgets('the first sample has totals and null rates', (tester) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000},
      tx: {'enp42s0': 2000},
      interfaces: {'enp42s0': _info('enp42s0', speedMbps: 1000)},
    );

    f.sampler.start();
    await tester.pump();
    expect(f.sampler.isRunning, isTrue);
    expect(f.reader.reads, 1);
    expect(f.samples, hasLength(1));
    final first = f.samples.single;
    expect(first.interface, 'enp42s0');
    expect(first.rxBytesTotal, 1000);
    expect(first.txBytesTotal, 2000);
    expect(first.rxBytesPerSecond, isNull);
    expect(first.txBytesPerSecond, isNull);
    expect(first.pillState, NetworkPillState.ethernet);
    expect(first.ethernetSpeedMbps, 1000);
  });

  testWidgets('rates divide by actual elapsed time, not the interval', (
    tester,
  ) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000},
      tx: {'enp42s0': 2000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.sampler.start();
    await tester.pump();

    f.reader.reading = _reading(
      rx: {'enp42s0': 2500},
      tx: {'enp42s0': 3500},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.setNow(1500000);
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples, hasLength(2));
    // 1500 bytes / 1.5 s = 1000 B/s; 1500 bytes / 1.5 s = 1000 B/s.
    expect(f.samples.last.rxBytesPerSecond, 1000);
    expect(f.samples.last.txBytesPerSecond, 1000);
  });

  testWidgets('a counter reset reports null rates then recovers', (
    tester,
  ) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 10000},
      tx: {'enp42s0': 20000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.sampler.start();
    await tester.pump();

    f.setNow(1000000);
    f.reader.reading = _reading(
      rx: {'enp42s0': 100},
      tx: {'enp42s0': 200},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples.last.rxBytesPerSecond, isNull);
    expect(f.samples.last.rxBytesTotal, 100);

    f.setNow(2000000);
    f.reader.reading = _reading(
      rx: {'enp42s0': 1100},
      tx: {'enp42s0': 1200},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples.last.rxBytesPerSecond, 1000);
    expect(f.samples.last.txBytesPerSecond, 1000);
  });

  testWidgets('an interface change resets the baseline and never aggregates', (
    tester,
  ) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000, 'wg0': 900000},
      tx: {'enp42s0': 2000, 'wg0': 800000},
      interfaces: {
        'enp42s0': _info('enp42s0', ifindex: 2),
        'wg0': _info('wg0', ifindex: 9, physical: false),
      },
      routes: const {'wg0'},
    );
    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.interface, 'enp42s0');
    expect(f.samples.single.rxBytesTotal, 1000);
    expect(f.samples.single.rxBytesPerSecond, isNull);

    f.reader.reading = _reading(
      rx: {'wlan0': 500, 'wg0': 999999},
      tx: {'wlan0': 600, 'wg0': 888888},
      interfaces: {
        'wlan0': _info(
          'wlan0',
          ifindex: 3,
          medium: NetworkMedium.wifi,
          speedMbps: null,
        ),
        'wg0': _info('wg0', ifindex: 9, physical: false),
      },
      routes: const {'wlan0'},
    );
    f.setNow(1000000);
    await tester.pump(const Duration(seconds: 1));
    final next = f.samples.last;
    expect(next.interface, 'wlan0');
    expect(next.rxBytesTotal, 500);
    expect(next.rxBytesPerSecond, isNull);
    expect(next.txBytesPerSecond, isNull);
    expect(next.pillState, NetworkPillState.wifi);
    expect(next.ethernetSpeedMbps, isNull);
  });

  testWidgets('a link flap resets rates and shows the new link state', (
    tester,
  ) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000},
      tx: {'enp42s0': 2000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.sampler.start();
    await tester.pump();

    f.reader.reading = _reading(
      rx: {'enp42s0': 2000},
      tx: {'enp42s0': 3000},
      interfaces: {
        'enp42s0': _info('enp42s0', link: NetworkLink.down, adminUp: true),
      },
    );
    f.setNow(1000000);
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples.last.link, NetworkLink.down);
    expect(f.samples.last.pillState, NetworkPillState.disconnected);
    expect(f.samples.last.rxBytesPerSecond, isNull);

    f.reader.reading = _reading(
      rx: {'enp42s0': 3000},
      tx: {'enp42s0': 4000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.setNow(2000000);
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples.last.link, NetworkLink.up);
    expect(
      f.samples.last.ethernetSpeedMbps,
      isNull,
      reason: 'the fake ethernet interface publishes no speed',
    );
    expect(f.samples.last.rxBytesPerSecond, isNull);
  });

  testWidgets('an administrative down link is Off not Disconnected', (
    tester,
  ) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000},
      tx: {'enp42s0': 2000},
      interfaces: {
        'enp42s0': _info('enp42s0', adminUp: false, link: NetworkLink.down),
      },
      routes: const {},
    );
    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.pillState, NetworkPillState.disabled);
    expect(f.samples.single.rxBytesPerSecond, isNull);
  });

  testWidgets('a missing interface hides once and does not resurrect', (
    tester,
  ) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000},
      tx: {'enp42s0': 2000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.sampler.start();
    await tester.pump();
    expect(f.samples, hasLength(1));

    f.reader.reading = NetworkKernelReading(
      counters: const {},
      interfaces: const {},
      defaultRouteInterfaces: const {},
    );
    f.setNow(1000000);
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples, hasLength(2));
    expect(f.samples.last.visible, isFalse);

    f.setNow(2000000);
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples, hasLength(2));
  });

  testWidgets('a pinned missing interface stays hidden and quiet', (
    tester,
  ) async {
    final f = _fixture(interface: 'wg0');
    f.reader.reading = NetworkKernelReading(
      counters: const {},
      interfaces: const {},
      defaultRouteInterfaces: const {},
    );
    f.sampler.start();
    await tester.pump();
    expect(f.sampler.isRunning, isTrue);
    expect(f.samples, isEmpty);
  });

  testWidgets('pause stops the timer and resume reports a fresh baseline', (
    tester,
  ) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000},
      tx: {'enp42s0': 2000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.sampler.start();
    await tester.pump();
    expect(f.reader.reads, 1);

    f.setNow(1000000);
    f.reader.reading = _reading(
      rx: {'enp42s0': 2000},
      tx: {'enp42s0': 3000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples, hasLength(2));
    expect(f.samples.last.rxBytesPerSecond, 1000);

    f.sampler.pause();
    expect(f.sampler.isRunning, isFalse);
    f.setNow(60000000);
    await tester.pump(const Duration(seconds: 60));
    expect(f.reader.reads, 2);
    expect(f.samples, hasLength(2));

    f.sampler.resume();
    await tester.pump();
    expect(f.sampler.isRunning, isTrue);
    expect(f.reader.reads, 3);
    expect(f.samples, hasLength(3));
    expect(f.samples.last.rxBytesPerSecond, isNull);
    expect(f.samples.last.txBytesPerSecond, isNull);
    expect(f.samples.last.rxBytesTotal, 2000);
  });

  testWidgets('a paused start does no work until resumed', (tester) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000},
      tx: {'enp42s0': 2000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.sampler.start(paused: true);
    expect(f.sampler.isRunning, isFalse);
    await tester.pump(const Duration(seconds: 60));
    expect(f.reader.reads, 0);
    expect(f.samples, isEmpty);

    f.sampler.resume();
    await tester.pump();
    expect(f.reader.reads, 1);
    expect(f.samples.single.rxBytesPerSecond, isNull);
  });

  testWidgets('dispose is terminal and disposes the reader once', (
    tester,
  ) async {
    final f = _fixture();
    f.reader.reading = _reading(
      rx: {'enp42s0': 1000},
      tx: {'enp42s0': 2000},
      interfaces: {'enp42s0': _info('enp42s0')},
    );
    f.sampler.start();
    await tester.pump();
    await f.sampler.dispose();
    await f.sampler.dispose();
    f.sampler.resume();
    await tester.pump(const Duration(seconds: 2));
    expect(f.sampler.isRunning, isFalse);
    expect(f.reader.disposed, 1);
    expect(f.samples, hasLength(1));
  });

  testWidgets('metadata enriches the selected interface and preserves rates', (
    tester,
  ) async {
    final metadata = _FakeMetadata();
    final f = _fixture(metadata: metadata);
    f.reader.reading = _reading(
      rx: {'wlan0': 1000},
      tx: {'wlan0': 2000},
      interfaces: {
        'wlan0': _info('wlan0', ifindex: 3, medium: NetworkMedium.wifi),
      },
      routes: const {'wlan0'},
    );
    f.sampler.start();
    await tester.pump();
    expect(metadata.starts, 1);
    expect(f.samples.single.source, NetworkSource.kernel);
    expect(f.samples.single.ssid, isNull);

    f.reader.reading = _reading(
      rx: {'wlan0': 2000},
      tx: {'wlan0': 3000},
      interfaces: {
        'wlan0': _info('wlan0', ifindex: 3, medium: NetworkMedium.wifi),
      },
      routes: const {'wlan0'},
    );
    f.setNow(1000000);
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples.last.rxBytesPerSecond, 1000);

    metadata.emit(
      const NetworkMetadataSnapshot(
        service: NetworkMetadataServiceKind.networkManager,
        devices: {
          'wlan0': NetworkDeviceMetadata(
            medium: NetworkMedium.wifi,
            status: NetworkStatus.online,
            ssid: 'home',
            signalPercent: 72,
            frequencyMhz: 5180,
          ),
        },
      ),
    );
    await tester.pump();
    final enriched = f.samples.last;
    expect(enriched.interface, 'wlan0');
    expect(enriched.ssid, 'home');
    expect(enriched.signalPercent, 72);
    expect(enriched.frequencyMhz, 5180);
    expect(enriched.band, WifiBand.band5);
    expect(enriched.status, NetworkStatus.online);
    expect(enriched.source, NetworkSource.networkManager);
    expect(enriched.pillState, NetworkPillState.wifi);
    expect(enriched.rxBytesPerSecond, 1000);
    expect(enriched.txBytesPerSecond, 1000);
  });

  testWidgets('an interface change drops metadata for the old name', (
    tester,
  ) async {
    final metadata = _FakeMetadata();
    final f = _fixture(metadata: metadata);
    f.reader.reading = _reading(
      rx: {'wlan0': 1000},
      tx: {'wlan0': 2000},
      interfaces: {
        'wlan0': _info('wlan0', ifindex: 3, medium: NetworkMedium.wifi),
      },
      routes: const {'wlan0'},
    );
    f.sampler.start();
    await tester.pump();
    metadata.emit(
      const NetworkMetadataSnapshot(
        service: NetworkMetadataServiceKind.networkManager,
        devices: {
          'wlan0': NetworkDeviceMetadata(
            medium: NetworkMedium.wifi,
            status: NetworkStatus.online,
            ssid: 'home',
            signalPercent: 80,
            frequencyMhz: 2412,
          ),
        },
      ),
    );
    await tester.pump();
    expect(f.samples.last.ssid, 'home');

    f.reader.reading = _reading(
      rx: {'enp42s0': 500},
      tx: {'enp42s0': 600},
      interfaces: {'enp42s0': _info('enp42s0', ifindex: 2)},
      routes: const {'enp42s0'},
    );
    f.setNow(1000000);
    await tester.pump(const Duration(seconds: 1));
    final switched = f.samples.last;
    expect(switched.interface, 'enp42s0');
    expect(switched.ssid, isNull);
    expect(switched.signalPercent, isNull);
    expect(switched.frequencyMhz, isNull);
    expect(switched.band, WifiBand.unknown);
    expect(switched.source, NetworkSource.kernel);
  });

  testWidgets('metadata while paused is stored but not painted', (
    tester,
  ) async {
    final metadata = _FakeMetadata();
    final f = _fixture(metadata: metadata);
    f.reader.reading = _reading(
      rx: {'wlan0': 1000},
      tx: {'wlan0': 2000},
      interfaces: {
        'wlan0': _info('wlan0', ifindex: 3, medium: NetworkMedium.wifi),
      },
      routes: const {'wlan0'},
    );
    f.sampler.start();
    await tester.pump();
    expect(f.samples, hasLength(1));

    f.sampler.pause();
    metadata.emit(
      const NetworkMetadataSnapshot(
        service: NetworkMetadataServiceKind.networkManager,
        devices: {
          'wlan0': NetworkDeviceMetadata(
            medium: NetworkMedium.wifi,
            status: NetworkStatus.online,
            ssid: 'home',
          ),
        },
      ),
    );
    await tester.pump();
    expect(f.samples, hasLength(1));

    f.sampler.resume();
    await tester.pump();
    expect(f.samples, hasLength(2));
    expect(f.samples.last.ssid, 'home');
    expect(f.samples.last.source, NetworkSource.networkManager);
  });

  testWidgets('losing the metadata owner clears identity fields', (
    tester,
  ) async {
    final metadata = _FakeMetadata();
    final f = _fixture(metadata: metadata);
    f.reader.reading = _reading(
      rx: {'wlan0': 1000},
      tx: {'wlan0': 2000},
      interfaces: {
        'wlan0': _info('wlan0', ifindex: 3, medium: NetworkMedium.wifi),
      },
      routes: const {'wlan0'},
    );
    f.sampler.start();
    await tester.pump();
    metadata.emit(
      const NetworkMetadataSnapshot(
        service: NetworkMetadataServiceKind.networkManager,
        devices: {
          'wlan0': NetworkDeviceMetadata(
            medium: NetworkMedium.wifi,
            status: NetworkStatus.online,
            ssid: 'home',
            signalPercent: 72,
          ),
        },
      ),
    );
    await tester.pump();
    expect(f.samples.last.ssid, 'home');

    metadata.emit(const NetworkMetadataSnapshot.none());
    await tester.pump();
    final cleared = f.samples.last;
    expect(cleared.ssid, isNull);
    expect(cleared.signalPercent, isNull);
    expect(cleared.status, NetworkStatus.unknown);
    expect(cleared.source, NetworkSource.kernel);
    expect(cleared.interface, 'wlan0');
  });

  test('sample json round-trips with snake_case keys', () {
    const sample = NetworkSample(
      interface: 'enp42s0',
      medium: NetworkMedium.ethernet,
      link: NetworkLink.up,
      adminUp: true,
      defaultRoute: true,
      ethernetSpeedMbps: 1000,
      rxBytesPerSecond: 1200,
      txBytesPerSecond: 3400,
      rxBytesTotal: 5000,
      txBytesTotal: 6000,
    );
    final json = Map<String, dynamic>.from(sample.toJson());
    expect(json['rx_bytes_per_second'], 1200);
    expect(json['default_route'], isTrue);
    expect(NetworkSample.fromJson(json), sample);
    expect(NetworkSample.fromJson(const {}), const NetworkSample.none());
    expect(
      NetworkSample.fromJson(const {'medium': 'satellite'}).medium,
      NetworkMedium.unknown,
    );
  });
}
