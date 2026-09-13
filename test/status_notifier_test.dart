import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/status_notifier.dart';

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// An in-process message bus: the real D-Bus codec, a fake session bus.
class _FakeBus {
  _FakeBus._(this.server, this.address, this.directory);

  final DBusServer server;
  final DBusAddress address;
  final Directory directory;

  static Future<_FakeBus> start() async {
    final directory = await Directory.systemTemp.createTemp('trickster-sni');
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

/// A minimal StatusNotifierItem exporter served by the fake bus.
class _FakeTrayItemObject extends DBusObject {
  _FakeTrayItemObject({DBusObjectPath? path})
    : super(path ?? DBusObjectPath('/StatusNotifierItem'));

  String id = 'test-item';
  String title = 'Test Item';
  String status = 'Active';
  String iconName = 'test-icon';
  String iconThemePath = '';
  bool itemIsMenu = false;
  String menuPath = '/';
  DBusValue? iconPixmap;
  DBusValue? attentionIconPixmap;

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (!StatusNotifierService.itemInterfaces.contains(interface)) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = _value(name);
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (!StatusNotifierService.itemInterfaces.contains(interface)) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return DBusGetAllPropertiesResponse(<String, DBusValue>{
      'Id': DBusString(id),
      'Title': DBusString(title),
      'Status': DBusString(status),
      'IconName': DBusString(iconName),
      'IconThemePath': DBusString(iconThemePath),
      'Menu': DBusObjectPath(menuPath),
      'ItemIsMenu': DBusBoolean(itemIsMenu),
      'IconPixmap': ?iconPixmap,
      'AttentionIconPixmap': ?attentionIconPixmap,
    });
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    return DBusMethodErrorResponse.unknownMethod();
  }

  DBusValue? _value(String name) => switch (name) {
    'Id' => DBusString(id),
    'Title' => DBusString(title),
    'Status' => DBusString(status),
    'IconName' => DBusString(iconName),
    'IconThemePath' => DBusString(iconThemePath),
    'Menu' => DBusObjectPath(menuPath),
    'ItemIsMenu' => DBusBoolean(itemIsMenu),
    'IconPixmap' => iconPixmap,
    'AttentionIconPixmap' => attentionIconPixmap,
    _ => null,
  };

  Future<void> emitPropertyChanged(String name, DBusValue value) {
    return emitSignal(
      'org.freedesktop.DBus.Properties',
      'PropertiesChanged',
      <DBusValue>[
        DBusString(StatusNotifierService.itemInterface),
        DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
          DBusString(name): DBusVariant(value),
        }),
        DBusArray(DBusSignature('s')),
      ],
    );
  }
}

/// A watcher already owning the well-known name, used for the host path.
class _FakeExternalWatcherObject extends DBusObject {
  _FakeExternalWatcherObject() : super(DBusObjectPath('/StatusNotifierWatcher'));

  final registeredHosts = <String>[];
  List<String> items = const <String>[];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    switch (methodCall.name) {
      case 'RegisterStatusNotifierHost':
        registeredHosts.add(methodCall.values.first.asString());
        return DBusMethodSuccessResponse();
      case 'RegisterStatusNotifierItem':
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    return switch (name) {
      'RegisteredStatusNotifierItems' => DBusGetPropertyResponse(
        DBusArray.string(items),
      ),
      'IsStatusNotifierHostRegistered' => DBusGetPropertyResponse(
        const DBusBoolean(true),
      ),
      'ProtocolVersion' => DBusGetPropertyResponse(const DBusInt32(0)),
      _ => DBusMethodErrorResponse.unknownProperty(),
    };
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(<String, DBusValue>{
      'RegisteredStatusNotifierItems': DBusArray.string(items),
      'IsStatusNotifierHostRegistered': const DBusBoolean(true),
      'ProtocolVersion': const DBusInt32(0),
    });
  }
}

Future<DBusRemoteObject> _watcherObject(DBusClient client) async {
  return DBusRemoteObject(
    client,
    name: StatusNotifierService.watcherName,
    path: DBusObjectPath(StatusNotifierService.watcherPath),
  );
}

Future<void> _registerItem(DBusRemoteObject watcher, String address) {
  return watcher.callMethod(
    StatusNotifierService.watcherInterface,
    'RegisterStatusNotifierItem',
    <DBusValue>[DBusString(address)],
    replySignature: DBusSignature(''),
  );
}

DBusValue _pixmap(List<(int, int, List<int>)> entries) {
  return DBusArray(DBusSignature('(iiay)'), [
    for (final (width, height, bytes) in entries)
      DBusStruct([
        DBusInt32(width),
        DBusInt32(height),
        DBusArray.byte(bytes),
      ]),
  ]);
}

List<int> _argbBytes(int width, int height, int alpha) {
  return [
    for (var i = 0; i < width * height; i++) ...[alpha, 10, 20, 30],
  ];
}

void main() {
  test('hosts the watcher and answers host queries', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = StatusNotifierService(client: bus.client());
    addTearDown(service.dispose);
    await service.start();

    final probe = bus.client();
    addTearDown(probe.close);
    expect(
      await probe.getNameOwner(StatusNotifierService.watcherName),
      isNotNull,
    );
    final watcher = await _watcherObject(probe);
    final hostRegistered = await watcher.getProperty(
      StatusNotifierService.watcherInterface,
      'IsStatusNotifierHostRegistered',
      signature: DBusSignature('b'),
    );
    expect(hostRegistered.asBoolean(), isTrue);
    final items = await watcher.getProperty(
      StatusNotifierService.watcherInterface,
      'RegisteredStatusNotifierItems',
      signature: DBusSignature('as'),
    );
    expect(items.asStringArray(), isEmpty);
  });

  test('tracks a registered item by service name', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = StatusNotifierService(client: bus.client());
    addTearDown(service.dispose);
    final snapshots = <List<SystemTrayItem>>[];
    final subscription = service.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await service.start();

    final tray = bus.client();
    addTearDown(tray.close);
    await tray.registerObject(_FakeTrayItemObject());
    await tray.requestName('org.example.Tray');

    final probe = bus.client();
    addTearDown(probe.close);
    final watcher = await _watcherObject(probe);
    await _registerItem(watcher, 'org.example.Tray/StatusNotifierItem');
    await _waitFor(() => snapshots.isNotEmpty);

    final item = snapshots.last.single;
    expect(item.title, 'Test Item');
    expect(item.status, SystemTrayStatus.active);
    expect(item.iconName, 'test-icon');
    expect(item.menuAvailable, isFalse);
    expect(item.primaryOpensMenu, isFalse);

    final items = await watcher.getProperty(
      StatusNotifierService.watcherInterface,
      'RegisteredStatusNotifierItems',
      signature: DBusSignature('as'),
    );
    expect(items.asStringArray(), ['org.example.Tray/StatusNotifierItem']);
  });

  test('updates items from PropertiesChanged and item signals', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = StatusNotifierService(client: bus.client());
    addTearDown(service.dispose);
    final snapshots = <List<SystemTrayItem>>[];
    final subscription = service.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await service.start();

    final tray = bus.client();
    addTearDown(tray.close);
    final itemObject = _FakeTrayItemObject();
    await tray.registerObject(itemObject);
    await tray.requestName('org.example.Tray');

    final probe = bus.client();
    addTearDown(probe.close);
    final watcher = await _watcherObject(probe);
    await _registerItem(watcher, 'org.example.Tray/StatusNotifierItem');
    await _waitFor(() => snapshots.isNotEmpty);

    itemObject.title = 'Renamed';
    await itemObject.emitPropertyChanged('Title', DBusString('Renamed'));
    await _waitFor(() => snapshots.last.single.title == 'Renamed');

    itemObject.status = 'NeedsAttention';
    await itemObject.emitSignal(
      StatusNotifierService.itemInterface,
      'NewStatus',
      <DBusValue>[DBusString('NeedsAttention')],
    );
    await _waitFor(
      () => snapshots.last.single.status == SystemTrayStatus.needsAttention,
    );
  });

  test('removes items when their owner disconnects', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = StatusNotifierService(client: bus.client());
    addTearDown(service.dispose);
    final snapshots = <List<SystemTrayItem>>[];
    final subscription = service.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await service.start();

    final tray = bus.client();
    await tray.registerObject(_FakeTrayItemObject());
    await tray.requestName('org.example.Tray');

    final probe = bus.client();
    addTearDown(probe.close);
    final watcher = await _watcherObject(probe);
    await _registerItem(watcher, 'org.example.Tray/StatusNotifierItem');
    await _waitFor(() => snapshots.isNotEmpty);

    await tray.close();
    await _waitFor(() => snapshots.last.isEmpty);
    final items = await watcher.getProperty(
      StatusNotifierService.watcherInterface,
      'RegisteredStatusNotifierItems',
      signature: DBusSignature('as'),
    );
    expect(items.asStringArray(), isEmpty);
  });

  test('ignores malformed registrations', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = StatusNotifierService(client: bus.client());
    addTearDown(service.dispose);
    await service.start();

    final probe = bus.client();
    addTearDown(probe.close);
    final watcher = await _watcherObject(probe);
    await _registerItem(watcher, 'not a bus name');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(service.current, isEmpty);
  });

  test('registers as host with an existing watcher', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);

    final tray = bus.client();
    addTearDown(tray.close);
    await tray.registerObject(_FakeTrayItemObject());
    await tray.requestName('org.example.Tray');

    final external = bus.client();
    addTearDown(external.close);
    final externalWatcher = _FakeExternalWatcherObject()
      ..items = const ['org.example.Tray/StatusNotifierItem'];
    await external.registerObject(externalWatcher);
    await external.requestName(StatusNotifierService.watcherName);

    final service = StatusNotifierService(client: bus.client());
    addTearDown(service.dispose);
    final snapshots = <List<SystemTrayItem>>[];
    final subscription = service.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await service.start();

    expect(externalWatcher.registeredHosts, isNotEmpty);
    await _waitFor(() => snapshots.isNotEmpty);
    expect(snapshots.single.single.title, 'Test Item');
  });

  test('decodes the pixmap nearest the display size', () {
    final decoded = decodeStatusNotifierPixmapForTesting(
      _pixmap([
        (2, 2, _argbBytes(2, 2, 128)),
        (4, 4, _argbBytes(4, 4, 255)),
      ]),
    )!;
    expect(decoded.width, 4);
    expect(decoded.height, 4);
    expect(decoded.rgba[0], 10);
    expect(decoded.rgba[3], 255);
  });

  test('premultiplies alpha channels', () {
    final decoded = decodeStatusNotifierPixmapForTesting(
      _pixmap([(1, 1, [128, 200, 100, 50])]),
    )!;
    expect(decoded.rgba, [100, 50, 25, 128]);
  });

  test('bounds oversized inputs and rejects malformed candidates', () {
    expect(
      decodeStatusNotifierPixmapForTesting(
        _pixmap([(600, 600, List<int>.filled(600 * 600 * 4, 0))]),
      ),
      isNull,
    );
    expect(
      decodeStatusNotifierPixmapForTesting(
        _pixmap([(4, 4, List<int>.filled(3, 0))]),
      ),
      isNull,
    );
    expect(
      decodeStatusNotifierPixmapForTesting(_pixmap([(0, 4, <int>[])])),
      isNull,
    );
    expect(
      decodeStatusNotifierPixmapForTesting(_pixmap([(-1, 4, <int>[])])),
      isNull,
    );
    final downscaled = decodeStatusNotifierPixmapForTesting(
      _pixmap([(128, 128, _argbBytes(128, 128, 200))]),
    )!;
    expect(downscaled.width, 64);
    expect(downscaled.height, 64);
  });

  test('exposes decoded icon pixmaps and evicts them with the item', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = StatusNotifierService(client: bus.client());
    addTearDown(service.dispose);
    final snapshots = <List<SystemTrayItem>>[];
    final subscription = service.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await service.start();

    final tray = bus.client();
    final itemObject = _FakeTrayItemObject()
      ..iconPixmap = _pixmap([(4, 4, _argbBytes(4, 4, 255))]);
    await tray.registerObject(itemObject);
    await tray.requestName('org.example.Tray');

    final probe = bus.client();
    addTearDown(probe.close);
    final watcher = await _watcherObject(probe);
    await _registerItem(watcher, 'org.example.Tray/StatusNotifierItem');
    await _waitFor(() => snapshots.isNotEmpty);

    final item = snapshots.last.single;
    expect(item.iconPixmap, isNotNull);
    expect(item.iconPixmap!.width, 4);
    expect(item.iconPixmap!.height, 4);

    await tray.close();
    await _waitFor(() => snapshots.last.isEmpty);
  });
}
