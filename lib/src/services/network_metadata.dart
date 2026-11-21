import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:trickster/src/services/network.dart';

/// Reads identity and connectivity metadata from one authoritative D-Bus
/// service. NetworkManager wins when both names exist; iwd is used only when
/// NetworkManager is absent. Owner detection is non-activating, every call is
/// bounded, and refreshes are signal-driven with a short coalescing window.
class NetworkMetadataService implements NetworkMetadataSource {
  NetworkMetadataService({
    DBusClient Function()? clientFactory,
    this.readTimeout = const Duration(seconds: 4),
    this.coalesce = const Duration(milliseconds: 55),
    this.maxDevices = 16,
  }) : _clientFactory = clientFactory ?? DBusClient.system;

  static const String networkManagerName = 'org.freedesktop.NetworkManager';
  static const String iwdName = 'net.connman.iwd';

  final DBusClient Function() _clientFactory;
  final Duration readTimeout;
  final Duration coalesce;
  final int maxDevices;

  final _controller = StreamController<NetworkMetadataSnapshot>.broadcast();

  NetworkMetadataSnapshot _current = const NetworkMetadataSnapshot.none();
  DBusClient? _client;
  StreamSubscription<DBusNameOwnerChangedEvent>? _ownerSubscription;
  _MetadataBackend? _backend;
  NetworkMetadataServiceKind _backendKind = NetworkMetadataServiceKind.none;
  Timer? _selectionTimer;
  Future<void> _transition = Future<void>.value();
  var _started = false;
  var _disposed = false;

  @override
  Stream<NetworkMetadataSnapshot> get snapshots => _controller.stream;

  @override
  NetworkMetadataSnapshot get current => _current;

  @override
  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    try {
      final client = _clientFactory();
      _client = client;
      _ownerSubscription = client.nameOwnerChanged
          .where(
            (event) =>
                event.name == networkManagerName || event.name == iwdName,
          )
          .listen((_) => _scheduleSelection());
      await _enqueue(_select);
    } on Object {
      _emit(const NetworkMetadataSnapshot.none());
    }
  }

  @override
  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    if (!_started) {
      await start();
      return;
    }
    await _enqueue(() async {
      await _backend?.refresh();
    });
  }

  Future<void> _select() async {
    if (_disposed) {
      return;
    }
    final client = _client;
    if (client == null) {
      _emit(const NetworkMetadataSnapshot.none());
      return;
    }
    final kind = await _preferredService(client);
    if (kind == _backendKind) {
      await _backend?.refresh();
      return;
    }

    await _backend?.dispose();
    _backend = null;
    _backendKind = kind;
    if (kind == NetworkMetadataServiceKind.none || _disposed) {
      _emit(const NetworkMetadataSnapshot.none());
      return;
    }

    final backend = kind == NetworkMetadataServiceKind.networkManager
        ? _NetworkManagerMetadata(
            client: client,
            readTimeout: readTimeout,
            coalesce: coalesce,
            maxDevices: maxDevices,
            onSnapshot: _emit,
          )
        : _IwdMetadata(
            client: client,
            readTimeout: readTimeout,
            coalesce: coalesce,
            maxDevices: maxDevices,
            onSnapshot: _emit,
          );
    _backend = backend;
    try {
      await backend.start();
      _emit(backend.current);
    } on Object {
      await backend.dispose();
      _backend = null;
      _backendKind = NetworkMetadataServiceKind.none;
      _emit(const NetworkMetadataSnapshot.none());
    }
  }

  Future<NetworkMetadataServiceKind> _preferredService(
    DBusClient client,
  ) async {
    try {
      if (await client.nameHasOwner(networkManagerName).timeout(readTimeout)) {
        return NetworkMetadataServiceKind.networkManager;
      }
      if (await client.nameHasOwner(iwdName).timeout(readTimeout)) {
        return NetworkMetadataServiceKind.iwd;
      }
    } on Object {
      return NetworkMetadataServiceKind.none;
    }
    return NetworkMetadataServiceKind.none;
  }

  void _scheduleSelection() {
    if (_disposed) {
      return;
    }
    _selectionTimer?.cancel();
    _selectionTimer = Timer(coalesce, () {
      _selectionTimer = null;
      unawaited(_enqueue(_select));
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _transition.then((_) => operation());
    _transition = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  void _emit(NetworkMetadataSnapshot snapshot) {
    if (_disposed) {
      return;
    }
    final next = snapshot.available
        ? snapshot
        : const NetworkMetadataSnapshot.none();
    if (next == _current) {
      return;
    }
    _current = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _selectionTimer?.cancel();
    _selectionTimer = null;
    await _ownerSubscription?.cancel();
    _ownerSubscription = null;
    await _transition;
    await _backend?.dispose();
    _backend = null;
    await _client?.close();
    _client = null;
    await _controller.close();
  }

  /// Exposed for a sanity check that the service never owns a periodic timer.
  @visibleForTesting
  bool get hasSelectionTimer => _selectionTimer?.isActive ?? false;
}

abstract class _MetadataBackend {
  _MetadataBackend({
    required this.client,
    required this.readTimeout,
    required this.coalesce,
    required this.maxDevices,
    required NetworkMetadataSnapshot initial,
    required this.onSnapshot,
  }) : current = initial;

  final DBusClient client;
  final Duration readTimeout;
  final Duration coalesce;
  final int maxDevices;
  final void Function(NetworkMetadataSnapshot) onSnapshot;

  NetworkMetadataSnapshot current;
  StreamSubscription<DBusSignal>? _signals;
  Timer? _refreshTimer;
  var _refreshing = false;
  var _refreshAgain = false;
  var _disposed = false;

  String get serviceName;

  String get pathNamespace;

  NetworkMetadataServiceKind get kind;

  Future<NetworkMetadataSnapshot> readSnapshot();

  Future<void> start() async {
    _signals = DBusSignalStream(
      client,
      sender: serviceName,
      pathNamespace: DBusObjectPath(pathNamespace),
    ).listen((_) => _scheduleRefresh(), onError: (_) => _scheduleRefresh());
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      final next = await readSnapshot();
      if (!_disposed) {
        current = next;
        onSnapshot(next);
      }
    } on Object {
      // Keep the last good snapshot; the next signal or owner change retries.
    } finally {
      _refreshing = false;
      if (_refreshAgain && !_disposed) {
        _refreshAgain = false;
        _scheduleRefresh();
      }
    }
  }

  void _scheduleRefresh() {
    if (_disposed) {
      return;
    }
    _refreshTimer?.cancel();
    _refreshTimer = Timer(coalesce, () {
      _refreshTimer = null;
      unawaited(refresh());
    });
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _signals?.cancel();
    _signals = null;
  }
}

final class _NetworkManagerMetadata extends _MetadataBackend {
  _NetworkManagerMetadata({
    required super.client,
    required super.readTimeout,
    required super.coalesce,
    required super.maxDevices,
    required super.onSnapshot,
  }) : super(
         initial: const NetworkMetadataSnapshot(
           service: NetworkMetadataServiceKind.networkManager,
         ),
       );

  static const String _managerName = NetworkMetadataService.networkManagerName;
  static const String _managerPath = '/org/freedesktop/NetworkManager';
  static const String _managerInterface = 'org.freedesktop.NetworkManager';
  static const String _deviceInterface =
      'org.freedesktop.NetworkManager.Device';
  static const String _wiredInterface =
      'org.freedesktop.NetworkManager.Device.Wired';
  static const String _wirelessInterface =
      'org.freedesktop.NetworkManager.Device.Wireless';
  static const String _accessPointInterface =
      'org.freedesktop.NetworkManager.AccessPoint';

  @override
  String get serviceName => _managerName;

  @override
  String get pathNamespace => _managerPath;

  @override
  NetworkMetadataServiceKind get kind =>
      NetworkMetadataServiceKind.networkManager;

  DBusRemoteObject get _root => DBusRemoteObject(
    client,
    name: _managerName,
    path: DBusObjectPath(_managerPath),
  );

  @override
  Future<NetworkMetadataSnapshot> readSnapshot() async {
    final manager = await _root
        .getAllProperties(_managerInterface)
        .timeout(readTimeout);
    final networkingEnabled = _boolean(manager, 'NetworkingEnabled');
    final wirelessEnabled = _boolean(manager, 'WirelessEnabled');
    final hardwareEnabled = _boolean(manager, 'WirelessHardwareEnabled');
    final managerState = _uint32(manager, 'State');
    final connectivity = _uint32(manager, 'Connectivity');
    final checkEnabled =
        _optionalBool(manager, 'ConnectivityCheckEnabled') ?? true;

    final reply = await _root
        .callMethod(
          _managerInterface,
          'GetDevices',
          const <DBusValue>[],
          replySignature: DBusSignature('ao'),
        )
        .timeout(readTimeout);
    final devicePaths = reply.returnValues.first
        .asObjectPathArray()
        .take(maxDevices)
        .toList(growable: false);

    final devices = <String, NetworkDeviceMetadata>{};
    for (final path in devicePaths) {
      final metadata = await _readDevice(
        path.value,
        networkingEnabled: networkingEnabled,
        wirelessEnabled: wirelessEnabled && hardwareEnabled,
        connectivityCheckEnabled: checkEnabled,
        managerState: managerState,
        connectivity: connectivity,
      );
      if (metadata != null) {
        devices[metadata.key] = metadata.value;
      }
    }
    return NetworkMetadataSnapshot(
      service: NetworkMetadataServiceKind.networkManager,
      networkingEnabled: networkingEnabled,
      wirelessEnabled: wirelessEnabled && hardwareEnabled,
      devices: devices,
    );
  }

  Future<MapEntry<String, NetworkDeviceMetadata>?> _readDevice(
    String path, {
    required bool networkingEnabled,
    required bool wirelessEnabled,
    required bool connectivityCheckEnabled,
    required int managerState,
    required int connectivity,
  }) async {
    final properties = await _tryGetAll(path, _deviceInterface);
    if (properties == null) {
      return null;
    }
    final interface = _string(properties, 'Interface');
    final type = _uint32(properties, 'DeviceType');
    if (interface.isEmpty || (type != 1 && type != 2)) {
      return null;
    }
    final medium = type == 2 ? NetworkMedium.wifi : NetworkMedium.ethernet;
    final state = _uint32(properties, 'State');
    final status = classifyNetworkManagerStatus(
      networkingEnabled: networkingEnabled,
      wirelessEnabled: wirelessEnabled,
      connectivityCheckEnabled: connectivityCheckEnabled,
      medium: medium,
      managerState: managerState,
      connectivity: connectivity,
      deviceState: state,
    );

    String? ssid;
    int? signalPercent;
    int? frequencyMhz;
    if (type == 2) {
      final wireless = await _tryGetAll(path, _wirelessInterface);
      final accessPoint = _objectPath(wireless, 'ActiveAccessPoint');
      if (accessPoint != null) {
        final ap = await _tryGetAll(accessPoint, _accessPointInterface);
        ssid = decodeSsid(_bytes(ap, 'Ssid'));
        signalPercent = _optionalByte(ap, 'Strength')?.clamp(0, 100).toInt();
        final frequency = _optionalUint32(ap, 'Frequency');
        frequencyMhz = frequency != null && frequency > 0 ? frequency : null;
      }
    }

    int? speedMbps;
    if (type == 1) {
      final wired = await _tryGetAll(path, _wiredInterface);
      final speed = _optionalUint32(wired, 'Speed');
      speedMbps = speed != null && speed > 0 ? speed : null;
    }

    return MapEntry(
      interface,
      NetworkDeviceMetadata(
        medium: medium,
        status: status,
        ssid: ssid,
        signalPercent: signalPercent,
        frequencyMhz: frequencyMhz,
        speedMbps: speedMbps,
      ),
    );
  }

  Future<Map<String, DBusValue>?> _tryGetAll(
    String path,
    String interface,
  ) async {
    try {
      return await DBusRemoteObject(
        client,
        name: _managerName,
        path: DBusObjectPath(path),
      ).getAllProperties(interface).timeout(readTimeout);
    } on Object {
      return null;
    }
  }
}

final class _IwdMetadata extends _MetadataBackend {
  _IwdMetadata({
    required super.client,
    required super.readTimeout,
    required super.coalesce,
    required super.maxDevices,
    required super.onSnapshot,
  }) : _manager = DBusRemoteObjectManager(
         client,
         name: NetworkMetadataService.iwdName,
         path: DBusObjectPath.root,
       ),
       super(
         initial: const NetworkMetadataSnapshot(
           service: NetworkMetadataServiceKind.iwd,
         ),
       );

  static const String _service = NetworkMetadataService.iwdName;
  static const String _rootPath = '/net/connman/iwd';
  static const String _deviceInterface = 'net.connman.iwd.Device';
  static const String _stationInterface = 'net.connman.iwd.Station';
  static const String _networkInterface = 'net.connman.iwd.Network';

  final DBusRemoteObjectManager _manager;

  @override
  String get serviceName => _service;

  @override
  String get pathNamespace => _rootPath;

  @override
  NetworkMetadataServiceKind get kind => NetworkMetadataServiceKind.iwd;

  @override
  Future<NetworkMetadataSnapshot> readSnapshot() async {
    final managed = await _manager.getManagedObjects().timeout(readTimeout);
    final devices = <String, NetworkDeviceMetadata>{};
    var wirelessEnabled = false;
    for (final entry in managed.entries) {
      if (devices.length >= maxDevices) {
        break;
      }
      final device = entry.value[_deviceInterface];
      if (device == null) {
        continue;
      }
      final name = _string(device, 'Name');
      if (name.isEmpty) {
        continue;
      }
      final powered = _boolean(device, 'Powered');
      wirelessEnabled = wirelessEnabled || powered;
      final station = entry.value[_stationInterface];
      if (station == null) {
        continue;
      }

      final state = _string(station, 'State', fallback: 'disconnected');
      final connectedPath = _objectPath(station, 'ConnectedNetwork');
      String? ssid;
      int? signalPercent;
      if (connectedPath != null) {
        final network =
            managed[DBusObjectPath(connectedPath)]?[_networkInterface];
        if (network != null) {
          ssid = decodeSsid(utf8.encode(_rawString(network, 'Name')));
        }
        signalPercent = await _readSignal(entry.key, connectedPath);
      }

      devices[name] = NetworkDeviceMetadata(
        medium: NetworkMedium.wifi,
        status: classifyIwdStatus(powered: powered, stationState: state),
        ssid: ssid,
        signalPercent: signalPercent,
        frequencyMhz: null,
        speedMbps: null,
      );
    }
    return NetworkMetadataSnapshot(
      service: NetworkMetadataServiceKind.iwd,
      wirelessEnabled: wirelessEnabled,
      devices: devices,
    );
  }

  Future<int?> _readSignal(
    DBusObjectPath stationPath,
    String connectedPath,
  ) async {
    try {
      final reply =
          await DBusRemoteObject(client, name: _service, path: stationPath)
              .callMethod(
                _stationInterface,
                'GetOrderedNetworks',
                const <DBusValue>[],
                replySignature: DBusSignature('a(on)'),
              )
              .timeout(readTimeout);
      final ordered = reply.returnValues.first;
      if (ordered is! DBusArray) {
        return null;
      }
      for (final value in ordered.children) {
        if (value is! DBusStruct || value.children.length != 2) {
          continue;
        }
        final path = value.children[0];
        final strength = value.children[1];
        if (path is DBusObjectPath &&
            path.value == connectedPath &&
            strength is DBusInt16) {
          return signalPercentFromDbmHundredths(strength.value);
        }
      }
    } on Object {
      return null;
    }
    return null;
  }
}

/// NetworkManager's device/connectivity precedence. A device that is not
/// activated falls back to link-classification values; a disabled manager or
/// wireless radio wins over everything.
@visibleForTesting
NetworkStatus classifyNetworkManagerStatus({
  required bool networkingEnabled,
  required bool wirelessEnabled,
  required bool connectivityCheckEnabled,
  required NetworkMedium medium,
  required int managerState,
  required int connectivity,
  required int deviceState,
}) {
  if (!networkingEnabled || managerState == 10) {
    return NetworkStatus.disabled;
  }
  if (medium == NetworkMedium.wifi && !wirelessEnabled) {
    return NetworkStatus.disabled;
  }
  if (deviceState == 0 || deviceState == 10) {
    return NetworkStatus.unknown;
  }
  if (deviceState == 20 ||
      deviceState == 30 ||
      deviceState == 110 ||
      deviceState == 120) {
    return NetworkStatus.disconnected;
  }
  if (deviceState >= 40 && deviceState <= 90) {
    return NetworkStatus.linked;
  }
  if (deviceState == 100) {
    if (connectivityCheckEnabled) {
      switch (connectivity) {
        case 4:
          return NetworkStatus.online;
        case 3:
          return NetworkStatus.limited;
        case 2:
          return NetworkStatus.captive;
        case 1:
          return NetworkStatus.local;
      }
    }
    return switch (managerState) {
      70 => NetworkStatus.online,
      60 => NetworkStatus.limited,
      50 => NetworkStatus.local,
      _ => NetworkStatus.unknown,
    };
  }
  return NetworkStatus.unknown;
}

/// iwd owns association, not internet reachability. A connected station stays
/// [NetworkStatus.unknown] so the sampler's default-route check decides
/// online versus linked; connecting states are linked; a powered-off device is
/// disabled.
@visibleForTesting
NetworkStatus classifyIwdStatus({
  required bool powered,
  required String stationState,
}) {
  if (!powered) {
    return NetworkStatus.disabled;
  }
  return switch (stationState) {
    'connected' => NetworkStatus.unknown,
    'connecting' || 'disconnecting' || 'roaming' => NetworkStatus.linked,
    'disconnected' => NetworkStatus.disconnected,
    _ => NetworkStatus.unknown,
  };
}

/// iwd reports ordered-network strength as signed hundredths of dBm.
@visibleForTesting
int signalPercentFromDbmHundredths(int hundredths) {
  final dbm = hundredths / 100;
  return ((dbm + 100) * 2).round().clamp(0, 100);
}

/// SSIDs are bytes, not necessarily UTF-8. Decode leniently, replace control
/// characters, and refuse empty or oversized values rather than paint junk.
@visibleForTesting
String? decodeSsid(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 32) {
    return null;
  }
  final sanitized = <int>[
    for (final byte in bytes) byte < 0x20 || byte == 0x7f ? 0x20 : byte,
  ];
  final decoded = utf8.decode(sanitized, allowMalformed: true);
  return decoded.trim().isEmpty ? null : decoded;
}

bool _boolean(Map<String, DBusValue>? values, String key) {
  final value = values?[key];
  return value is DBusBoolean && value.value;
}

bool? _optionalBool(Map<String, DBusValue>? values, String key) {
  final value = values?[key];
  return value is DBusBoolean ? value.value : null;
}

int _uint32(Map<String, DBusValue>? values, String key) {
  final value = values?[key];
  return value is DBusUint32 ? value.value : 0;
}

int? _optionalUint32(Map<String, DBusValue>? values, String key) {
  final value = values?[key];
  return value is DBusUint32 ? value.value : null;
}

int? _optionalByte(Map<String, DBusValue>? values, String key) {
  final value = values?[key];
  return value is DBusByte ? value.value : null;
}

String _string(
  Map<String, DBusValue>? values,
  String key, {
  String fallback = '',
}) {
  final value = values?[key];
  return value is DBusString && value.value.trim().isNotEmpty
      ? value.value.trim()
      : fallback;
}

String _rawString(Map<String, DBusValue>? values, String key) {
  final value = values?[key];
  return value is DBusString ? value.value : '';
}

List<int> _bytes(Map<String, DBusValue>? values, String key) {
  final value = values?[key];
  return value is DBusArray && value.signature == DBusSignature('ay')
      ? value.asByteArray().toList(growable: false)
      : const <int>[];
}

String? _objectPath(Map<String, DBusValue>? values, String key) {
  final value = values?[key];
  if (value is! DBusObjectPath || value.value == '/') {
    return null;
  }
  return value.value;
}
