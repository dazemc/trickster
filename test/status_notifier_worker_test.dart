import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/status_notifier_protocol.dart';
import 'package:trickster/src/services/status_notifier_worker_proxy.dart';

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitForAsync(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
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
      'trickster-sni-worker',
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

class _FakeTrayItemObject extends DBusObject {
  _FakeTrayItemObject() : super(DBusObjectPath('/StatusNotifierItem'));

  String title = 'Worker Item';
  String iconName = 'worker-icon';
  String menuPath = '/Menu';
  final activations = <({String method, int x, int y})>[];

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
      'Id': DBusString('worker-item'),
      'Title': DBusString(title),
      'Status': DBusString('Active'),
      'IconName': DBusString(iconName),
      'IconThemePath': DBusString(''),
      'Menu': DBusObjectPath(menuPath),
      'ItemIsMenu': DBusBoolean(false),
    });
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (!StatusNotifierService.itemInterfaces.contains(methodCall.interface)) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (methodCall.name == 'Activate' ||
        methodCall.name == 'SecondaryActivate' ||
        methodCall.name == 'ContextMenu') {
      activations.add((
        method: methodCall.name,
        x: methodCall.values[0].asInt32(),
        y: methodCall.values[1].asInt32(),
      ));
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  DBusValue? _value(String name) => switch (name) {
    'Id' => DBusString('worker-item'),
    'Title' => DBusString(title),
    'Status' => DBusString('Active'),
    'IconName' => DBusString('worker-icon'),
    'IconThemePath' => DBusString(''),
    'Menu' => DBusObjectPath(menuPath),
    'ItemIsMenu' => DBusBoolean(false),
    _ => null,
  };
}

class _FakeMenuObject extends DBusObject {
  _FakeMenuObject() : super(DBusObjectPath('/Menu'));

  final events = <int>[];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    switch (methodCall.name) {
      case 'AboutToShow':
        return DBusMethodSuccessResponse(<DBusValue>[const DBusBoolean(true)]);
      case 'GetLayout':
        return DBusMethodSuccessResponse(<DBusValue>[
          const DBusUint32(1),
          DBusStruct(<DBusValue>[
            const DBusInt32(0),
            DBusDict(
              DBusSignature('s'),
              DBusSignature('v'),
              <DBusValue, DBusValue>{},
            ),
            DBusArray(DBusSignature('v'), <DBusValue>[
              DBusVariant(
                DBusStruct(<DBusValue>[
                  const DBusInt32(10),
                  DBusDict(DBusSignature('s'), DBusSignature('v'), <
                    DBusValue,
                    DBusValue
                  >{
                    DBusString('label'): const DBusVariant(DBusString('Quit')),
                    DBusString('enabled'): const DBusVariant(DBusBoolean(true)),
                  }),
                  DBusArray(DBusSignature('v'), <DBusValue>[]),
                ]),
              ),
            ]),
          ]),
        ]);
      case 'Event':
        events.add(methodCall.values[0].asInt32());
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

Future<DBusRemoteObject> _watcherObject(DBusClient client) {
  return Future<DBusRemoteObject>.value(
    DBusRemoteObject(
      client,
      name: StatusNotifierService.watcherName,
      path: DBusObjectPath(StatusNotifierService.watcherPath),
    ),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the real worker owns the watcher and emits a parsed item', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final icons = await Directory.systemTemp.createTemp(
      'trickster-worker-icons',
    );
    addTearDown(() => icons.delete(recursive: true));
    final iconFile = File('${icons.path}/worker.png')
      ..writeAsBytesSync(base64Decode(_pngFixture));

    final proxy = StatusNotifierWorkerProxy(
      startPayload: StatusNotifierStartPayload(
        address: bus.address.value,
        heartbeatInterval: const Duration(milliseconds: 50),
        recoveryBackoff: const <Duration>[
          Duration(milliseconds: 20),
          Duration(milliseconds: 40),
        ],
      ),
      requestTimeout: const Duration(seconds: 5),
      startupTimeout: const Duration(seconds: 5),
    );
    addTearDown(proxy.dispose);

    final snapshots = <List<SystemTrayItem>>[];
    final subscription = proxy.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    await proxy.start();

    expect(proxy.workerIsolateName, 'trickster-sni-worker');

    final probe = bus.client();
    addTearDown(probe.close);
    await _waitForAsync(() async {
      try {
        return (await probe.getNameOwner(StatusNotifierService.watcherName)) !=
            null;
      } on Object {
        return false;
      }
    });

    final tray = bus.client();
    addTearDown(tray.close);
    final itemObject = _FakeTrayItemObject()..iconName = iconFile.path;
    final menuObject = _FakeMenuObject();
    await tray.registerObject(itemObject);
    await tray.registerObject(menuObject);
    await tray.requestName('org.example.WorkerTray');

    final watcher = await _watcherObject(probe);
    await _registerItem(watcher, 'org.example.WorkerTray/StatusNotifierItem');
    await _waitFor(
      () => snapshots.any(
        (items) => items.any(
          (item) => item.title == 'Worker Item' && item.iconPixmap != null,
        ),
      ),
    );

    final item = snapshots
        .lastWhere(
          (items) => items.any(
            (item) => item.title == 'Worker Item' && item.iconPixmap != null,
          ),
        )
        .firstWhere(
          (item) => item.title == 'Worker Item' && item.iconPixmap != null,
        );
    expect(item.status, SystemTrayStatus.active);
    expect(item.iconName, iconFile.path);
    expect(item.menuAvailable, isTrue);
    expect(item.iconPixmap!.width, 24);
    expect(item.iconPixmap!.height, 24);

    expect(
      await proxy.invoke(
        item,
        SystemTrayAction.activate,
        const Offset(12.5, -3.25),
      ),
      isTrue,
    );
    expect(itemObject.activations.single, (method: 'Activate', x: 13, y: -3));

    final entries = await proxy.loadMenu(item);
    expect(entries, isNotNull);
    expect(entries!.single.label, 'Quit');
    expect(await proxy.activateMenuEntry(item, entries.single.id), isTrue);
    expect(menuObject.events, <int>[entries.single.id]);

    await proxy.dispose();
    await _waitForAsync(() async {
      try {
        return (await probe.getNameOwner(StatusNotifierService.watcherName)) ==
            null;
      } on Object {
        return false;
      }
    });
  });

  test('protocol limits stay bounded for the integration payloads', () {
    expect(StatusNotifierProtocolLimits.maxItems, 64);
    expect(StatusNotifierProtocolLimits.maxIconDimension, 64);
    expect(
      StatusNotifierProtocolLimits.maxIconBytes,
      StatusNotifierProtocolLimits.maxIconDimension *
          StatusNotifierProtocolLimits.maxIconDimension *
          4,
    );
  });
}

/// A 4x4 opaque red PNG: small, valid, and decodable by the engine codec.
const String _pngFixture =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGP4z8DwHxkzkC4AADxAH+HggXe0AAAAAElFTkSuQmCC';
