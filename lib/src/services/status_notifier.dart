import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show ImageByteFormat, Offset, instantiateImageCodec;

import 'package:dbus/dbus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// StatusNotifier item status, in ascending attention order.
enum SystemTrayStatus { passive, active, needsAttention }

/// Item interactions the host can invoke.
enum SystemTrayAction { activate, secondaryActivate, contextMenu }

/// How a menu entry toggles, mirroring `com.canonical.dbusmenu`.
enum SystemTrayMenuToggleType { none, checkmark, radio }

/// One parsed `com.canonical.dbusmenu` layout entry.
@immutable
class SystemTrayMenuEntry {
  const SystemTrayMenuEntry({
    required this.id,
    required this.label,
    required this.enabled,
    required this.visible,
    required this.separator,
    required this.toggleType,
    required this.toggleState,
    required this.destructive,
    required this.children,
  });

  final int id;
  final String label;
  final bool enabled;
  final bool visible;
  final bool separator;
  final SystemTrayMenuToggleType toggleType;
  final int toggleState;
  final bool destructive;
  final List<SystemTrayMenuEntry> children;

  @override
  bool operator ==(Object other) {
    return other is SystemTrayMenuEntry &&
        other.id == id &&
        other.label == label &&
        other.enabled == enabled &&
        other.visible == visible &&
        other.separator == separator &&
        other.toggleType == toggleType &&
        other.toggleState == toggleState &&
        other.destructive == destructive &&
        listEquals(other.children, children);
  }

  @override
  int get hashCode => Object.hash(
    id,
    label,
    enabled,
    visible,
    separator,
    toggleType,
    toggleState,
    destructive,
    Object.hashAll(children),
  );
}

/// A decoded, premultiplied RGBA icon at display size.
@immutable
class SystemTrayIconPixmap {
  const SystemTrayIconPixmap({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;

  /// Premultiplied RGBA8888 pixels in row-major order.
  final Uint8List rgba;

  @override
  bool operator ==(Object other) {
    return other is SystemTrayIconPixmap &&
        other.width == width &&
        other.height == height &&
        listEquals(other.rgba, rgba);
  }

  @override
  int get hashCode => Object.hash(width, height, Object.hashAll(rgba));
}

/// One StatusNotifier item tracked by the host.
@immutable
class SystemTrayItem {
  const SystemTrayItem({
    required this.id,
    required this.title,
    required this.status,
    required this.iconName,
    required this.iconThemePath,
    required this.iconPixmap,
    required this.menuAvailable,
    required this.primaryOpensMenu,
    this.menuPath = '',
  });

  final String id;
  final String title;
  final SystemTrayStatus status;
  final String iconName;
  final String iconThemePath;
  final SystemTrayIconPixmap? iconPixmap;
  final bool menuAvailable;
  final bool primaryOpensMenu;
  final String menuPath;

  @override
  bool operator ==(Object other) {
    return other is SystemTrayItem &&
        other.id == id &&
        other.title == title &&
        other.status == status &&
        other.iconName == iconName &&
        other.iconThemePath == iconThemePath &&
        other.iconPixmap == iconPixmap &&
        other.menuAvailable == menuAvailable &&
        other.primaryOpensMenu == primaryOpensMenu &&
        other.menuPath == menuPath;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    status,
    iconName,
    iconThemePath,
    iconPixmap,
    menuAvailable,
    primaryOpensMenu,
    menuPath,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'status': status.name,
    'iconName': iconName,
    'iconThemePath': iconThemePath,
    'menuAvailable': menuAvailable,
    'primaryOpensMenu': primaryOpensMenu,
    'menuPath': menuPath,
  };

  /// Icon pixmap bytes are presentational and not serialized.
  static SystemTrayItem fromJson(Map<String, dynamic> json) => SystemTrayItem(
    id: '${json['id']}',
    title: '${json['title']}',
    status: _statusFromName('${json['status']}'),
    iconName: '${json['iconName']}',
    iconThemePath: '${json['iconThemePath']}',
    iconPixmap: null,
    menuAvailable: (json['menuAvailable'] as bool?) ?? false,
    primaryOpensMenu: (json['primaryOpensMenu'] as bool?) ?? false,
    menuPath: '${json['menuPath']}',
  );
}

/// Bloc state for the tray item list. A bare `List` compares by identity, so
/// the wrapper exists to give the bloc value semantics — and a JSON shape for
/// the future `tricksterctl status` dump.
class TrayState extends Equatable {
  const TrayState([this.items = const []]);

  final List<SystemTrayItem> items;

  // Spread: Equatable compares props element-wise.
  @override
  List<Object?> get props => [...items];

  Map<String, Object?> toJson() => {
    'items': [for (final item in items) item.toJson()],
  };

  static TrayState fromJson(Map<String, dynamic> json) => TrayState([
    for (final entry in json['items'] as List<dynamic>? ?? const [])
      if (entry is Map<String, dynamic>) SystemTrayItem.fromJson(entry),
  ]);
}

/// Hosts the freedesktop/KDE StatusNotifier protocol used by AppIndicator and
/// modern Linux tray applications.
///
/// The host owns `org.kde.StatusNotifierWatcher` when the name is free,
/// registers itself as a host, and tracks every item by its bus name and
/// object path. Items are removed when their name owner disappears. D-Bus
/// runs on the UI isolate for now; Denial isolated it on a worker.
///
/// XEmbed tray icons stay dropped: embedding them needs an owned Xwayland,
/// which a guest bar cannot borrow.
class StatusNotifierService {
  StatusNotifierService({DBusClient? client}) : _client = client;

  static const String watcherName = 'org.kde.StatusNotifierWatcher';
  static const String watcherPath = '/StatusNotifierWatcher';
  static const String watcherInterface = 'org.kde.StatusNotifierWatcher';
  static const String standardWatcherName =
      'org.freedesktop.StatusNotifierWatcher';
  static const String standardWatcherInterface =
      'org.freedesktop.StatusNotifierWatcher';
  static const String itemInterface = 'org.kde.StatusNotifierItem';
  static const String standardItemInterface =
      'org.freedesktop.StatusNotifierItem';
  static const String menuInterface = 'com.canonical.dbusmenu';
  static const List<String> itemInterfaces = <String>[
    itemInterface,
    standardItemInterface,
  ];

  static const Duration _readTimeout = Duration(seconds: 2);
  static const Duration _methodTimeout = Duration(seconds: 4);
  static const Duration _signalCoalesce = Duration(milliseconds: 45);
  static const int _maxItems = 64;
  static const int _maxMenuItems = 256;
  static const int _maxMenuDepth = 5;

  DBusClient? _client;
  final _watcher = StatusNotifierWatcherEndpoint();
  final StreamController<List<SystemTrayItem>> _snapshots =
      StreamController<List<SystemTrayItem>>.broadcast(sync: true);
  final Map<String, _StatusNotifierRegistration> _registrations = {};
  final Map<String, SystemTrayItem> _items = {};
  final Map<String, String> _itemInterfaces = {};
  final Map<String, Map<String, DBusValue>> _itemProperties = {};
  final Map<String, SystemTrayIconPixmap?> _normalPixmaps = {};
  final Map<String, SystemTrayIconPixmap?> _attentionPixmaps = {};
  final Map<String, String?> _iconPaths = {};
  final Map<String, SystemTrayIconPixmap?> _iconFiles = {};
  final Set<String> _iconLoads = {};
  final Map<String, _PendingStatusNotifierRefresh> _pendingRefreshes = {};
  List<SystemTrayItem> _lastSnapshot = const <SystemTrayItem>[];

  final List<StreamSubscription<DBusSignal>> _itemSignals = [];
  StreamSubscription<DBusSignal>? _watcherSignals;
  StreamSubscription<DBusNameOwnerChangedEvent>? _ownerChanges;
  Timer? _signalTimer;
  Timer? _externalWatcherTimer;
  bool _ownsWatcher = false;
  bool _started = false;
  bool _disposed = false;
  bool _drainingRefreshes = false;

  DBusClient get _bus => _client ??= DBusClient.session();

  Stream<List<SystemTrayItem>> get snapshots => _snapshots.stream;

  List<SystemTrayItem> get current => _orderedItems();

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _watcher.onRegisterItem = _registerFromMethod;
    _watcher.onRegisterHost = (_) async {
      _watcher.setHostRegistered(true);
      await _watcher.emitHostRegistered();
    };
    await _bus.registerObject(_watcher);
    final watcherReply = await _bus.requestName(
      watcherName,
      flags: const {DBusRequestNameFlag.doNotQueue},
    );
    _ownsWatcher =
        watcherReply == DBusRequestNameReply.primaryOwner ||
        watcherReply == DBusRequestNameReply.alreadyOwner;

    final hostName = 'org.kde.StatusNotifierHost.Trickster$pid';
    await _bus.requestName(
      hostName,
      flags: const {DBusRequestNameFlag.doNotQueue},
    );

    // Subscribe before importing registrations from an existing watcher so
    // item changes cannot race the initial asynchronous property reads.
    for (final interface in itemInterfaces) {
      _itemSignals.add(
        DBusSignalStream(
          _bus,
          interface: interface,
        ).listen(_handleItemSignal, onError: (_) => _scheduleAllRefreshes()),
      );
    }
    _itemSignals.add(
      DBusSignalStream(
        _bus,
        interface: 'org.freedesktop.DBus.Properties',
        name: 'PropertiesChanged',
      ).listen(
        _handlePropertiesChanged,
        onError: (_) => _scheduleAllRefreshes(),
      ),
    );
    _ownerChanges = _bus.nameOwnerChanged.listen(_handleOwnerChanged);

    if (_ownsWatcher) {
      await _bus.requestName(
        standardWatcherName,
        flags: const {DBusRequestNameFlag.doNotQueue},
      );
      await _bus.requestName(
        'org.freedesktop.StatusNotifierHost-Trickster$pid',
        flags: const {DBusRequestNameFlag.doNotQueue},
      );
      _watcher.setHostRegistered(true);
      await _watcher.emitHostRegistered();
    } else {
      await _registerWithExternalWatcher(hostName);
    }
  }

  Future<void> _registerWithExternalWatcher(String hostName) async {
    final object = DBusRemoteObject(
      _bus,
      name: watcherName,
      path: DBusObjectPath(watcherPath),
    );
    await object
        .callMethod(watcherInterface, 'RegisterStatusNotifierHost', <DBusValue>[
          DBusString(hostName),
        ], replySignature: DBusSignature(''))
        .timeout(_methodTimeout);
    _watcherSignals = DBusSignalStream(
      _bus,
      sender: watcherName,
      path: DBusObjectPath(watcherPath),
      interface: watcherInterface,
    ).listen((_) => _scheduleExternalWatcherRefresh());
    await _refreshExternalWatcher(object);
  }

  void _scheduleExternalWatcherRefresh() {
    if (_disposed || _ownsWatcher) {
      return;
    }
    _externalWatcherTimer?.cancel();
    _externalWatcherTimer = Timer(_signalCoalesce, () {
      _externalWatcherTimer = null;
      unawaited(
        _refreshExternalWatcher(
          DBusRemoteObject(
            _bus,
            name: watcherName,
            path: DBusObjectPath(watcherPath),
          ),
        ),
      );
    });
  }

  Future<void> _refreshExternalWatcher(DBusRemoteObject object) async {
    try {
      final value = await object
          .getProperty(
            watcherInterface,
            'RegisteredStatusNotifierItems',
            signature: DBusSignature('as'),
          )
          .timeout(_readTimeout);
      final addresses = value.asStringArray().take(_maxItems).toSet();
      for (final address in addresses) {
        await _registerAddress(address, sender: null, emitSignal: false);
      }
      final removed = _registrations.values
          .where((registration) => !addresses.contains(registration.address))
          .toList(growable: false);
      for (final registration in removed) {
        _removeRegistration(registration);
      }
      if (removed.isNotEmpty) {
        _emit();
      }
    } on Object {
      // The owner-change stream retries if the external watcher restarts.
    }
  }

  Future<void> _registerFromMethod(String address, String? sender) {
    return _registerAddress(address, sender: sender, emitSignal: true);
  }

  Future<void> _registerAddress(
    String address, {
    required String? sender,
    required bool emitSignal,
  }) async {
    if (_disposed || _registrations.length >= _maxItems) {
      return;
    }
    final parsed = _parseRegistration(address, sender: sender);
    if (parsed == null || _registrations.containsKey(parsed.id)) {
      return;
    }
    String? owner;
    try {
      owner = await _bus.getNameOwner(parsed.busName).timeout(_readTimeout);
    } on Object {
      return;
    }
    if (owner == null || owner.isEmpty || _disposed) {
      return;
    }
    if (_registrations.values.any(
      (registration) =>
          registration.owner == owner && registration.path == parsed.path,
    )) {
      return;
    }
    final registration = parsed.withOwner(owner);
    _registrations[registration.id] = registration;
    if (_ownsWatcher) {
      _watcher.setRegisteredItems(
        _registrations.values.map((item) => item.address),
      );
      if (emitSignal) {
        await _watcher.emitItemRegistered(registration.address);
      }
    }
    _scheduleItemRefresh(registration.id, full: true, immediate: true);
  }

  void _handleItemSignal(DBusSignal signal) {
    final registration = _registrationForSignal(signal);
    final properties = _itemSignalProperties[signal.name];
    if (registration == null || properties == null) {
      return;
    }
    _itemInterfaces[registration.id] = signal.interface;
    _scheduleItemRefresh(registration.id, properties: properties);
  }

  void _handlePropertiesChanged(DBusSignal signal) {
    final registration = _registrationForSignal(signal);
    if (registration == null || signal.signature != DBusSignature('sa{sv}as')) {
      return;
    }
    try {
      final changed = DBusPropertiesChangedSignal(signal);
      if (!itemInterfaces.contains(changed.propertiesInterface)) {
        return;
      }
      _itemInterfaces[registration.id] = changed.propertiesInterface;
      final properties = _itemProperties.putIfAbsent(
        registration.id,
        () => <String, DBusValue>{},
      );
      var updated = false;
      for (final entry in changed.changedProperties.entries) {
        if (_knownItemProperties.contains(entry.key)) {
          properties[entry.key] = entry.value;
          updated = true;
        }
      }
      if (updated) {
        _updateItem(registration);
      }
      final invalidated = changed.invalidatedProperties
          .where(_knownItemProperties.contains)
          .toSet();
      if (invalidated.isNotEmpty) {
        _scheduleItemRefresh(registration.id, properties: invalidated);
      }
    } on Object {
      _scheduleItemRefresh(registration.id, full: true);
    }
  }

  _StatusNotifierRegistration? _registrationForSignal(DBusSignal signal) {
    final sender = signal.sender;
    if (sender == null) {
      return null;
    }
    for (final registration in _registrations.values) {
      if (registration.owner == sender &&
          registration.path == signal.path.value) {
        return registration;
      }
    }
    return null;
  }

  void _handleOwnerChanged(DBusNameOwnerChangedEvent event) {
    if (!_ownsWatcher && event.name == watcherName && event.newOwner != null) {
      _scheduleExternalWatcherRefresh();
    }
    if (event.newOwner != null) {
      return;
    }
    final removed = _registrations.values
        .where((item) => item.busName == event.name || item.owner == event.name)
        .toList(growable: false);
    for (final registration in removed) {
      _removeRegistration(registration);
      if (_ownsWatcher) {
        unawaited(_watcher.emitItemUnregistered(registration.address));
      }
    }
    if (removed.isNotEmpty) {
      _watcher.setRegisteredItems(
        _registrations.values.map((item) => item.address),
      );
      _emit();
    }
  }

  void _removeRegistration(_StatusNotifierRegistration registration) {
    _registrations.remove(registration.id);
    _items.remove(registration.id);
    _itemInterfaces.remove(registration.id);
    _itemProperties.remove(registration.id);
    _normalPixmaps.remove(registration.id);
    _attentionPixmaps.remove(registration.id);
    _pendingRefreshes.remove(registration.id);
  }

  void _scheduleAllRefreshes() {
    for (final registration in _registrations.values) {
      _scheduleItemRefresh(registration.id, full: true);
    }
  }

  void _scheduleItemRefresh(
    String registrationId, {
    Set<String> properties = const <String>{},
    bool full = false,
    bool immediate = false,
  }) {
    if (_disposed) {
      return;
    }
    final pending = _pendingRefreshes.putIfAbsent(
      registrationId,
      _PendingStatusNotifierRefresh.new,
    );
    if (full) {
      pending.full = true;
      pending.properties.clear();
    } else if (!pending.full) {
      pending.properties.addAll(
        properties.where(_knownItemProperties.contains),
      );
    }
    if (immediate && _signalTimer != null) {
      _signalTimer!.cancel();
      _signalTimer = null;
    }
    _signalTimer ??= Timer(immediate ? Duration.zero : _signalCoalesce, () {
      _signalTimer = null;
      unawaited(_drainRefreshes());
    });
  }

  Future<void> _drainRefreshes() async {
    if (_disposed || _drainingRefreshes) {
      return;
    }
    _drainingRefreshes = true;
    try {
      while (_pendingRefreshes.isNotEmpty && !_disposed) {
        final pending = Map<String, _PendingStatusNotifierRefresh>.of(
          _pendingRefreshes,
        );
        _pendingRefreshes.clear();
        await Future.wait(<Future<void>>[
          for (final entry in pending.entries)
            if (_registrations[entry.key] case final registration?)
              entry.value.full
                  ? _refreshAllProperties(registration)
                  : _refreshProperties(registration, entry.value.properties),
        ]);
      }
    } finally {
      _drainingRefreshes = false;
    }
  }

  Future<void> _refreshAllProperties(
    _StatusNotifierRegistration registration,
  ) async {
    final object = _remoteItem(registration);
    final preferred = _itemInterfaces[registration.id];
    final interfaces = <String>{?preferred, ...itemInterfaces};
    for (final interface in interfaces) {
      try {
        final properties = await object
            .getAllProperties(interface)
            .timeout(_readTimeout);
        _itemInterfaces[registration.id] = interface;
        _itemProperties[registration.id] = Map<String, DBusValue>.of(
          properties,
        );
        _updateItem(registration);
        return;
      } on Object {
        continue;
      }
    }
  }

  Future<void> _refreshProperties(
    _StatusNotifierRegistration registration,
    Set<String> propertyNames,
  ) async {
    if (propertyNames.isEmpty || _disposed) {
      return;
    }
    final object = _remoteItem(registration);
    final preferred = _itemInterfaces[registration.id];
    final interfaces = <String>{?preferred, ...itemInterfaces};
    for (final interface in interfaces) {
      final entries = await Future.wait(<Future<MapEntry<String, DBusValue>?>>[
        for (final property in propertyNames)
          _readProperty(object, interface, property),
      ]);
      final resolved = entries.whereType<MapEntry<String, DBusValue>>();
      if (resolved.isEmpty) {
        continue;
      }
      _itemInterfaces[registration.id] = interface;
      _itemProperties
          .putIfAbsent(registration.id, () => <String, DBusValue>{})
          .addEntries(resolved);
      _updateItem(registration);
      return;
    }
  }

  Future<MapEntry<String, DBusValue>?> _readProperty(
    DBusRemoteObject object,
    String interface,
    String property,
  ) async {
    try {
      final value = await object
          .getProperty(interface, property)
          .timeout(_readTimeout);
      return MapEntry<String, DBusValue>(property, value);
    } on Object {
      return null;
    }
  }

  void _updateItem(_StatusNotifierRegistration registration) {
    final properties = _itemProperties[registration.id];
    if (properties == null || _disposed) {
      return;
    }
    if (properties.remove('IconPixmap') case final rawPixmap?) {
      _normalPixmaps[registration.id] = _bestPixmap(rawPixmap);
    }
    if (properties.remove('AttentionIconPixmap') case final rawPixmap?) {
      _attentionPixmaps[registration.id] = _bestPixmap(rawPixmap);
    }
    final status = _status(_string(properties['Status']));
    final attention = status == SystemTrayStatus.needsAttention;
    var pixmap = attention
        ? _attentionPixmaps[registration.id]
        : _normalPixmaps[registration.id];
    if (attention && pixmap == null) {
      pixmap = _normalPixmaps[registration.id];
    }
    var iconName = _boundedText(
      _string(properties[attention ? 'AttentionIconName' : 'IconName']),
      512,
    );
    if (attention && iconName.isEmpty) {
      iconName = _boundedText(_string(properties['IconName']), 512);
    }
    final themePath = _boundedText(_string(properties['IconThemePath']), 4096);
    pixmap ??= _cachedIconPixmap(iconName, themePath);
    if (pixmap == null && iconName.isNotEmpty) {
      _ensureIconPixmap(iconName, themePath);
    }
    final itemId = _boundedText(_string(properties['Id']), 256);
    final rawTitle = _boundedText(_string(properties['Title']), 256);
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : itemId.isNotEmpty
        ? itemId
        : registration.busName;
    final menuPath = _objectPath(properties['Menu']);
    _items[registration.id] = SystemTrayItem(
      id: registration.id,
      title: title,
      status: status,
      iconName: iconName,
      iconThemePath: themePath,
      iconPixmap: pixmap,
      menuAvailable: menuPath != null && menuPath != '/',
      primaryOpensMenu: _boolean(properties['ItemIsMenu']),
      menuPath: menuPath ?? '',
    );
    _emit();
  }

  /// The decoded icon-name cache entry for one item, or null while the file
  /// lookup and decode are pending (or when the name is unknown).
  SystemTrayIconPixmap? _cachedIconPixmap(String iconName, String themePath) {
    if (iconName.isEmpty) {
      return null;
    }
    final key = _iconCacheKey(iconName, themePath);
    return _iconFiles.containsKey(key) ? _iconFiles[key] : null;
  }

  void _ensureIconPixmap(String iconName, String themePath) {
    final key = _iconCacheKey(iconName, themePath);
    if (_iconFiles.containsKey(key) || !_iconLoads.add(key)) {
      return;
    }
    unawaited(_loadIconPixmap(key, iconName, themePath));
  }

  static String _iconCacheKey(String iconName, String themePath) =>
      '$iconName\u0000$themePath';

  /// Resolves the file path off the UI isolate, then decodes it in-place at
  /// the display size. Results are cached per name/theme and per path; the
  /// item is re-emitted once the icon lands.
  Future<void> _loadIconPixmap(
    String key,
    String iconName,
    String themePath,
  ) async {
    SystemTrayIconPixmap? pixmap;
    try {
      final path = await _iconPath(iconName, themePath);
      if (path != null) {
        pixmap = await _decodeIconFile(path);
      }
    } on Object {
      pixmap = null;
    } finally {
      _iconLoads.remove(key);
    }
    if (_disposed) {
      return;
    }
    _storeIconFile(key, pixmap);
    for (final item in List<SystemTrayItem>.of(_items.values)) {
      if (item.iconName == iconName && item.iconThemePath == themePath) {
        final registration = _registrations[item.id];
        if (registration != null) {
          _updateItem(registration);
        }
      }
    }
  }

  Future<String?> _iconPath(String iconName, String themePath) async {
    final key = _iconCacheKey(iconName, themePath);
    if (_iconPaths.containsKey(key)) {
      return _iconPaths[key];
    }
    String? path;
    try {
      path = await Isolate.run(() => _resolveTrayIconPath(iconName, themePath));
    } on Object {
      path = null;
    }
    _iconPaths.remove(key);
    _iconPaths[key] = path;
    while (_iconPaths.length > _StatusNotifierLimits.maxIconPaths) {
      _iconPaths.remove(_iconPaths.keys.first);
    }
    return path;
  }

  void _storeIconFile(String key, SystemTrayIconPixmap? pixmap) {
    _iconFiles.remove(key);
    _iconFiles[key] = pixmap;
    while (_iconFiles.length > _StatusNotifierLimits.maxDecodedIcons) {
      _iconFiles.remove(_iconFiles.keys.first);
    }
  }

  /// Invokes an item method with the bar-relative pointer position. Returns
  /// false when no interface accepts the call.
  Future<bool> invoke(
    SystemTrayItem item,
    SystemTrayAction action,
    Offset position,
  ) async {
    final registration = _registrations[item.id];
    if (registration == null || _disposed) {
      return false;
    }
    final method = switch (action) {
      SystemTrayAction.activate => 'Activate',
      SystemTrayAction.secondaryActivate => 'SecondaryActivate',
      SystemTrayAction.contextMenu => 'ContextMenu',
    };
    final x = position.dx.round().clamp(-0x80000000, 0x7fffffff);
    final y = position.dy.round().clamp(-0x80000000, 0x7fffffff);
    final preferred = _itemInterfaces[registration.id];
    final interfaces = <String>{?preferred, ...itemInterfaces};
    for (final interface in interfaces) {
      try {
        await _remoteItem(registration)
            .callMethod(interface, method, <DBusValue>[
              DBusInt32(x),
              DBusInt32(y),
            ], replySignature: DBusSignature(''))
            .timeout(_methodTimeout);
        _itemInterfaces[registration.id] = interface;
        return true;
      } on Object {
        continue;
      }
    }
    _scheduleItemRefresh(registration.id, full: true, immediate: true);
    return false;
  }

  /// Reads the item's `com.canonical.dbusmenu` layout, or null when the item
  /// exposes no usable menu.
  Future<List<SystemTrayMenuEntry>?> loadMenu(SystemTrayItem item) async {
    final registration = _registrations[item.id];
    if (registration == null ||
        _disposed ||
        !item.menuAvailable ||
        item.menuPath.isEmpty ||
        item.menuPath == '/') {
      return null;
    }
    DBusObjectPath path;
    try {
      path = DBusObjectPath(item.menuPath);
    } on Object {
      return null;
    }
    final object = DBusRemoteObject(
      _bus,
      name: registration.busName,
      path: path,
    );
    try {
      await object
          .callMethod(menuInterface, 'AboutToShow', const <DBusValue>[
            DBusInt32(0),
          ], replySignature: DBusSignature('b'))
          .timeout(_methodTimeout);
    } on Object {
      // Some exporters omit AboutToShow even though their static layout is
      // otherwise usable.
    }
    try {
      final response = await object
          .callMethod(menuInterface, 'GetLayout', <DBusValue>[
            const DBusInt32(0),
            const DBusInt32(_maxMenuDepth),
            DBusArray.string(const <String>[
              'label',
              'enabled',
              'visible',
              'type',
              'children-display',
              'toggle-type',
              'toggle-state',
              'disposition',
            ]),
          ], replySignature: DBusSignature('u(ia{sv}av)'))
          .timeout(_methodTimeout);
      if (response.returnValues.length != 2) {
        return null;
      }
      final budget = _MenuBudget(_maxMenuItems);
      final root = _parseMenuEntry(
        response.returnValues[1],
        budget: budget,
        depth: 0,
      );
      if (root == null) {
        return null;
      }
      return List<SystemTrayMenuEntry>.unmodifiable(
        root.children.where((entry) => entry.visible),
      );
    } on Object {
      return null;
    }
  }

  /// Sends a `clicked` event for [entryId] to the item's menu.
  Future<bool> activateMenuEntry(SystemTrayItem item, int entryId) async {
    final registration = _registrations[item.id];
    if (registration == null ||
        _disposed ||
        entryId <= 0 ||
        item.menuPath.isEmpty ||
        item.menuPath == '/') {
      return false;
    }
    try {
      await DBusRemoteObject(
            _bus,
            name: registration.busName,
            path: DBusObjectPath(item.menuPath),
          )
          .callMethod(menuInterface, 'Event', <DBusValue>[
            DBusInt32(entryId),
            const DBusString('clicked'),
            const DBusVariant(DBusString('')),
            DBusUint32(DateTime.now().millisecondsSinceEpoch & 0xffffffff),
          ], replySignature: DBusSignature(''))
          .timeout(_methodTimeout);
      return true;
    } on Object {
      return false;
    }
  }

  DBusRemoteObject _remoteItem(_StatusNotifierRegistration registration) {
    return DBusRemoteObject(
      _bus,
      name: registration.busName,
      path: DBusObjectPath(registration.path),
    );
  }

  List<SystemTrayItem> _orderedItems() {
    final items = _items.values.toList(growable: false)
      ..sort((left, right) {
        final byStatus = _statusPriority(
          left.status,
        ).compareTo(_statusPriority(right.status));
        return byStatus != 0
            ? byStatus
            : left.title.toLowerCase().compareTo(right.title.toLowerCase());
      });
    return List<SystemTrayItem>.unmodifiable(items);
  }

  void _emit() {
    final next = _orderedItems();
    if (!_snapshots.isClosed && !listEquals(_lastSnapshot, next)) {
      _lastSnapshot = next;
      _snapshots.add(next);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _signalTimer?.cancel();
    _externalWatcherTimer?.cancel();
    _pendingRefreshes.clear();
    for (final subscription in _itemSignals) {
      await subscription.cancel();
    }
    await _watcherSignals?.cancel();
    await _ownerChanges?.cancel();
    if (_started) {
      await _bus.unregisterObject(_watcher);
    }
    await _snapshots.close();
    await _client?.close();
  }
}

/// The watcher object this host exports on the session bus.
@visibleForTesting
class StatusNotifierWatcherEndpoint extends DBusObject {
  StatusNotifierWatcherEndpoint()
    : super(DBusObjectPath(StatusNotifierService.watcherPath));

  Future<void> Function(String address, String? sender)? onRegisterItem;
  Future<void> Function(String host)? onRegisterHost;
  List<String> _registeredItems = const <String>[];
  bool _hostRegistered = false;

  void setRegisteredItems(Iterable<String> registrations) {
    _registeredItems = List<String>.unmodifiable(registrations);
  }

  void setHostRegistered(bool value) {
    _hostRegistered = value;
  }

  Future<void> emitItemRegistered(String address) async {
    for (final interface in <String>[
      StatusNotifierService.watcherInterface,
      StatusNotifierService.standardWatcherInterface,
    ]) {
      await emitSignal(interface, 'StatusNotifierItemRegistered', <DBusValue>[
        DBusString(address),
      ]);
    }
  }

  Future<void> emitItemUnregistered(String address) async {
    for (final interface in <String>[
      StatusNotifierService.watcherInterface,
      StatusNotifierService.standardWatcherInterface,
    ]) {
      await emitSignal(interface, 'StatusNotifierItemUnregistered', <DBusValue>[
        DBusString(address),
      ]);
    }
  }

  Future<void> emitHostRegistered() async {
    for (final interface in <String>[
      StatusNotifierService.watcherInterface,
      StatusNotifierService.standardWatcherInterface,
    ]) {
      await emitSignal(interface, 'StatusNotifierHostRegistered');
    }
  }

  @override
  List<DBusIntrospectInterface> introspect() => <DBusIntrospectInterface>[
    for (final interface in <String>[
      StatusNotifierService.watcherInterface,
      StatusNotifierService.standardWatcherInterface,
    ])
      DBusIntrospectInterface(
        interface,
        methods: <DBusIntrospectMethod>[
          _watcherMethod('RegisterStatusNotifierItem'),
          _watcherMethod('RegisterStatusNotifierHost'),
        ],
        properties: <DBusIntrospectProperty>[
          DBusIntrospectProperty(
            'RegisteredStatusNotifierItems',
            DBusSignature('as'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'IsStatusNotifierHostRegistered',
            DBusSignature('b'),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            'ProtocolVersion',
            DBusSignature('i'),
            access: DBusPropertyAccess.read,
          ),
        ],
        signals: <DBusIntrospectSignal>[
          _watcherSignal('StatusNotifierItemRegistered'),
          _watcherSignal('StatusNotifierItemUnregistered'),
          DBusIntrospectSignal('StatusNotifierHostRegistered'),
          DBusIntrospectSignal('StatusNotifierHostUnregistered'),
        ],
      ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != StatusNotifierService.watcherInterface &&
        methodCall.interface !=
            StatusNotifierService.standardWatcherInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (methodCall.signature != DBusSignature('s')) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    switch (methodCall.name) {
      case 'RegisterStatusNotifierItem':
        final callback = onRegisterItem;
        if (callback == null) {
          return DBusMethodErrorResponse.failed('Tray host is unavailable');
        }
        await callback(methodCall.values.first.asString(), methodCall.sender);
        return DBusMethodSuccessResponse();
      case 'RegisterStatusNotifierHost':
        await onRegisterHost?.call(methodCall.values.first.asString());
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface != StatusNotifierService.watcherInterface &&
        interface != StatusNotifierService.standardWatcherInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return switch (name) {
      'RegisteredStatusNotifierItems' => DBusGetPropertyResponse(
        DBusArray.string(_registeredItems),
      ),
      'IsStatusNotifierHostRegistered' => DBusGetPropertyResponse(
        DBusBoolean(_hostRegistered),
      ),
      'ProtocolVersion' => DBusGetPropertyResponse(const DBusInt32(0)),
      _ => DBusMethodErrorResponse.unknownProperty(),
    };
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != StatusNotifierService.watcherInterface &&
        interface != StatusNotifierService.standardWatcherInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(<String, DBusValue>{
      'RegisteredStatusNotifierItems': DBusArray.string(_registeredItems),
      'IsStatusNotifierHostRegistered': DBusBoolean(_hostRegistered),
      'ProtocolVersion': const DBusInt32(0),
    });
  }
}

DBusIntrospectMethod _watcherMethod(String name) => DBusIntrospectMethod(
  name,
  args: <DBusIntrospectArgument>[
    DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.in_),
  ],
);

DBusIntrospectSignal _watcherSignal(String name) => DBusIntrospectSignal(
  name,
  args: <DBusIntrospectArgument>[
    DBusIntrospectArgument(DBusSignature('s'), DBusArgumentDirection.out),
  ],
);

class _PendingStatusNotifierRefresh {
  bool full = false;
  final Set<String> properties = <String>{};
}

class _MenuBudget {
  _MenuBudget(this.remaining);

  int remaining;
}

SystemTrayMenuEntry? _parseMenuEntry(
  DBusValue value, {
  required _MenuBudget budget,
  required int depth,
}) {
  if (budget.remaining <= 0 || depth > StatusNotifierService._maxMenuDepth) {
    return null;
  }
  try {
    final fields = value.asStruct();
    if (fields.length != 3) {
      return null;
    }
    final id = fields[0].asInt32();
    final properties = fields[1].asStringVariantDict();
    final children = <SystemTrayMenuEntry>[];
    if (depth < StatusNotifierService._maxMenuDepth) {
      for (final child in fields[2].asArray()) {
        if (budget.remaining <= 0) {
          break;
        }
        final parsed = _parseMenuEntry(
          child.asVariant(),
          budget: budget,
          depth: depth + 1,
        );
        if (parsed != null) {
          children.add(parsed);
        }
      }
    }
    budget.remaining -= 1;
    final type = _string(properties['type']);
    final toggleType = switch (_string(properties['toggle-type'])) {
      'checkmark' => SystemTrayMenuToggleType.checkmark,
      'radio' => SystemTrayMenuToggleType.radio,
      _ => SystemTrayMenuToggleType.none,
    };
    return SystemTrayMenuEntry(
      id: id,
      label: _menuLabel(_boundedText(_string(properties['label']), 512)),
      enabled: properties.containsKey('enabled')
          ? _boolean(properties['enabled'])
          : true,
      visible: properties.containsKey('visible')
          ? _boolean(properties['visible'])
          : true,
      separator: type == 'separator',
      toggleType: toggleType,
      toggleState: _int32(properties['toggle-state']),
      destructive: _string(properties['disposition']) == 'warning',
      children: List<SystemTrayMenuEntry>.unmodifiable(children),
    );
  } on Object {
    return null;
  }
}

int _int32(DBusValue? value) {
  try {
    return value?.asInt32() ?? 0;
  } on Object {
    return 0;
  }
}

String _menuLabel(String value) {
  final output = StringBuffer();
  for (var index = 0; index < value.length; index += 1) {
    final character = value[index];
    if (character != '_') {
      output.write(character);
      continue;
    }
    if (index + 1 < value.length && value[index + 1] == '_') {
      output.write('_');
      index += 1;
    }
  }
  return output.toString();
}

class _StatusNotifierRegistration {
  const _StatusNotifierRegistration({
    required this.busName,
    required this.path,
    required this.owner,
  });

  final String busName;
  final String path;
  final String owner;

  String get id => 'status-notifier:$busName:$path';

  String get address => '$busName$path';

  _StatusNotifierRegistration withOwner(String value) =>
      _StatusNotifierRegistration(busName: busName, path: path, owner: value);
}

_StatusNotifierRegistration? _parseRegistration(
  String value, {
  required String? sender,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 4096) {
    return null;
  }
  if (trimmed.startsWith('/')) {
    if (sender == null || sender.isEmpty) {
      return null;
    }
    try {
      DBusObjectPath(trimmed);
      return _StatusNotifierRegistration(
        busName: sender,
        path: trimmed,
        owner: sender,
      );
    } on Object {
      return null;
    }
  }
  final slash = trimmed.indexOf('/');
  final busName = slash < 0 ? trimmed : trimmed.substring(0, slash);
  final path = slash < 0 ? '/StatusNotifierItem' : trimmed.substring(slash);
  try {
    if (!_isValidBusName(busName)) {
      return null;
    }
    DBusObjectPath(path);
    return _StatusNotifierRegistration(busName: busName, path: path, owner: '');
  } on Object {
    return null;
  }
}

bool _isValidBusName(String value) {
  if (value.isEmpty || value.length > 255) {
    return false;
  }
  final unique = value.startsWith(':');
  final body = unique ? value.substring(1) : value;
  final parts = body.split('.');
  if (parts.length < 2 || parts.any((part) => part.isEmpty)) {
    return false;
  }
  final segment = unique
      ? RegExp(r'^[A-Za-z0-9_-]+$')
      : RegExp(r'^[A-Za-z_-][A-Za-z0-9_-]*$');
  return parts.every(segment.hasMatch);
}

String _string(DBusValue? value, {String fallback = ''}) {
  try {
    return value?.asString() ?? fallback;
  } on Object {
    return fallback;
  }
}

String? _objectPath(DBusValue? value) {
  try {
    return value?.asObjectPath().value;
  } on Object {
    return null;
  }
}

bool _boolean(DBusValue? value) {
  try {
    return value?.asBoolean() ?? false;
  } on Object {
    return false;
  }
}

String _boundedText(String value, int maxLength) {
  final normalized = value.replaceAll('\u0000', '').trim();
  return normalized.length <= maxLength
      ? normalized
      : normalized.substring(0, maxLength);
}

SystemTrayStatus _status(String value) => switch (value.toLowerCase()) {
  'passive' => SystemTrayStatus.passive,
  'needsattention' => SystemTrayStatus.needsAttention,
  _ => SystemTrayStatus.active,
};

SystemTrayStatus _statusFromName(String value) {
  for (final status in SystemTrayStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return SystemTrayStatus.active;
}

int _statusPriority(SystemTrayStatus status) => switch (status) {
  SystemTrayStatus.needsAttention => 0,
  SystemTrayStatus.active => 1,
  SystemTrayStatus.passive => 2,
};

/// Picks the pixmap closest to the display size from an `a(iiay)` array,
/// bounds the input, downscales to at most 64px, and premultiplies the
/// channels. Returns null when nothing usable is present.
SystemTrayIconPixmap? _bestPixmap(DBusValue? value) {
  if (value == null || value.signature != DBusSignature('a(iiay)')) {
    return null;
  }
  _StatusNotifierPixmapCandidate? best;
  for (final entry in value.asArray().take(32)) {
    try {
      final tuple = entry.asStruct();
      if (tuple.length != 3 || tuple[2].signature != DBusSignature('ay')) {
        continue;
      }
      final width = tuple[0].asInt32();
      final height = tuple[1].asInt32();
      final byteCount = width * height * 4;
      if (width <= 0 ||
          height <= 0 ||
          width > _StatusNotifierLimits.maxInputDimension ||
          height > _StatusNotifierLimits.maxInputDimension ||
          byteCount > _StatusNotifierLimits.maxInputIconBytes ||
          tuple[2].asArray().length != byteCount) {
        continue;
      }
      final candidate = _StatusNotifierPixmapCandidate(
        width: width,
        height: height,
        bytes: tuple[2].asArray(),
      );
      if (best == null || candidate.score < best.score) {
        best = candidate;
      }
    } on Object {
      continue;
    }
  }
  return best?.decode();
}

class _StatusNotifierPixmapCandidate {
  const _StatusNotifierPixmapCandidate({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final List<DBusValue> bytes;

  int get score {
    final extent = width > height ? width : height;
    final delta = extent - _StatusNotifierLimits.preferredIconDimension;
    return delta >= 0
        ? delta
        : -delta + _StatusNotifierLimits.maxInputDimension;
  }

  SystemTrayIconPixmap decode() {
    final longest = width > height ? width : height;
    final outputScale = longest <= _StatusNotifierLimits.maxOutputDimension
        ? 1.0
        : _StatusNotifierLimits.maxOutputDimension / longest;
    final outputWidth = (width * outputScale).round().clamp(
      1,
      _StatusNotifierLimits.maxOutputDimension,
    );
    final outputHeight = (height * outputScale).round().clamp(
      1,
      _StatusNotifierLimits.maxOutputDimension,
    );
    final rgba = Uint8List(outputWidth * outputHeight * 4);
    for (var outputY = 0; outputY < outputHeight; outputY += 1) {
      final sourceY = outputY * height ~/ outputHeight;
      for (var outputX = 0; outputX < outputWidth; outputX += 1) {
        final sourceX = outputX * width ~/ outputWidth;
        final sourceOffset = (sourceY * width + sourceX) * 4;
        final outputOffset = (outputY * outputWidth + outputX) * 4;
        final alpha = bytes[sourceOffset].asByte();
        rgba[outputOffset] = _premultiplyChannel(
          bytes[sourceOffset + 1].asByte(),
          alpha,
        );
        rgba[outputOffset + 1] = _premultiplyChannel(
          bytes[sourceOffset + 2].asByte(),
          alpha,
        );
        rgba[outputOffset + 2] = _premultiplyChannel(
          bytes[sourceOffset + 3].asByte(),
          alpha,
        );
        rgba[outputOffset + 3] = alpha;
      }
    }
    return SystemTrayIconPixmap(
      width: outputWidth,
      height: outputHeight,
      rgba: rgba,
    );
  }
}

int _premultiplyChannel(int channel, int alpha) {
  return (channel * alpha + 127) ~/ 255;
}

abstract final class _StatusNotifierLimits {
  static const int preferredIconDimension = 24;
  static const int maxInputDimension = 512;
  static const int maxInputIconBytes =
      maxInputDimension * maxInputDimension * 4;
  static const int maxOutputDimension = 64;
  static const int maxIconPaths = 256;
  static const int maxDecodedIcons = 64;
  static const int maxIconFileBytes = 8 * 1024 * 1024;
}

/// Resolves `IconName`/`IconThemePath` the way a freedesktop host does.
/// Exposed for tests; production runs this on a worker isolate.
@visibleForTesting
String? resolveStatusNotifierIconForTesting(
  String iconName,
  String iconThemePath,
) => _resolveTrayIconPath(iconName, iconThemePath);

/// Decodes an icon file exactly as the service does. Exposed for tests.
@visibleForTesting
Future<SystemTrayIconPixmap?> decodeStatusNotifierIconForTesting(String path) =>
    _decodeIconFile(path);

bool _looksLikeSvg(String path, List<int> bytes) {
  if (path.toLowerCase().endsWith('.svg')) {
    return true;
  }
  final head = utf8.decode(bytes.take(256).toList(), allowMalformed: true);
  return head.contains('<svg');
}

/// Rasterizes an SVG icon at the strip's display size. The vector compiler
/// runs on its own worker isolate inside flutter_svg; the picture is
/// rendered and flattened here so the rest of the pipeline stays pixel-based.
Future<SystemTrayIconPixmap?> _decodeSvgIcon(List<int> bytes) async {
  final info = await vg.loadPicture(
    SvgStringLoader(utf8.decode(bytes, allowMalformed: true)),
    null,
  );
  try {
    final size = info.size;
    if (size.width <= 0 || size.height <= 0) {
      return null;
    }
    final longest = size.width > size.height ? size.width : size.height;
    final scale = _StatusNotifierLimits.preferredIconDimension / longest;
    final width = (size.width * scale).round();
    final height = (size.height * scale).round();
    if (width <= 0 ||
        height <= 0 ||
        width > _StatusNotifierLimits.maxOutputDimension ||
        height > _StatusNotifierLimits.maxOutputDimension) {
      return null;
    }
    final image = await info.picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (data == null) {
        return null;
      }
      return SystemTrayIconPixmap(
        width: image.width,
        height: image.height,
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  } finally {
    info.picture.dispose();
  }
}

const List<String> _trayIconExtensions = <String>['png', 'webp', 'jpg', 'jpeg'];
const List<String> _trayIconSizes = <String>[
  'scalable',
  '128x128',
  '96x96',
  '64x64',
  '48x48',
  '32x32',
  '24x24',
  '22x22',
  '16x16',
];
const List<String> _trayIconContexts = <String>[
  'status',
  'apps',
  'devices',
  'actions',
];
const List<String> _trayThemeSizes = <String>[
  'scalable',
  '512x512',
  '256x256',
  '192x192',
  '128x128',
  '96x96',
  '64x64',
  '48x48',
  '36x36',
  '32x32',
  '24x24',
  '22x22',
  '16x16',
];
const List<String> _trayThemeContexts = <String>[
  'apps',
  'status',
  'actions',
  'devices',
  'categories',
  'places',
  'mimetypes',
  'legacy',
  'panel',
  'ui',
];

String _joinIconPath(String parent, String child) =>
    parent.endsWith('/') ? '$parent$child' : '$parent/$child';

List<String> _uniqueIconPaths(Iterable<String> values) {
  final seen = <String>{};
  final unique = <String>[];
  for (final value in values) {
    if (value.isEmpty || !seen.add(value)) {
      continue;
    }
    unique.add(value);
  }
  return unique;
}

String _stripIconExtension(String name) {
  final lower = name.toLowerCase();
  for (final extension in _trayIconExtensions) {
    final suffix = '.$extension';
    if (lower.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

bool _isSafeIconFile(String path) {
  try {
    final stat = File(path).statSync();
    return stat.type == FileSystemEntityType.file &&
        stat.size > 0 &&
        stat.size <= _StatusNotifierLimits.maxIconFileBytes;
  } on FileSystemException {
    return false;
  }
}

String? _findIconWithExtension(String base) {
  for (final extension in _trayIconExtensions) {
    final path = '$base.$extension';
    if (_isSafeIconFile(path)) {
      return path;
    }
  }
  return null;
}

/// The freedesktop direct-path arm: `IconName` may be an absolute path or a
/// `file://` URI instead of a theme name.
String? _directIconPath(String requested) {
  String path = requested;
  if (requested.startsWith('file://')) {
    final uri = Uri.tryParse(requested);
    if (uri == null || uri.scheme != 'file' || uri.host.isNotEmpty) {
      return null;
    }
    try {
      path = uri.toFilePath();
    } on UnsupportedError {
      return null;
    }
  } else if (!requested.startsWith('/')) {
    return null;
  }
  return File(path).existsSync() ? path : null;
}

String? _resolveTrayIconPath(String iconName, String iconThemePath) {
  final requested = iconName.trim();
  if (requested.isEmpty) {
    return null;
  }
  final direct = _directIconPath(requested);
  if (direct != null) {
    return direct;
  }
  final name = _stripIconExtension(requested);
  if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
    return null;
  }
  for (final root in _uniqueIconPaths(iconThemePath.split(':'))) {
    if (!root.startsWith('/')) {
      continue;
    }
    final direct = _findIconWithExtension(_joinIconPath(root, name));
    if (direct != null) {
      return direct;
    }
    for (final size in _trayIconSizes) {
      for (final context in _trayIconContexts) {
        final candidate = _findIconWithExtension(
          _joinIconPath(
            _joinIconPath(_joinIconPath(root, size), context),
            name,
          ),
        );
        if (candidate != null) {
          return candidate;
        }
      }
    }
  }
  for (final root in _iconRoots()) {
    final pixmap = _findIconWithExtension(
      _joinIconPath(_joinIconPath(root, 'pixmaps'), name),
    );
    if (pixmap != null) {
      return pixmap;
    }
    final iconsDir = Directory(_joinIconPath(root, 'icons'));
    if (!iconsDir.existsSync()) {
      continue;
    }
    final themes = <String>[
      _joinIconPath(iconsDir.path, 'hicolor'),
      _joinIconPath(iconsDir.path, 'Adwaita'),
      _joinIconPath(iconsDir.path, 'Tela'),
    ];
    try {
      for (final entity in iconsDir.listSync(followLinks: false)) {
        if (entity is Directory) {
          themes.add(entity.path);
        }
      }
    } on FileSystemException {
      continue;
    }
    for (final theme in _uniqueIconPaths(themes)) {
      for (final directory in _iconThemeDirectories(theme)) {
        final candidate = _findIconWithExtension(
          _joinIconPath(_joinIconPath(theme, directory), name),
        );
        if (candidate != null) {
          return candidate;
        }
      }
    }
  }
  return null;
}

List<String> _iconRoots() {
  final environment = Platform.environment;
  final home = environment['HOME'] ?? '';
  final dataHome =
      environment['XDG_DATA_HOME'] ??
      (home.isEmpty ? '' : '$home/.local/share');
  final dataDirs =
      (environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share').split(
        ':',
      );
  return _uniqueIconPaths(<String>[
    dataHome,
    ...dataDirs,
    if (home.isNotEmpty) '$home/.local/share/flatpak/exports/share',
    '/var/lib/flatpak/exports/share',
  ]);
}

List<String> _iconThemeDirectories(String theme) {
  final directories = <String>[
    for (final size in _trayThemeSizes)
      for (final context in _trayThemeContexts) _joinIconPath(size, context),
    for (final context in _trayThemeContexts)
      _joinIconPath('symbolic', context),
  ];
  try {
    var inIconTheme = false;
    for (final rawLine in File(
      _joinIconPath(theme, 'index.theme'),
    ).readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.startsWith('[') && line.endsWith(']')) {
        inIconTheme = line == '[Icon Theme]';
        continue;
      }
      if (!inIconTheme) {
        continue;
      }
      final equals = line.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final key = line.substring(0, equals);
      if (key != 'Directories' && key != 'ScaledDirectories') {
        continue;
      }
      for (final value in line.substring(equals + 1).split(',')) {
        final directory = value.trim();
        if (_isSafeRelativeIconDirectory(directory)) {
          directories.add(directory);
        }
      }
    }
  } on FileSystemException {
    // Themes without an index still get the conventional lookup paths.
  }
  return _uniqueIconPaths(directories);
}

bool _isSafeRelativeIconDirectory(String value) {
  if (value.isEmpty || value.startsWith('/')) {
    return false;
  }
  for (final component in value.split('/')) {
    if (component.isEmpty || component == '.' || component == '..') {
      return false;
    }
  }
  return true;
}

/// Decodes an icon file at the strip's display size. [ImageByteFormat.rawRgba]
/// is premultiplied, matching [SystemTrayIconPixmap].
Future<SystemTrayIconPixmap?> _decodeIconFile(String path) async {
  try {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size <= 0 ||
        stat.size > _StatusNotifierLimits.maxIconFileBytes) {
      return null;
    }
    final bytes = await File(path).readAsBytes();
    if (_looksLikeSvg(path, bytes)) {
      return await _decodeSvgIcon(bytes);
    }
    final codec = await instantiateImageCodec(
      bytes,
      targetWidth: _StatusNotifierLimits.preferredIconDimension,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final longest = image.width > image.height ? image.width : image.height;
        if (longest > _StatusNotifierLimits.maxOutputDimension) {
          return null;
        }
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        if (data == null) {
          return null;
        }
        return SystemTrayIconPixmap(
          width: image.width,
          height: image.height,
          rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } on Object {
    return null;
  }
}

@visibleForTesting
SystemTrayIconPixmap? decodeStatusNotifierPixmapForTesting(DBusValue value) =>
    _bestPixmap(value);

const Set<String> _knownItemProperties = <String>{
  'Id',
  'Title',
  'Status',
  'IconName',
  'IconPixmap',
  'AttentionIconName',
  'AttentionIconPixmap',
  'IconThemePath',
  'Menu',
  'ItemIsMenu',
};

const Map<String, Set<String>> _itemSignalProperties = <String, Set<String>>{
  'NewTitle': <String>{'Title'},
  'NewStatus': <String>{'Status'},
  'NewIcon': <String>{'IconName', 'IconPixmap'},
  'NewAttentionIcon': <String>{'AttentionIconName', 'AttentionIconPixmap'},
  'NewIconThemePath': <String>{'IconThemePath'},
};
