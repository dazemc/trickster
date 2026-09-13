import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// StatusNotifier item status, in ascending attention order.
enum SystemTrayStatus { passive, active, needsAttention }

/// One StatusNotifier item tracked by the host.
@immutable
class SystemTrayItem {
  const SystemTrayItem({
    required this.id,
    required this.title,
    required this.status,
    required this.iconName,
    required this.iconThemePath,
    required this.menuAvailable,
    required this.primaryOpensMenu,
    this.menuPath = '',
  });

  final String id;
  final String title;
  final SystemTrayStatus status;
  final String iconName;
  final String iconThemePath;
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
    menuAvailable,
    primaryOpensMenu,
    menuPath,
  );
}

/// Hosts the freedesktop/KDE StatusNotifier protocol used by AppIndicator and
/// modern Linux tray applications.
///
/// The host owns `org.kde.StatusNotifierWatcher` when the name is free,
/// registers itself as a host, and tracks every item by its bus name and
/// object path. Items are removed when their name owner disappears. D-Bus
/// runs on the UI isolate for now; Denial isolated it on a worker.
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

  DBusClient? _client;
  final _watcher = StatusNotifierWatcherEndpoint();
  final StreamController<List<SystemTrayItem>> _snapshots =
      StreamController<List<SystemTrayItem>>.broadcast(sync: true);
  final Map<String, _StatusNotifierRegistration> _registrations = {};
  final Map<String, SystemTrayItem> _items = {};
  final Map<String, String> _itemInterfaces = {};
  final Map<String, Map<String, DBusValue>> _itemProperties = {};
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
        .callMethod(
          watcherInterface,
          'RegisterStatusNotifierHost',
          <DBusValue>[DBusString(hostName)],
          replySignature: DBusSignature(''),
        )
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
    final status = _status(_string(properties['Status']));
    final attention = status == SystemTrayStatus.needsAttention;
    var iconName = _boundedText(
      _string(properties[attention ? 'AttentionIconName' : 'IconName']),
      512,
    );
    if (attention && iconName.isEmpty) {
      iconName = _boundedText(_string(properties['IconName']), 512);
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
      iconThemePath: _boundedText(_string(properties['IconThemePath']), 4096),
      menuAvailable: menuPath != null && menuPath != '/',
      primaryOpensMenu: _boolean(properties['ItemIsMenu']),
      menuPath: menuPath ?? '',
    );
    _emit();
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
    await _bus.unregisterObject(_watcher);
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

int _statusPriority(SystemTrayStatus status) => switch (status) {
  SystemTrayStatus.needsAttention => 0,
  SystemTrayStatus.active => 1,
  SystemTrayStatus.passive => 2,
};

const Set<String> _knownItemProperties = <String>{
  'Id',
  'Title',
  'Status',
  'IconName',
  'AttentionIconName',
  'IconThemePath',
  'Menu',
  'ItemIsMenu',
};

const Map<String, Set<String>> _itemSignalProperties = <String, Set<String>>{
  'NewTitle': <String>{'Title'},
  'NewStatus': <String>{'Status'},
  'NewIcon': <String>{'IconName'},
  'NewAttentionIcon': <String>{'AttentionIconName'},
  'NewIconThemePath': <String>{'IconThemePath'},
};
