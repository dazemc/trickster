import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

enum NetworkMedium { unknown, ethernet, wifi }

enum NetworkLink { unknown, down, up }

/// Where the connectivity/identity metadata came from. `kernel` means only
/// sysfs/procfs facts; the pill must not invent SSID, signal, or a band.
enum NetworkSource { kernel, networkManager, iwd }

/// The connectivity classification the pill renders. `captive` folds into
/// the "Limited" text; `unknown` leaves the kernel link/route decision in
/// charge.
enum NetworkStatus {
  unknown,
  disabled,
  disconnected,
  linked,
  local,
  limited,
  captive,
  online,
}

enum WifiBand { unknown, band24, band5, band6 }

/// The text contract for the pill. `local` and `limited` are reachable with
/// NetworkManager/iwd metadata; kernel-only samples use the link/route path.
enum NetworkPillState {
  wifi,
  ethernet,
  connected,
  linked,
  local,
  limited,
  disconnected,
  disabled,
}

WifiBand wifiBandForFrequency(int? frequencyMhz) {
  if (frequencyMhz == null || frequencyMhz <= 0) {
    return WifiBand.unknown;
  }
  if (frequencyMhz >= 2400 && frequencyMhz <= 2500) {
    return WifiBand.band24;
  }
  if (frequencyMhz >= 4900 && frequencyMhz < 5925) {
    return WifiBand.band5;
  }
  if (frequencyMhz >= 5925 && frequencyMhz <= 7125) {
    return WifiBand.band6;
  }
  return WifiBand.unknown;
}

/// One interface's byte counters from `/proc/net/dev`.
class NetDevCounters extends Equatable {
  const NetDevCounters({required this.rxBytes, required this.txBytes});

  final int rxBytes;
  final int txBytes;

  @override
  List<Object?> get props => [rxBytes, txBytes];
}

/// One `/sys/class/net` entry. Virtual interfaces keep their entry so a pinned
/// name can still be sampled, but [physical] is what auto-selection trusts.
class NetworkInterfaceInfo extends Equatable {
  const NetworkInterfaceInfo({
    required this.name,
    required this.ifindex,
    required this.physical,
    this.medium = NetworkMedium.unknown,
    this.adminUp = false,
    this.link = NetworkLink.unknown,
    this.speedMbps,
  });

  final String name;
  final int ifindex;
  final bool physical;
  final NetworkMedium medium;
  final bool adminUp;
  final NetworkLink link;
  final int? speedMbps;

  NetworkInterfaceInfo copyWith({
    NetworkMedium? medium,
    bool? adminUp,
    NetworkLink? link,
    int? speedMbps,
    bool clearSpeed = false,
  }) {
    return NetworkInterfaceInfo(
      name: name,
      ifindex: ifindex,
      physical: physical,
      medium: medium ?? this.medium,
      adminUp: adminUp ?? this.adminUp,
      link: link ?? this.link,
      speedMbps: clearSpeed ? null : speedMbps ?? this.speedMbps,
    );
  }

  @override
  List<Object?> get props => [
    name,
    ifindex,
    physical,
    medium,
    adminUp,
    link,
    speedMbps,
  ];
}

/// One kernel read: every counter line, the interface cache, and the
/// interfaces that currently carry a default route.
class NetworkKernelReading {
  NetworkKernelReading({
    required Map<String, NetDevCounters> counters,
    required Map<String, NetworkInterfaceInfo> interfaces,
    required Set<String> defaultRouteInterfaces,
  }) : counters = Map.unmodifiable(counters),
       interfaces = Map.unmodifiable(interfaces),
       defaultRouteInterfaces = Set.unmodifiable(defaultRouteInterfaces);

  final Map<String, NetDevCounters> counters;
  final Map<String, NetworkInterfaceInfo> interfaces;
  final Set<String> defaultRouteInterfaces;
}

/// One merged sample: kernel truth plus, when available, NetworkManager/iwd
/// identity and connectivity metadata. Kernel-only values stay null; nothing
/// is synthesized.
class NetworkSample extends Equatable {
  const NetworkSample({
    this.interface,
    this.medium = NetworkMedium.unknown,
    this.link = NetworkLink.unknown,
    this.adminUp = false,
    this.defaultRoute = false,
    this.status = NetworkStatus.unknown,
    this.source = NetworkSource.kernel,
    this.ssid,
    this.signalPercent,
    this.frequencyMhz,
    this.band = WifiBand.unknown,
    this.ethernetSpeedMbps,
    this.rxBytesPerSecond,
    this.txBytesPerSecond,
    this.rxBytesTotal,
    this.txBytesTotal,
  });

  const NetworkSample.none() : this();

  /// Null only when no physical interface exists and none is pinned.
  final String? interface;
  final NetworkMedium medium;
  final NetworkLink link;
  final bool adminUp;
  final bool defaultRoute;

  /// Merged connectivity state; [NetworkStatus.unknown] defers to link/route.
  final NetworkStatus status;
  final NetworkSource source;
  final String? ssid;
  final int? signalPercent;
  final int? frequencyMhz;
  final WifiBand band;
  final int? ethernetSpeedMbps;

  /// Null on the first sample, a counter reset, or an interface/link change.
  final int? rxBytesPerSecond;
  final int? txBytesPerSecond;
  final int? rxBytesTotal;
  final int? txBytesTotal;

  bool get visible => interface != null;

  /// Disabled and disconnected are metadata-aware; local/limited/captive come
  /// only from the metadata source. Kernel-only samples fall through to the
  /// link/default-route decision.
  NetworkPillState get pillState {
    if (!adminUp || status == NetworkStatus.disabled) {
      return NetworkPillState.disabled;
    }
    if (status == NetworkStatus.disconnected || link == NetworkLink.down) {
      return NetworkPillState.disconnected;
    }
    if (status == NetworkStatus.captive || status == NetworkStatus.limited) {
      return NetworkPillState.limited;
    }
    if (status == NetworkStatus.local) {
      return NetworkPillState.local;
    }
    if (status == NetworkStatus.linked) {
      return NetworkPillState.linked;
    }
    if (status == NetworkStatus.online) {
      return switch (medium) {
        NetworkMedium.wifi => NetworkPillState.wifi,
        NetworkMedium.ethernet => NetworkPillState.ethernet,
        NetworkMedium.unknown => NetworkPillState.connected,
      };
    }
    if (link != NetworkLink.up || !defaultRoute) {
      return NetworkPillState.linked;
    }
    return switch (medium) {
      NetworkMedium.wifi => NetworkPillState.wifi,
      NetworkMedium.ethernet => NetworkPillState.ethernet,
      NetworkMedium.unknown => NetworkPillState.connected,
    };
  }

  @override
  List<Object?> get props => [
    interface,
    medium,
    link,
    adminUp,
    defaultRoute,
    status,
    source,
    ssid,
    signalPercent,
    frequencyMhz,
    band,
    ethernetSpeedMbps,
    rxBytesPerSecond,
    txBytesPerSecond,
    rxBytesTotal,
    txBytesTotal,
  ];

  Map<String, Object?> toJson() => {
    'interface': interface,
    'medium': medium.name,
    'link': link.name,
    'admin_up': adminUp,
    'default_route': defaultRoute,
    'status': status.name,
    'source': source.name,
    'ssid': ssid,
    'signal_percent': signalPercent,
    'frequency_mhz': frequencyMhz,
    'band': band.name,
    'ethernet_speed_mbps': ethernetSpeedMbps,
    'rx_bytes_per_second': rxBytesPerSecond,
    'tx_bytes_per_second': txBytesPerSecond,
    'rx_bytes_total': rxBytesTotal,
    'tx_bytes_total': txBytesTotal,
  };

  static NetworkSample fromJson(Map<String, dynamic> json) => NetworkSample(
    interface: json['interface'] as String?,
    medium: _enumByName(NetworkMedium.values, json['medium']),
    link: _enumByName(NetworkLink.values, json['link']),
    adminUp: json['admin_up'] as bool? ?? false,
    defaultRoute: json['default_route'] as bool? ?? false,
    status: _enumByName(NetworkStatus.values, json['status']),
    source: _enumByName(NetworkSource.values, json['source']),
    ssid: json['ssid'] as String?,
    signalPercent: (json['signal_percent'] as num?)?.toInt(),
    frequencyMhz: (json['frequency_mhz'] as num?)?.toInt(),
    band: _enumByName(WifiBand.values, json['band']),
    ethernetSpeedMbps: (json['ethernet_speed_mbps'] as num?)?.toInt(),
    rxBytesPerSecond: (json['rx_bytes_per_second'] as num?)?.toInt(),
    txBytesPerSecond: (json['tx_bytes_per_second'] as num?)?.toInt(),
    rxBytesTotal: (json['rx_bytes_total'] as num?)?.toInt(),
    txBytesTotal: (json['tx_bytes_total'] as num?)?.toInt(),
  );
}

T _enumByName<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return values.first;
}

/// One device's identity/connectivity metadata, keyed by interface name.
class NetworkDeviceMetadata extends Equatable {
  const NetworkDeviceMetadata({
    required this.medium,
    this.status = NetworkStatus.unknown,
    this.ssid,
    this.signalPercent,
    this.frequencyMhz,
    this.speedMbps,
  });

  final NetworkMedium medium;
  final NetworkStatus status;
  final String? ssid;
  final int? signalPercent;
  final int? frequencyMhz;
  final int? speedMbps;

  @override
  List<Object?> get props => [
    medium,
    status,
    ssid,
    signalPercent,
    frequencyMhz,
    speedMbps,
  ];
}

/// One authoritative metadata read. `service == none` is neutral: the sampler
/// falls back to kernel facts and clears every metadata field.
class NetworkMetadataSnapshot extends Equatable {
  const NetworkMetadataSnapshot({
    this.service = NetworkMetadataServiceKind.none,
    this.networkingEnabled = true,
    this.wirelessEnabled = true,
    this.devices = const <String, NetworkDeviceMetadata>{},
  });

  const NetworkMetadataSnapshot.none() : this();

  final NetworkMetadataServiceKind service;
  final bool networkingEnabled;
  final bool wirelessEnabled;
  final Map<String, NetworkDeviceMetadata> devices;

  bool get available => service != NetworkMetadataServiceKind.none;

  NetworkSource get source => switch (service) {
    NetworkMetadataServiceKind.none => NetworkSource.kernel,
    NetworkMetadataServiceKind.networkManager => NetworkSource.networkManager,
    NetworkMetadataServiceKind.iwd => NetworkSource.iwd,
  };

  @override
  List<Object?> get props => [
    service,
    networkingEnabled,
    wirelessEnabled,
    ...devices.entries.map((entry) => Object.hash(entry.key, entry.value)),
  ];
}

enum NetworkMetadataServiceKind { none, networkManager, iwd }

/// The metadata authority the sampler listens to. `null` on the sampler means
/// kernel-only (unit tests, or a deliberately disabled metadata plane).
abstract interface class NetworkMetadataSource {
  Stream<NetworkMetadataSnapshot> get snapshots;

  NetworkMetadataSnapshot get current;

  Future<void> start();

  Future<void> refresh();

  Future<void> dispose();
}

/// Parses the two header lines plus one `iface: rx ... tx ...` line per
/// interface. Invalid or truncated lines are skipped, never synthesized.
@visibleForTesting
Map<String, NetDevCounters> parseProcNetDev(String source) {
  final result = <String, NetDevCounters>{};
  for (final line in source.split('\n')) {
    final colon = line.indexOf(':');
    if (colon <= 0) {
      continue;
    }
    final name = line.substring(0, colon).trim();
    if (name.isEmpty) {
      continue;
    }
    final fields = line.substring(colon + 1).trim().split(RegExp(r'\s+'));
    if (fields.length < 9) {
      continue;
    }
    final rx = int.tryParse(fields[0]);
    final tx = int.tryParse(fields[8]);
    if (rx == null || tx == null || rx < 0 || tx < 0) {
      continue;
    }
    result[name] = NetDevCounters(rxBytes: rx, txBytes: tx);
  }
  return result;
}

/// IPv4 default routes from `/proc/net/route`: destination and mask both zero,
/// `RTF_UP` set. Loopback is never a default-route candidate.
@visibleForTesting
Set<String> parseIpv4DefaultRoutes(String source) {
  final routes = <String>{};
  for (final line in source.split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 8 || fields.first == 'Iface') {
      continue;
    }
    final iface = fields[0];
    final destination = fields[1].toLowerCase();
    final flags = int.tryParse(fields[3], radix: 16);
    final mask = fields[7].toLowerCase();
    if (iface.isEmpty ||
        iface == 'lo' ||
        destination != '00000000' ||
        mask != '00000000' ||
        flags == null ||
        flags & 0x1 == 0) {
      continue;
    }
    routes.add(iface);
  }
  return routes;
}

/// IPv6 default routes from `/proc/net/ipv6_route`: destination and prefix
/// both zero, `RTF_UP` set. The kernel prints the destination as 32 hex digits
/// and the prefix as two.
@visibleForTesting
Set<String> parseIpv6DefaultRoutes(String source) {
  final routes = <String>{};
  for (final line in source.split('\n')) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 10) {
      continue;
    }
    final destination = fields[0].toLowerCase();
    final prefix = fields[1].toLowerCase();
    final flags = int.tryParse(fields[8], radix: 16);
    final iface = fields[9];
    if (iface.isEmpty ||
        iface == 'lo' ||
        destination != '00000000000000000000000000000000' ||
        prefix != '00' ||
        flags == null ||
        flags & 0x1 == 0) {
      continue;
    }
    routes.add(iface);
  }
  return routes;
}

/// `/sys/class/net/<if>/flags` is printed as `0x1003`; the `IFF_UP` bit is 1.
@visibleForTesting
int? parseInterfaceFlags(String source) {
  var text = source.trim().toLowerCase();
  if (text.isEmpty) {
    return null;
  }
  if (text.startsWith('0x')) {
    text = text.substring(2);
  }
  return int.tryParse(text, radix: 16);
}

/// Sysfs publishes a positive Mb/s value when the link is up and `-1` (or a
/// failed read) when it is not. Only a positive value is a reading.
@visibleForTesting
int? parseLinkSpeed(String source) {
  final value = int.tryParse(source.trim());
  return value != null && value > 0 ? value : null;
}

/// Carrier is authoritative when readable; Wi-Fi publishes no carrier file
/// while down, so `operstate` is the fallback.
@visibleForTesting
NetworkLink parseLinkState({String? carrier, String? operstate}) {
  switch (carrier?.trim()) {
    case '1':
      return NetworkLink.up;
    case '0':
      return NetworkLink.down;
  }
  return switch (operstate?.trim()) {
    'up' => NetworkLink.up,
    'down' || 'dormant' || 'lowerlayerdown' || 'notpresent' => NetworkLink.down,
    _ => NetworkLink.unknown,
  };
}

/// Whether a physical interface or an explicitly pinned name exists.
///
/// Used by the settings availability probe; it mirrors the sampler's
/// selection rule without reading counters or routes. Auto mode ignores
/// loopback and interfaces without a `device` link; a pinned name is accepted
/// as written, including a virtual interface.
bool hasNetworkInterface({String netRoot = '/sys/class/net', String? pinned}) {
  final root = Directory(netRoot);
  if (!root.existsSync()) {
    return false;
  }
  if (pinned != null && pinned.isNotEmpty) {
    return Directory('$netRoot/$pinned').existsSync();
  }
  try {
    for (final entity in root.listSync(followLinks: true)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name == 'lo' || name.isEmpty) {
        continue;
      }
      if (Directory('${entity.path}/device').existsSync()) {
        return true;
      }
    }
  } on FileSystemException {
    return false;
  }
  return false;
}

/// The active interface. Auto mode trusts only physical interfaces and picks
/// one; it never aggregates or samples a tunnel. A pinned name is accepted as
/// written, including a virtual interface, because pinning is explicit.
@visibleForTesting
NetworkInterfaceInfo? selectNetworkInterface({
  required String? pinned,
  required Map<String, NetworkInterfaceInfo> interfaces,
  required Set<String> defaultRouteInterfaces,
}) {
  if (pinned != null && pinned.isNotEmpty) {
    return interfaces[pinned];
  }
  NetworkInterfaceInfo? best;
  var bestScore = -1;
  for (final info in interfaces.values) {
    if (!info.physical || info.name == 'lo') {
      continue;
    }
    final score =
        (defaultRouteInterfaces.contains(info.name) ? 4 : 0) +
        (info.link == NetworkLink.up ? 2 : 0) +
        (info.adminUp ? 1 : 0);
    if (best == null ||
        score > bestScore ||
        (score == bestScore && info.ifindex < best.ifindex) ||
        (score == bestScore &&
            info.ifindex == best.ifindex &&
            info.name.compareTo(best.name) < 0)) {
      best = info;
      bestScore = score;
    }
  }
  return best;
}

/// The kernel side of the module. Implementations read one snapshot; the
/// sampler owns cadence and rate math.
abstract interface class NetworkReader {
  NetworkKernelReading read({String? selectedName, String? pinnedName});

  void dispose();
}

/// Reads sysfs and procfs without spawning anything. Interface identity is
/// re-enumerated at most every [interfaceRefresh]; the selected interface's
/// live link fields are refreshed on every read so a flap is seen at 1 Hz.
class SystemNetworkReader implements NetworkReader {
  SystemNetworkReader({
    Directory? netRoot,
    File? procNetDev,
    File? procNetRoute,
    File? procNetIpv6Route,
    this.interfaceRefresh = const Duration(seconds: 10),
  }) : _netRoot = netRoot ?? Directory('/sys/class/net'),
       _procNetDev = procNetDev ?? File('/proc/net/dev'),
       _procNetRoute = procNetRoute ?? File('/proc/net/route'),
       _procNetIpv6Route = procNetIpv6Route ?? File('/proc/net/ipv6_route');

  static const int _maxInterfaces = 4096;
  static const int _maxProcBytes = 128 * 1024;

  final Duration interfaceRefresh;
  final Directory _netRoot;
  final File _procNetDev;
  final File _procNetRoute;
  final File _procNetIpv6Route;
  final Uint8List _buffer = Uint8List(_maxProcBytes);
  final Stopwatch _interfaceClock = Stopwatch()..start();
  Map<String, NetworkInterfaceInfo>? _interfaces;

  @override
  NetworkKernelReading read({String? selectedName, String? pinnedName}) {
    final counters = _readCounters();
    final routes = _readDefaultRoutes();
    final cache = _interfaces;
    final expired =
        cache == null || _interfaceClock.elapsed >= interfaceRefresh;
    final missingSelected =
        selectedName != null && !(cache?.containsKey(selectedName) ?? false);
    if (expired || missingSelected) {
      _interfaces = _enumerateInterfaces(pinnedName: pinnedName);
      _interfaceClock
        ..reset()
        ..start();
    }
    final interfaces = _interfaces!;
    if (selectedName != null) {
      final previous = interfaces[selectedName];
      final refreshed = _readInterface(selectedName, previous: previous);
      if (refreshed == null) {
        interfaces.remove(selectedName);
      } else {
        interfaces[selectedName] = refreshed;
      }
    }
    return NetworkKernelReading(
      counters: counters,
      interfaces: interfaces,
      defaultRouteInterfaces: routes,
    );
  }

  @override
  void dispose() {
    _interfaces = null;
  }

  Map<String, NetDevCounters> _readCounters() {
    try {
      return parseProcNetDev(_readBounded(_procNetDev));
    } on Object {
      return const {};
    }
  }

  Set<String> _readDefaultRoutes() {
    final routes = <String>{};
    try {
      routes.addAll(parseIpv4DefaultRoutes(_readBounded(_procNetRoute)));
    } on Object {
      // A missing route table is not a network failure; the link state stands.
    }
    try {
      routes.addAll(parseIpv6DefaultRoutes(_readBounded(_procNetIpv6Route)));
    } on Object {
      // Same for the IPv6 table.
    }
    return routes;
  }

  /// Reuses one buffer for the two procfs tables. A table larger than the cap
  /// is truncated; parsers skip the incomplete tail.
  String _readBounded(File file) {
    final opened = file.openSync();
    try {
      final read = opened.readIntoSync(_buffer);
      if (read <= 0) {
        return '';
      }
      // Drop a truncated tail rather than handing the parser half a line.
      var end = read;
      if (read == _buffer.length) {
        while (end > 0 && _buffer[end - 1] != 0x0a) {
          end -= 1;
        }
      }
      return String.fromCharCodes(_buffer, 0, end);
    } finally {
      opened.closeSync();
    }
  }

  Map<String, NetworkInterfaceInfo> _enumerateInterfaces({
    required String? pinnedName,
  }) {
    final interfaces = <String, NetworkInterfaceInfo>{};
    List<FileSystemEntity> entries;
    try {
      entries = _netRoot.listSync(followLinks: false);
    } on Object {
      return interfaces;
    }
    for (final entity in entries) {
      if (interfaces.length >= _maxInterfaces) {
        break;
      }
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.isEmpty || name == '.' || name == '..') {
        continue;
      }
      final physical =
          name != 'lo' && _existsFollowing('${_path(name)}/device');
      final full = physical || name == pinnedName;
      interfaces[name] = NetworkInterfaceInfo(
        name: name,
        ifindex: _readInt(File('${_path(name)}/ifindex')) ?? 0,
        physical: physical,
        medium: full ? _readMedium(name) : NetworkMedium.unknown,
        adminUp: full ? _readAdminUp(name) ?? false : false,
        link: full ? _readLink(name) : NetworkLink.unknown,
        speedMbps: full ? _readSpeed(name) : null,
      );
    }
    return interfaces;
  }

  NetworkInterfaceInfo? _readInterface(
    String name, {
    required NetworkInterfaceInfo? previous,
  }) {
    final directory = Directory(_path(name));
    if (!directory.existsSync()) {
      return null;
    }
    final medium = previous == null || previous.medium == NetworkMedium.unknown
        ? _readMedium(name)
        : previous.medium;
    final link = _readLink(name);
    final speed = medium == NetworkMedium.ethernet && link == NetworkLink.up
        ? _readSpeed(name) ?? previous?.speedMbps
        : null;
    return NetworkInterfaceInfo(
      name: name,
      ifindex:
          previous?.ifindex ?? _readInt(File('${directory.path}/ifindex')) ?? 0,
      physical:
          previous?.physical ??
          (name != 'lo' && _existsFollowing('${directory.path}/device')),
      medium: medium,
      adminUp: _readAdminUp(name) ?? previous?.adminUp ?? false,
      link: link,
      speedMbps: speed,
    );
  }

  String _path(String name) => '${_netRoot.path}/$name';

  bool _existsFollowing(String path) {
    return FileSystemEntity.typeSync(path, followLinks: true) !=
        FileSystemEntityType.notFound;
  }

  NetworkMedium _readMedium(String name) {
    if (Directory('${_path(name)}/wireless').existsSync() ||
        _existsFollowing('${_path(name)}/phy80211')) {
      return NetworkMedium.wifi;
    }
    final type = _readInt(File('${_path(name)}/type'));
    return type == 1 ? NetworkMedium.ethernet : NetworkMedium.unknown;
  }

  bool? _readAdminUp(String name) {
    final flags = parseInterfaceFlags(
      _readText(File('${_path(name)}/flags')) ?? '',
    );
    return flags == null ? null : flags & 0x1 != 0;
  }

  NetworkLink _readLink(String name) {
    return parseLinkState(
      carrier: _readText(File('${_path(name)}/carrier')),
      operstate: _readText(File('${_path(name)}/operstate')),
    );
  }

  int? _readSpeed(String name) {
    return parseLinkSpeed(_readText(File('${_path(name)}/speed')) ?? '');
  }

  int? _readInt(File file) => int.tryParse(_readText(file)?.trim() ?? '');

  String? _readText(File file) {
    try {
      return file.readAsStringSync();
    } on Object {
      return null;
    }
  }
}

class _CounterBaseline {
  const _CounterBaseline({
    required this.interface,
    required this.rxBytes,
    required this.txBytes,
    required this.atMicros,
  });

  final String interface;
  final int rxBytes;
  final int txBytes;
  final int atMicros;
}

/// Samples one interface at [interval]. Rates divide by the measured elapsed
/// time, not the nominal interval; the first sample, a counter reset, and an
/// interface or link change all report null rates.
class NetworkSampler {
  NetworkSampler({
    this.interval = const Duration(seconds: 1),
    this.interface,
    NetworkReader? reader,
    NetworkMetadataSource? metadata,
    int Function()? nowMicros,
    void Function(String)? log,
  }) : _reader = reader ?? SystemNetworkReader(),
       _metadata = metadata,
       _nowMicros = nowMicros,
       _log = log ?? stderr.writeln;

  final Duration interval;

  /// Pinned interface name; null selects the active physical interface.
  final String? interface;
  final NetworkReader _reader;
  final NetworkMetadataSource? _metadata;
  final int Function()? _nowMicros;
  final void Function(String) _log;
  final Stopwatch _stopwatch = Stopwatch()..start();
  final _controller = StreamController<NetworkSample>.broadcast();

  NetworkSample _latest = const NetworkSample.none();
  NetworkMetadataSnapshot _metadataSnapshot =
      const NetworkMetadataSnapshot.none();
  StreamSubscription<NetworkMetadataSnapshot>? _metadataSubscription;
  _CounterBaseline? _baseline;
  String? _loggedInterface;
  Timer? _timer;
  var _running = false;
  var _paused = false;
  var _disposed = false;
  var _metadataStarted = false;

  Stream<NetworkSample> get snapshots => _controller.stream;

  NetworkSample get current => _latest;

  @visibleForTesting
  bool get isRunning => _timer?.isActive ?? false;

  /// A paused start starts no throughput timer, so a module created while the
  /// seat is already idle does no periodic work. The metadata plane may still
  /// connect and keep its event subscriptions live, matching MPRIS; a resume
  /// sample already has the latest identity state.
  void start({bool paused = false}) {
    if (_disposed) {
      return;
    }
    _startMetadata();
    if (_running) {
      if (paused) {
        pause();
      } else {
        resume();
      }
      return;
    }
    _running = true;
    _paused = paused;
    if (!_paused) {
      _sample();
      _schedule();
    }
  }

  void _startMetadata() {
    final metadata = _metadata;
    if (metadata == null) {
      return;
    }
    _metadataSubscription ??= metadata.snapshots.listen(_onMetadata);
    if (_metadataStarted) {
      return;
    }
    _metadataStarted = true;
    unawaited(metadata.start());
  }

  void pause() {
    if (!_running || _paused) {
      return;
    }
    _paused = true;
    _timer?.cancel();
    _timer = null;
    // The idle window is not a throughput measurement.
    _baseline = null;
  }

  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;
    if (!_running) {
      return;
    }
    // Immediate baseline: the pill drops stale rates, then the next tick
    // measures a fresh one-second window.
    _sample();
    _schedule();
  }

  void _schedule() {
    _timer ??= Timer.periodic(interval, (_) => _sample());
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    _paused = true;
    _timer?.cancel();
    _timer = null;
    _baseline = null;
    await _metadataSubscription?.cancel();
    _metadataSubscription = null;
    await _metadata?.dispose();
    _reader.dispose();
    await _controller.close();
  }

  void _sample() {
    if (!_running || _paused || _disposed || _controller.isClosed) {
      return;
    }
    final reading = _reader.read(
      selectedName: _latest.interface,
      pinnedName: interface,
    );
    final selected = selectNetworkInterface(
      pinned: interface,
      interfaces: reading.interfaces,
      defaultRouteInterfaces: reading.defaultRouteInterfaces,
    );
    if (selected == null) {
      _hide();
      return;
    }
    final counters = reading.counters[selected.name];
    if (counters == null) {
      _hide();
      return;
    }

    final changed =
        _latest.interface != selected.name ||
        _latest.link != selected.link ||
        _latest.adminUp != selected.adminUp;
    if (changed) {
      _baseline = null;
    }

    final now = _nowMicros?.call() ?? _stopwatch.elapsedMicroseconds;
    int? rxRate;
    int? txRate;
    final baseline = _baseline;
    if (baseline != null &&
        baseline.interface == selected.name &&
        counters.rxBytes >= baseline.rxBytes &&
        counters.txBytes >= baseline.txBytes) {
      final elapsed = now - baseline.atMicros;
      if (elapsed > 0 && selected.link == NetworkLink.up && selected.adminUp) {
        final rxDelta = counters.rxBytes - baseline.rxBytes;
        final txDelta = counters.txBytes - baseline.txBytes;
        rxRate = (rxDelta * 1000000 / elapsed).round();
        txRate = (txDelta * 1000000 / elapsed).round();
      }
    }
    _baseline = _CounterBaseline(
      interface: selected.name,
      rxBytes: counters.rxBytes,
      txBytes: counters.txBytes,
      atMicros: now,
    );

    final base = NetworkSample(
      interface: selected.name,
      medium: selected.medium,
      link: selected.link,
      adminUp: selected.adminUp,
      defaultRoute: reading.defaultRouteInterfaces.contains(selected.name),
      ethernetSpeedMbps: selected.medium == NetworkMedium.ethernet
          ? selected.speedMbps
          : null,
      rxBytesPerSecond: rxRate,
      txBytesPerSecond: txRate,
      rxBytesTotal: counters.rxBytes,
      txBytesTotal: counters.txBytes,
    );
    final next = _mergeMetadata(base, _metadataSnapshot);
    if (next != _latest) {
      _latest = next;
      _controller.add(next);
    }
    if (_loggedInterface != selected.name) {
      _loggedInterface = selected.name;
      _log('trickster: network interface ${selected.name}');
    }
  }

  void _onMetadata(NetworkMetadataSnapshot snapshot) {
    _metadataSnapshot = snapshot;
    if (!_running ||
        _paused ||
        _disposed ||
        _controller.isClosed ||
        !_latest.visible) {
      return;
    }
    final next = _mergeMetadata(_latest, snapshot);
    if (next != _latest) {
      _latest = next;
      _controller.add(next);
    }
  }

  /// Metadata is looked up by the selected interface name, so an interface
  /// change cannot carry the old SSID. A missing device clears every metadata
  /// field and leaves the kernel classification in charge.
  NetworkSample _mergeMetadata(
    NetworkSample base,
    NetworkMetadataSnapshot snapshot,
  ) {
    final device = base.interface == null
        ? null
        : snapshot.devices[base.interface];
    if (device == null) {
      return NetworkSample(
        interface: base.interface,
        medium: base.medium,
        link: base.link,
        adminUp: base.adminUp,
        defaultRoute: base.defaultRoute,
        status: NetworkStatus.unknown,
        source: NetworkSource.kernel,
        ethernetSpeedMbps: base.ethernetSpeedMbps,
        rxBytesPerSecond: base.rxBytesPerSecond,
        txBytesPerSecond: base.txBytesPerSecond,
        rxBytesTotal: base.rxBytesTotal,
        txBytesTotal: base.txBytesTotal,
      );
    }
    final usable =
        device.status != NetworkStatus.disconnected &&
        device.status != NetworkStatus.disabled;
    return NetworkSample(
      interface: base.interface,
      medium: device.medium,
      link: base.link,
      adminUp: base.adminUp,
      defaultRoute: base.defaultRoute,
      status: device.status,
      source: snapshot.source,
      ssid: usable ? device.ssid : null,
      signalPercent: usable ? device.signalPercent : null,
      frequencyMhz: usable ? device.frequencyMhz : null,
      band: usable
          ? wifiBandForFrequency(device.frequencyMhz)
          : WifiBand.unknown,
      ethernetSpeedMbps: usable && device.medium == NetworkMedium.ethernet
          ? base.ethernetSpeedMbps ?? device.speedMbps
          : null,
      rxBytesPerSecond: base.rxBytesPerSecond,
      txBytesPerSecond: base.txBytesPerSecond,
      rxBytesTotal: base.rxBytesTotal,
      txBytesTotal: base.txBytesTotal,
    );
  }

  void _hide() {
    _baseline = null;
    if (_latest.visible) {
      _latest = const NetworkSample.none();
      _controller.add(_latest);
    }
  }
}
