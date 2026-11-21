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
  Duration interval = const Duration(seconds: 1),
}) {
  final reader = _FakeReader();
  var now = 0;
  final sampler = NetworkSampler(
    interval: interval,
    interface: interface,
    reader: reader,
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
