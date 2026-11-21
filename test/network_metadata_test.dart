import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/network.dart';
import 'package:trickster/src/services/network_metadata.dart';

const _managerIface = 'org.freedesktop.NetworkManager';
const _deviceIface = 'org.freedesktop.NetworkManager.Device';
const _wiredIface = 'org.freedesktop.NetworkManager.Device.Wired';
const _wirelessIface = 'org.freedesktop.NetworkManager.Device.Wireless';
const _apIface = 'org.freedesktop.NetworkManager.AccessPoint';
const _managerPath = '/org/freedesktop/NetworkManager';
const _managerName = 'org.freedesktop.NetworkManager';
const _iwdName = 'net.connman.iwd';

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeBus {
  _FakeBus._(this.server, this.address, this.directory);

  final DBusServer server;
  final DBusAddress address;
  final Directory directory;

  static Future<_FakeBus> start() async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-network-metadata',
    );
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress('unix:path=${directory.path}/bus'),
    );
    return _FakeBus._(server, address, directory);
  }

  DBusClient client() => DBusClient(address);

  Future<void> dispose() async {
    await server.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

class _FakeManager extends DBusObject {
  _FakeManager(this.devicePaths) : super(DBusObjectPath(_managerPath));

  final List<String> devicePaths;
  bool networkingEnabled = true;
  bool wirelessEnabled = true;
  bool wirelessHardwareEnabled = true;
  int state = 70;
  int connectivity = 4;
  bool connectivityCheckEnabled = true;
  var getAllCalls = 0;
  var getDevicesCalls = 0;

  Map<String, DBusValue> _properties() => <String, DBusValue>{
    'NetworkingEnabled': DBusBoolean(networkingEnabled),
    'WirelessEnabled': DBusBoolean(wirelessEnabled),
    'WirelessHardwareEnabled': DBusBoolean(wirelessHardwareEnabled),
    'State': DBusUint32(state),
    'Connectivity': DBusUint32(connectivity),
    'ConnectivityCheckEnabled': DBusBoolean(connectivityCheckEnabled),
  };

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _managerIface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    getAllCalls += 1;
    return DBusGetAllPropertiesResponse(_properties());
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != _managerIface || call.name != 'GetDevices') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    getDevicesCalls += 1;
    return DBusMethodSuccessResponse([
      DBusArray(DBusSignature('o'), devicePaths.map(DBusObjectPath.new)),
    ]);
  }

  Future<void> emitChanged() {
    return emitSignal(
      'org.freedesktop.DBus.Properties',
      'PropertiesChanged',
      <DBusValue>[
        DBusString(_managerIface),
        DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
          DBusString('Connectivity'): DBusVariant(DBusUint32(connectivity)),
        }),
        DBusArray(DBusSignature('s')),
      ],
    );
  }
}

class _FakeDevice extends DBusObject {
  _FakeDevice({
    required String path,
    required this.interface,
    required this.deviceType,
    this.accessPointPath,
    this.wiredSpeed,
  }) : super(DBusObjectPath(path));

  final String interface;
  final int deviceType;
  int state = 100;
  String? accessPointPath;
  int? wiredSpeed;
  var getAllCalls = 0;

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    getAllCalls += 1;
    if (interface == _deviceIface) {
      return DBusGetAllPropertiesResponse(<String, DBusValue>{
        'Interface': DBusString(this.interface),
        'DeviceType': DBusUint32(deviceType),
        'State': DBusUint32(state),
      });
    }
    if (interface == _wiredIface && wiredSpeed != null) {
      return DBusGetAllPropertiesResponse(<String, DBusValue>{
        'Speed': DBusUint32(wiredSpeed!),
      });
    }
    if (interface == _wirelessIface) {
      return DBusGetAllPropertiesResponse(<String, DBusValue>{
        'ActiveAccessPoint': DBusObjectPath(accessPointPath ?? '/'),
      });
    }
    return DBusMethodErrorResponse.unknownInterface();
  }
}

class _FakeAccessPoint extends DBusObject {
  _FakeAccessPoint({required String path, required this.ssid})
    : super(DBusObjectPath(path));

  String ssid;
  int strength = 72;
  int frequency = 5180;

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != _apIface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(<String, DBusValue>{
      'Ssid': DBusArray.byte(utf8.encode(ssid)),
      'Strength': DBusByte(strength),
      'Frequency': DBusUint32(frequency),
    });
  }

  Future<void> emitChanged() {
    return emitSignal(
      'org.freedesktop.DBus.Properties',
      'PropertiesChanged',
      <DBusValue>[
        DBusString(_apIface),
        DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
          DBusString('Strength'): DBusVariant(DBusByte(strength)),
          DBusString('Ssid'): DBusVariant(DBusArray.byte(utf8.encode(ssid))),
        }),
        DBusArray(DBusSignature('s')),
      ],
    );
  }
}

class _FakeIwdRoot extends DBusObject {
  _FakeIwdRoot({
    required this.powered,
    required this.stationState,
    required this.connectedNetworkPath,
    required this.networkName,
  }) : super(DBusObjectPath.root);

  bool powered;
  String stationState;
  String connectedNetworkPath;
  String networkName;
  var getManagedObjectsCalls = 0;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'org.freedesktop.DBus.ObjectManager' ||
        call.name != 'GetManagedObjects') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    getManagedObjectsCalls += 1;
    final devicePath = DBusObjectPath('/net/connman/iwd/0');
    final networkPath = DBusObjectPath(connectedNetworkPath);
    return DBusMethodSuccessResponse([
      DBusDict(
        DBusSignature('o'),
        DBusSignature('a{sa{sv}}'),
        <DBusValue, DBusValue>{
          devicePath: DBusDict(
            DBusSignature('s'),
            DBusSignature('a{sv}'),
            <DBusValue, DBusValue>{
              DBusString('net.connman.iwd.Device'): DBusDict(
                DBusSignature('s'),
                DBusSignature('v'),
                <DBusValue, DBusValue>{
                  DBusString('Name'): DBusVariant(DBusString('wlan0')),
                  DBusString('Powered'): DBusVariant(DBusBoolean(powered)),
                },
              ),
              DBusString('net.connman.iwd.Station'): DBusDict(
                DBusSignature('s'),
                DBusSignature('v'),
                <DBusValue, DBusValue>{
                  DBusString('State'): DBusVariant(DBusString(stationState)),
                  DBusString('ConnectedNetwork'): DBusVariant(
                    DBusObjectPath(connectedNetworkPath),
                  ),
                },
              ),
            },
          ),
          networkPath: DBusDict(
            DBusSignature('s'),
            DBusSignature('a{sv}'),
            <DBusValue, DBusValue>{
              DBusString('net.connman.iwd.Network'): DBusDict(
                DBusSignature('s'),
                DBusSignature('v'),
                <DBusValue, DBusValue>{
                  DBusString('Name'): DBusVariant(DBusString(networkName)),
                },
              ),
            },
          ),
        },
      ),
    ]);
  }
}

class _FakeIwdStation extends DBusObject {
  _FakeIwdStation({required this.networkPath})
    : super(DBusObjectPath('/net/connman/iwd/0'));

  final String networkPath;
  int signalHundredths = -5500;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'net.connman.iwd.Station' ||
        call.name != 'GetOrderedNetworks') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse([
      DBusArray(DBusSignature('(on)'), <DBusValue>[
        DBusStruct(<DBusValue>[
          DBusObjectPath(networkPath),
          DBusInt16(signalHundredths),
        ]),
      ]),
    ]);
  }

  Future<void> emitChanged() {
    return emitSignal(
      'org.freedesktop.DBus.Properties',
      'PropertiesChanged',
      <DBusValue>[
        DBusString('net.connman.iwd.Station'),
        DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
          DBusString('State'): DBusVariant(DBusString('connected')),
        }),
        DBusArray(DBusSignature('s')),
      ],
    );
  }
}

class _NmFixture {
  _NmFixture._({
    required this.bus,
    required this.owner,
    required this.manager,
    required this.devices,
    required this.accessPoints,
    required this.ownsBus,
  });

  final _FakeBus bus;
  final DBusClient owner;
  final _FakeManager manager;
  final Map<String, _FakeDevice> devices;
  final Map<String, _FakeAccessPoint> accessPoints;
  final bool ownsBus;

  static Future<_NmFixture> start({
    bool wifi = true,
    bool ethernet = true,
    int deviceCount = 2,
    _FakeBus? bus,
  }) async {
    final actualBus = bus ?? await _FakeBus.start();
    final owner = actualBus.client();
    final devices = <String, _FakeDevice>{};
    final accessPoints = <String, _FakeAccessPoint>{};
    final paths = <String>[];
    if (wifi) {
      const path = '$_managerPath/Devices/1';
      const apPath = '$_managerPath/AccessPoint/1';
      paths.add(path);
      devices[path] = _FakeDevice(
        path: path,
        interface: 'wlan0',
        deviceType: 2,
        accessPointPath: apPath,
      );
      accessPoints[apPath] = _FakeAccessPoint(path: apPath, ssid: 'home');
      await owner.registerObject(accessPoints[apPath]!);
    }
    if (ethernet) {
      const path = '$_managerPath/Devices/2';
      paths.add(path);
      devices[path] = _FakeDevice(
        path: path,
        interface: 'enp42s0',
        deviceType: 1,
        wiredSpeed: 1000,
      );
    }
    for (var i = paths.length; i < deviceCount; i += 1) {
      final path = '$_managerPath/Devices/${i + 1}';
      paths.add(path);
      devices[path] = _FakeDevice(
        path: path,
        interface: 'eth$i',
        deviceType: 1,
        wiredSpeed: 100,
      );
    }
    final manager = _FakeManager(paths);
    await owner.registerObject(manager);
    for (final entry in devices.entries) {
      await owner.registerObject(entry.value);
    }
    await owner.requestName(_managerName);
    return _NmFixture._(
      bus: actualBus,
      owner: owner,
      manager: manager,
      devices: devices,
      accessPoints: accessPoints,
      ownsBus: bus == null,
    );
  }

  NetworkMetadataService service({
    int maxDevices = 16,
    Duration coalesce = const Duration(milliseconds: 20),
  }) {
    return NetworkMetadataService(
      clientFactory: bus.client,
      readTimeout: const Duration(seconds: 2),
      coalesce: coalesce,
      maxDevices: maxDevices,
    );
  }

  Future<void> dispose() async {
    await owner.close();
    if (ownsBus) {
      await bus.dispose();
    }
  }
}

class _IwdFixture {
  _IwdFixture._({
    required this.bus,
    required this.owner,
    required this.root,
    required this.station,
    required this.ownsBus,
  });

  final _FakeBus bus;
  final DBusClient owner;
  final _FakeIwdRoot root;
  final _FakeIwdStation station;
  final bool ownsBus;

  static Future<_IwdFixture> start({
    bool powered = true,
    String stationState = 'connected',
    _FakeBus? bus,
  }) async {
    final actualBus = bus ?? await _FakeBus.start();
    final owner = actualBus.client();
    final root = _FakeIwdRoot(
      powered: powered,
      stationState: stationState,
      connectedNetworkPath: '/net/connman/iwd/0/1',
      networkName: 'home',
    );
    final station = _FakeIwdStation(networkPath: '/net/connman/iwd/0/1');
    await owner.registerObject(root);
    await owner.registerObject(station);
    await owner.requestName(_iwdName);
    return _IwdFixture._(
      bus: actualBus,
      owner: owner,
      root: root,
      station: station,
      ownsBus: bus == null,
    );
  }

  NetworkMetadataService service({
    Duration coalesce = const Duration(milliseconds: 20),
  }) {
    return NetworkMetadataService(
      clientFactory: bus.client,
      readTimeout: const Duration(seconds: 2),
      coalesce: coalesce,
    );
  }

  Future<void> dispose() async {
    await owner.close();
    if (ownsBus) {
      await bus.dispose();
    }
  }
}

void main() {
  test('classifies NetworkManager device and connectivity states', () {
    NetworkStatus classify({
      bool networking = true,
      bool wireless = true,
      bool check = true,
      NetworkMedium medium = NetworkMedium.wifi,
      int manager = 70,
      int connectivity = 4,
      int device = 100,
    }) {
      return classifyNetworkManagerStatus(
        networkingEnabled: networking,
        wirelessEnabled: wireless,
        connectivityCheckEnabled: check,
        medium: medium,
        managerState: manager,
        connectivity: connectivity,
        deviceState: device,
      );
    }

    expect(classify(networking: false), NetworkStatus.disabled);
    expect(classify(manager: 10), NetworkStatus.disabled);
    expect(classify(wireless: false), NetworkStatus.disabled);
    expect(
      classify(wireless: false, medium: NetworkMedium.ethernet),
      NetworkStatus.online,
    );
    expect(classify(device: 10), NetworkStatus.unknown);
    expect(classify(device: 30), NetworkStatus.disconnected);
    expect(classify(device: 50), NetworkStatus.linked);
    expect(classify(connectivity: 4), NetworkStatus.online);
    expect(classify(connectivity: 3), NetworkStatus.limited);
    expect(classify(connectivity: 2), NetworkStatus.captive);
    expect(classify(connectivity: 1), NetworkStatus.local);
    expect(
      classify(check: false, connectivity: 1, manager: 70),
      NetworkStatus.online,
    );
    expect(
      classify(check: false, connectivity: 1, manager: 50),
      NetworkStatus.local,
    );
    expect(classify(connectivity: 0, manager: 60), NetworkStatus.limited);
  });

  test('classifies iwd state and converts hundredths-dBm', () {
    expect(
      classifyIwdStatus(powered: false, stationState: 'connected'),
      NetworkStatus.disabled,
    );
    expect(
      classifyIwdStatus(powered: true, stationState: 'connected'),
      NetworkStatus.unknown,
    );
    expect(
      classifyIwdStatus(powered: true, stationState: 'connecting'),
      NetworkStatus.linked,
    );
    expect(
      classifyIwdStatus(powered: true, stationState: 'disconnected'),
      NetworkStatus.disconnected,
    );
    expect(signalPercentFromDbmHundredths(-5500), 90);
    expect(signalPercentFromDbmHundredths(-7000), 60);
    expect(signalPercentFromDbmHundredths(-20000), 0);
  });

  test('decodes SSIDs leniently and rejects empty or oversized values', () {
    expect(decodeSsid(utf8.encode('home')), 'home');
    expect(decodeSsid(utf8.encode(' leading')), ' leading');
    expect(decodeSsid(<int>[0xff, 0xfe]), isNotNull);
    expect(decodeSsid(const []), isNull);
    expect(decodeSsid(List<int>.filled(33, 65)), isNull);
    expect(decodeSsid(<int>[0, 1, 2]), isNull);
  });

  test('maps a NetworkManager Wi-Fi and Ethernet device', () async {
    final fixture = await _NmFixture.start();
    final service = fixture.service();
    addTearDown(() async {
      await service.dispose();
      await fixture.dispose();
    });
    await service.start();
    await _waitFor(() => service.current.available);

    final snapshot = service.current;
    expect(snapshot.service, NetworkMetadataServiceKind.networkManager);
    final wifi = snapshot.devices['wlan0'];
    expect(wifi, isNotNull);
    expect(wifi!.status, NetworkStatus.online);
    expect(wifi.ssid, 'home');
    expect(wifi.signalPercent, 72);
    expect(wifi.frequencyMhz, 5180);
    final ethernet = snapshot.devices['enp42s0'];
    expect(ethernet, isNotNull);
    expect(ethernet!.speedMbps, 1000);
    expect(ethernet.status, NetworkStatus.online);
  });

  test(
    'honors networking and wireless disabled without disabling Ethernet',
    () async {
      final fixture = await _NmFixture.start();
      final service = fixture.service();
      addTearDown(() async {
        await service.dispose();
        await fixture.dispose();
      });
      fixture.manager.networkingEnabled = false;
      await service.start();
      await _waitFor(() => service.current.available);
      expect(service.current.devices['wlan0']?.status, NetworkStatus.disabled);
      expect(
        service.current.devices['enp42s0']?.status,
        NetworkStatus.disabled,
      );

      fixture.manager.networkingEnabled = true;
      fixture.manager.wirelessEnabled = false;
      await service.refresh();
      expect(service.current.devices['wlan0']?.status, NetworkStatus.disabled);
      expect(service.current.devices['enp42s0']?.status, NetworkStatus.online);
    },
  );

  test('refreshes once for coalesced signals and never polls', () async {
    final fixture = await _NmFixture.start();
    final service = fixture.service(
      coalesce: const Duration(milliseconds: 100),
    );
    addTearDown(() async {
      await service.dispose();
      await fixture.dispose();
    });
    await service.start();
    await _waitFor(() => service.current.available);
    final initialReads = fixture.manager.getDevicesCalls;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(
      fixture.manager.getDevicesCalls,
      initialReads,
      reason: 'metadata is signal-driven, not polled',
    );

    final ap = fixture.accessPoints.values.single;
    ap.strength = 55;
    ap.ssid = 'home-2';
    await ap.emitChanged();
    await _waitFor(() => service.current.devices['wlan0']?.ssid == 'home-2');
    final beforeBurst = fixture.manager.getDevicesCalls;
    await Future.wait([
      fixture.manager.emitChanged(),
      fixture.manager.emitChanged(),
      fixture.manager.emitChanged(),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(fixture.manager.getDevicesCalls, beforeBurst + 1);
  });

  test('caps device reads at sixteen', () async {
    final fixture = await _NmFixture.start(
      wifi: false,
      ethernet: false,
      deviceCount: 20,
    );
    final service = fixture.service(maxDevices: 16);
    addTearDown(() async {
      await service.dispose();
      await fixture.dispose();
    });
    await service.start();
    await _waitFor(() => service.current.available);
    expect(service.current.devices, hasLength(16));
    final readDevices = fixture.devices.values
        .where((device) => device.getAllCalls > 0)
        .length;
    expect(readDevices, 16);
    final unreadDevices = fixture.devices.values
        .where((device) => device.getAllCalls == 0)
        .length;
    expect(unreadDevices, 4);
  });

  test('owner loss clears metadata and owner return rebuilds it', () async {
    final fixture = await _NmFixture.start();
    final service = fixture.service();
    addTearDown(() async {
      await service.dispose();
      await fixture.dispose();
    });
    await service.start();
    await _waitFor(() => service.current.available);
    expect(service.current.devices, isNotEmpty);

    await fixture.owner.releaseName(_managerName);
    await _waitFor(() => !service.current.available);
    expect(service.current.service, NetworkMetadataServiceKind.none);

    await fixture.owner.requestName(_managerName);
    await _waitFor(() => service.current.available);
    expect(service.current.devices['wlan0']?.ssid, 'home');
  });

  test('NetworkManager wins over iwd when both exist', () async {
    final bus = await _FakeBus.start();
    final nm = await _NmFixture.start(bus: bus);
    final iwd = await _IwdFixture.start(bus: bus);
    final service = NetworkMetadataService(
      clientFactory: bus.client,
      readTimeout: const Duration(seconds: 2),
    );
    addTearDown(() async {
      await service.dispose();
      await nm.dispose();
      await iwd.dispose();
      await bus.dispose();
    });
    await service.start();
    await _waitFor(() => service.current.available);
    expect(service.current.service, NetworkMetadataServiceKind.networkManager);
    expect(iwd.root.getManagedObjectsCalls, 0);

    await nm.owner.releaseName(_managerName);
    await _waitFor(
      () => service.current.service == NetworkMetadataServiceKind.iwd,
    );
    expect(service.current.devices['wlan0']?.ssid, 'home');
  });

  test('reads iwd fallback details and refreshs on its signals', () async {
    final fixture = await _IwdFixture.start();
    final service = fixture.service();
    addTearDown(() async {
      await service.dispose();
      await fixture.dispose();
    });
    await service.start();
    await _waitFor(() => service.current.available);
    final wifi = service.current.devices['wlan0'];
    expect(service.current.service, NetworkMetadataServiceKind.iwd);
    expect(wifi, isNotNull);
    expect(wifi!.ssid, 'home');
    expect(wifi.signalPercent, 90);
    expect(wifi.frequencyMhz, isNull);
    expect(wifi.status, NetworkStatus.unknown);

    fixture.station.signalHundredths = -7000;
    await fixture.station.emitChanged();
    await _waitFor(() => service.current.devices['wlan0']?.signalPercent == 60);
  });

  test('a powered-off iwd device is disabled', () async {
    final fixture = await _IwdFixture.start(
      powered: false,
      stationState: 'disconnected',
    );
    final service = fixture.service();
    addTearDown(() async {
      await service.dispose();
      await fixture.dispose();
    });
    await service.start();
    await _waitFor(() => service.current.available);
    expect(service.current.devices['wlan0']?.status, NetworkStatus.disabled);
  });
}
