import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

enum NetworkMedium { unknown, ethernet, wifi }

enum NetworkLink { unknown, down, up }

/// The text contract for the pill. `local` and `limited` are reserved for the
/// connectivity metadata that will follow this kernel-only slice.
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

/// One kernel-truth sample. No connectivity metadata: rates, counters, link,
/// medium, admin state, and the default-route flag are the whole state.
class NetworkSample extends Equatable {
  const NetworkSample({
    this.interface,
    this.medium = NetworkMedium.unknown,
    this.link = NetworkLink.unknown,
    this.adminUp = false,
    this.defaultRoute = false,
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
  final int? ethernetSpeedMbps;

  /// Null on the first sample, a counter reset, or an interface/link change.
  final int? rxBytesPerSecond;
  final int? txBytesPerSecond;
  final int? rxBytesTotal;
  final int? txBytesTotal;

  bool get visible => interface != null;

  /// Kernel-only state priority. `local` and `limited` become reachable with
  /// the connectivity metadata slice; this slice never fabricates them.
  NetworkPillState get pillState {
    if (!adminUp) {
      return NetworkPillState.disabled;
    }
    if (link == NetworkLink.down) {
      return NetworkPillState.disconnected;
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
    int Function()? nowMicros,
    void Function(String)? log,
  }) : _reader = reader ?? SystemNetworkReader(),
       _nowMicros = nowMicros,
       _log = log ?? stderr.writeln;

  final Duration interval;

  /// Pinned interface name; null selects the active physical interface.
  final String? interface;
  final NetworkReader _reader;
  final int Function()? _nowMicros;
  final void Function(String) _log;
  final Stopwatch _stopwatch = Stopwatch()..start();
  final _controller = StreamController<NetworkSample>.broadcast();

  NetworkSample _latest = const NetworkSample.none();
  _CounterBaseline? _baseline;
  String? _loggedInterface;
  Timer? _timer;
  var _running = false;
  var _paused = false;
  var _disposed = false;

  Stream<NetworkSample> get snapshots => _controller.stream;

  NetworkSample get current => _latest;

  @visibleForTesting
  bool get isRunning => _timer?.isActive ?? false;

  /// A paused start reads nothing and starts no timer, so a module created
  /// while the seat is already idle does no periodic work.
  void start({bool paused = false}) {
    if (_disposed) {
      return;
    }
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

    final next = NetworkSample(
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
    if (next != _latest) {
      _latest = next;
      _controller.add(next);
    }
    if (_loggedInterface != selected.name) {
      _loggedInterface = selected.name;
      _log('trickster: network interface ${selected.name}');
    }
  }

  void _hide() {
    _baseline = null;
    if (_latest.visible) {
      _latest = const NetworkSample.none();
      _controller.add(_latest);
    }
  }
}
