import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/network.dart';

void _write(File file, String contents) {
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _addInterface(
  Directory root,
  Directory devices,
  String name, {
  bool physical = true,
  bool wifi = false,
  String type = '1',
  String flags = '0x1003',
  String operstate = 'up',
  String? carrier = '1',
  String? speed,
  int ifindex = 2,
}) {
  final directory = Directory('${root.path}/$name')
    ..createSync(recursive: true);
  if (physical) {
    final target = Directory('${devices.path}/$name')
      ..createSync(recursive: true);
    Link('${directory.path}/device').createSync(target.path);
  }
  if (wifi) {
    Directory('${directory.path}/wireless').createSync();
  }
  _write(File('${directory.path}/type'), type);
  _write(File('${directory.path}/flags'), flags);
  _write(File('${directory.path}/operstate'), operstate);
  if (carrier != null) {
    _write(File('${directory.path}/carrier'), carrier);
  }
  if (speed != null) {
    _write(File('${directory.path}/speed'), speed);
  }
  _write(File('${directory.path}/ifindex'), '$ifindex');
}

class _KernelFixture {
  _KernelFixture() {
    root = Directory.systemTemp.createTempSync('trickster-net');
    devices = Directory.systemTemp.createTempSync('trickster-net-devices');
    final proc = Directory.systemTemp.createTempSync('trickster-net-proc');
    _procDirectory = proc;
    procDev = File('${proc.path}/dev');
    procRoute = File('${proc.path}/route');
    procV6 = File('${proc.path}/ipv6_route');
    _write(procDev, _devTable);
    _write(procRoute, _routeTable);
    _write(procV6, _v6Table);
  }

  late final Directory root;
  late final Directory devices;
  late final Directory _procDirectory;
  late final File procDev;
  late final File procRoute;
  late final File procV6;

  SystemNetworkReader reader({Duration refresh = Duration.zero}) {
    return SystemNetworkReader(
      netRoot: root,
      procNetDev: procDev,
      procNetRoute: procRoute,
      procNetIpv6Route: procV6,
      interfaceRefresh: refresh,
    );
  }

  void dispose() {
    for (final directory in [root, devices, _procDirectory]) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  }
}

const _devTable = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 11 0 0 0 0 0 0 0 22 0 0 0 0 0 0 0
enp42s0: 1000 0 0 0 0 0 0 0 2000 0 0 0 0 0 0 0
  wg0: 999999 0 0 0 0 0 0 0 888888 0 0 0 0 0 0 0
''';

const _routeTable = '''
Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT
enp42s0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0
docker0\t000011AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0
''';

const _v6Table = '''
00000000000000000000000000000000 00 00000000000000000000000000000000 00 00000000000000000000000000000000 00000064 00000001 00000000 00000003 enp42s0
26010601ca7fe5f60000000000001124 80 00000000000000000000000000000000 00 00000000000000000000000000000000 00000064 00000001 00000000 00000001 enp42s0
''';

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

void main() {
  group('procfs parsers', () {
    test('maps receive and transmit bytes and skips malformed lines', () {
      final counters = parseProcNetDev('$_devTable\nbroken: 1 2\nempty:\n');
      expect(counters['lo'], const NetDevCounters(rxBytes: 11, txBytes: 22));
      expect(
        counters['enp42s0'],
        const NetDevCounters(rxBytes: 1000, txBytes: 2000),
      );
      expect(counters['wg0']?.rxBytes, 999999);
      expect(counters.containsKey('broken'), isFalse);
      expect(counters.containsKey('empty'), isFalse);
      expect(parseProcNetDev('not a table'), isEmpty);
    });

    test('keeps 64-bit counters as integers', () {
      const large = 1234567890123;
      final counters = parseProcNetDev(
        'eth0: $large 0 0 0 0 0 0 0 ${large + 1} 0 0 0 0 0 0 0',
      );
      expect(counters['eth0']?.rxBytes, large);
      expect(counters['eth0']?.txBytes, large + 1);
    });

    test('accepts only IPv4 default routes that are up', () {
      expect(parseIpv4DefaultRoutes(_routeTable), {'enp42s0'});
      expect(
        parseIpv4DefaultRoutes(
          'eth0 00000000 0 0002 0 0 0 00000000\n'
          'eth1 00000000 0 0003 0 0 0 00000000\n'
          'eth2 00000000 0 0003 0 0 0 00FFFFFF\n',
        ),
        {'eth1'},
      );
      expect(
        parseIpv4DefaultRoutes('lo 00000000 0 0003 0 0 0 00000000\n'),
        isEmpty,
      );
    });

    test('accepts only IPv6 default routes that are up', () {
      expect(parseIpv6DefaultRoutes(_v6Table), {'enp42s0'});
      expect(
        parseIpv6DefaultRoutes(
          '00000000000000000000000000000000 00 0 00 0 0 0 0 00000003 eth0\n'
          '00000000000000000000000000000000 00 0 00 0 0 0 0 00000001 lo\n'
          '00000000000000000000000000000000 00 0 00 0 0 0 0 00000000 eth1\n',
        ),
        {'eth0'},
      );
      expect(parseIpv6DefaultRoutes('garbage'), isEmpty);
    });

    test('flags parse both hex spellings', () {
      expect(parseInterfaceFlags('0x1003'), 0x1003);
      expect(parseInterfaceFlags('1003'), 0x1003);
      expect(parseInterfaceFlags(''), isNull);
      expect(parseInterfaceFlags('nope'), isNull);
    });

    test('link state prefers carrier and falls back to operstate', () {
      expect(parseLinkState(carrier: '1', operstate: 'down'), NetworkLink.up);
      expect(parseLinkState(carrier: '0', operstate: 'up'), NetworkLink.down);
      expect(parseLinkState(operstate: 'up'), NetworkLink.up);
      expect(parseLinkState(operstate: 'dormant'), NetworkLink.down);
      expect(parseLinkState(operstate: 'lowerlayerdown'), NetworkLink.down);
      expect(parseLinkState(operstate: 'wat'), NetworkLink.unknown);
      expect(parseLinkState(), NetworkLink.unknown);
    });

    test('only a positive speed is a reading', () {
      expect(parseLinkSpeed('1000'), 1000);
      expect(parseLinkSpeed('-1'), isNull);
      expect(parseLinkSpeed('0'), isNull);
      expect(parseLinkSpeed('fast'), isNull);
    });
  });

  group('interface selection', () {
    test('a physical default-route interface wins', () {
      final selected = selectNetworkInterface(
        pinned: null,
        interfaces: {
          'enp42s0': _info('enp42s0', ifindex: 2),
          'wlan0': _info(
            'wlan0',
            ifindex: 3,
            medium: NetworkMedium.wifi,
            link: NetworkLink.down,
            adminUp: false,
            speedMbps: null,
          ),
        },
        defaultRouteInterfaces: {'enp42s0'},
      );
      expect(selected?.name, 'enp42s0');
    });

    test('a tunnel default route never becomes the sampled interface', () {
      final selected = selectNetworkInterface(
        pinned: null,
        interfaces: {
          'wg0': _info('wg0', ifindex: 9, physical: false, speedMbps: null),
          'wlan0': _info(
            'wlan0',
            ifindex: 3,
            medium: NetworkMedium.wifi,
            speedMbps: null,
          ),
        },
        defaultRouteInterfaces: {'wg0'},
      );
      expect(selected?.name, 'wlan0');
    });

    test('loopback and virtual interfaces are ignored in auto mode', () {
      final selected = selectNetworkInterface(
        pinned: null,
        interfaces: {
          'lo': _info('lo', ifindex: 1, physical: false),
          'docker0': _info('docker0', ifindex: 4, physical: false),
          'veth1': _info('veth1', ifindex: 5, physical: false),
          'enp42s0': _info('enp42s0', ifindex: 2),
        },
        defaultRouteInterfaces: const {},
      );
      expect(selected?.name, 'enp42s0');
    });

    test(
      'the lowest ifindex physical interface still represents a dead link',
      () {
        final selected = selectNetworkInterface(
          pinned: null,
          interfaces: {
            'wlan0': _info(
              'wlan0',
              ifindex: 3,
              medium: NetworkMedium.wifi,
              link: NetworkLink.down,
              adminUp: true,
            ),
            'enp42s0': _info(
              'enp42s0',
              ifindex: 2,
              link: NetworkLink.down,
              adminUp: true,
            ),
          },
          defaultRouteInterfaces: const {},
        );
        expect(selected?.name, 'enp42s0');
      },
    );

    test('no physical interface means no selection', () {
      final selected = selectNetworkInterface(
        pinned: null,
        interfaces: {
          'lo': _info('lo', ifindex: 1, physical: false),
          'docker0': _info('docker0', ifindex: 2, physical: false),
        },
        defaultRouteInterfaces: const {},
      );
      expect(selected, isNull);
    });

    test('a pinned virtual or missing interface is honored', () {
      final interfaces = {'wg0': _info('wg0', ifindex: 9, physical: false)};
      expect(
        selectNetworkInterface(
          pinned: 'wg0',
          interfaces: interfaces,
          defaultRouteInterfaces: const {},
        )?.name,
        'wg0',
      );
      expect(
        selectNetworkInterface(
          pinned: 'missing0',
          interfaces: interfaces,
          defaultRouteInterfaces: const {},
        ),
        isNull,
      );
    });
  });

  group('sysfs reader', () {
    late _KernelFixture fixture;

    setUp(() => fixture = _KernelFixture());
    tearDown(() => fixture.dispose());

    test('discovers physical and virtual interfaces, not symlink targets', () {
      _addInterface(
        fixture.root,
        fixture.devices,
        'enp42s0',
        ifindex: 2,
        speed: '1000',
      );
      _addInterface(
        fixture.root,
        fixture.devices,
        'wlan0',
        ifindex: 3,
        wifi: true,
        speed: null,
        flags: '0x1002',
        operstate: 'down',
        carrier: null,
      );
      Directory('${fixture.root.path}/wg0').createSync();
      _write(File('${fixture.root.path}/wg0/flags'), '0x1003');
      _write(File('${fixture.root.path}/wg0/operstate'), 'up');
      Directory('${fixture.root.path}/lo').createSync();
      _write(File('${fixture.root.path}/lo/flags'), '0x1003');
      _write(File('${fixture.root.path}/lo/operstate'), 'unknown');
      _write(File('${fixture.root.path}/lo/carrier'), '1');

      final reading = fixture.reader().read();
      expect(reading.interfaces['enp42s0']?.physical, isTrue);
      expect(reading.interfaces['enp42s0']?.medium, NetworkMedium.ethernet);
      expect(reading.interfaces['enp42s0']?.link, NetworkLink.up);
      expect(reading.interfaces['enp42s0']?.adminUp, isTrue);
      expect(reading.interfaces['enp42s0']?.speedMbps, 1000);
      expect(reading.interfaces['wlan0']?.physical, isTrue);
      expect(reading.interfaces['wlan0']?.medium, NetworkMedium.wifi);
      expect(reading.interfaces['wlan0']?.link, NetworkLink.down);
      expect(reading.interfaces['wlan0']?.adminUp, isFalse);
      expect(reading.interfaces['wg0']?.physical, isFalse);
      expect(reading.interfaces['lo']?.physical, isFalse);
      expect(reading.defaultRouteInterfaces, {'enp42s0'});
      expect(reading.counters['enp42s0']?.rxBytes, 1000);
      expect(reading.counters['wg0']?.rxBytes, 999999);
    });

    test(
      'detects Wi-Fi through phy80211 and a dangling device link as virtual',
      () {
        final target = Directory('${fixture.devices.path}/phy')..createSync();
        final wlan = Directory('${fixture.root.path}/wlan0')..createSync();
        Link('${wlan.path}/device').createSync(target.path);
        Link('${wlan.path}/phy80211').createSync(target.path);
        _write(File('${wlan.path}/type'), '1');
        _write(File('${wlan.path}/flags'), '0x1003');
        _write(File('${wlan.path}/operstate'), 'up');
        _write(File('${wlan.path}/carrier'), '1');
        _write(File('${wlan.path}/ifindex'), '3');

        final dangling = Directory('${fixture.root.path}/usb0')..createSync();
        Link(
          '${dangling.path}/device',
        ).createSync('${fixture.devices.path}/gone');
        _write(File('${dangling.path}/flags'), '0x1003');
        _write(File('${dangling.path}/operstate'), 'up');
        _write(File('${dangling.path}/carrier'), '1');
        _write(File('${dangling.path}/ifindex'), '4');

        final reading = fixture.reader().read();
        expect(reading.interfaces['wlan0']?.medium, NetworkMedium.wifi);
        expect(reading.interfaces['wlan0']?.physical, isTrue);
        expect(reading.interfaces['usb0']?.physical, isFalse);
      },
    );

    test('the selected interface refreshes without a full enumeration', () {
      _addInterface(
        fixture.root,
        fixture.devices,
        'enp42s0',
        ifindex: 2,
        speed: '1000',
      );
      final reader = fixture.reader(refresh: const Duration(hours: 1));
      final first = reader.read(selectedName: 'enp42s0');
      expect(first.interfaces['enp42s0']?.link, NetworkLink.up);

      _write(File('${fixture.root.path}/enp42s0/carrier'), '0');
      _write(File('${fixture.root.path}/enp42s0/operstate'), 'down');
      _write(File('${fixture.root.path}/enp42s0/flags'), '0x1002');
      final second = reader.read(selectedName: 'enp42s0');
      expect(second.interfaces['enp42s0']?.link, NetworkLink.down);
      expect(second.interfaces['enp42s0']?.adminUp, isFalse);
      expect(second.interfaces['enp42s0']?.speedMbps, isNull);
    });

    test('a vanished selected interface is removed', () {
      _addInterface(fixture.root, fixture.devices, 'enp42s0', ifindex: 2);
      final reader = fixture.reader(refresh: const Duration(hours: 1));
      expect(
        reader.read(selectedName: 'enp42s0').interfaces['enp42s0'],
        isNotNull,
      );
      Directory('${fixture.root.path}/enp42s0').deleteSync(recursive: true);
      expect(
        reader.read(selectedName: 'enp42s0').interfaces.containsKey('enp42s0'),
        isFalse,
      );
    });

    test('missing procfs tables do not lose the interface cache', () {
      _addInterface(fixture.root, fixture.devices, 'enp42s0', ifindex: 2);
      fixture.procDev.deleteSync();
      fixture.procRoute.deleteSync();
      fixture.procV6.deleteSync();
      final reading = fixture.reader().read();
      expect(reading.counters, isEmpty);
      expect(reading.defaultRouteInterfaces, isEmpty);
      expect(reading.interfaces.containsKey('enp42s0'), isTrue);
    });

    test('a missing pin is not re-enumerated on every read', () {
      _addInterface(fixture.root, fixture.devices, 'enp42s0', ifindex: 2);
      final reader = fixture.reader(refresh: const Duration(hours: 1));
      expect(
        reader.read(pinnedName: 'wlan9').interfaces.containsKey('wlan9'),
        isFalse,
      );
      _addInterface(fixture.root, fixture.devices, 'wlan9', ifindex: 3);
      expect(
        reader.read(pinnedName: 'wlan9').interfaces.containsKey('wlan9'),
        isFalse,
        reason: 'identity enumeration is throttled, not per tick',
      );
    });

    test('the real kernel read is coherent', () {
      final reader = SystemNetworkReader();
      addTearDown(reader.dispose);
      final reading = reader.read();
      expect(reading.interfaces.keys, contains('lo'));
      final selected = selectNetworkInterface(
        pinned: null,
        interfaces: reading.interfaces,
        defaultRouteInterfaces: reading.defaultRouteInterfaces,
      );
      if (selected != null) {
        expect(reading.interfaces[selected.name], selected);
        expect(selected.physical, isTrue);
      }
    });
  });
}
