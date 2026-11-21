import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/status_notifier_models.dart';
import 'package:trickster/src/services/status_notifier_protocol.dart';

final _wireError = throwsA(isA<StatusNotifierWireException>());

StatusNotifierSnapshotItem _item({
  String id = 'status-notifier:org.example.Tray:/StatusNotifierItem',
  StatusNotifierIcon? icon,
  String menuPath = '',
}) {
  return StatusNotifierSnapshotItem(
    id: id,
    title: 'Test Item',
    status: SystemTrayStatus.active,
    iconName: 'test-icon',
    iconThemePath: '/tmp/icons',
    icon: icon ?? StatusNotifierIcon.none(),
    menuAvailable: menuPath.isNotEmpty,
    primaryOpensMenu: false,
    menuPath: menuPath,
  );
}

SystemTrayMenuEntry _menuEntry(
  int id, {
  String label = 'Entry',
  List<SystemTrayMenuEntry> children = const <SystemTrayMenuEntry>[],
}) {
  return SystemTrayMenuEntry(
    id: id,
    label: label,
    enabled: true,
    visible: true,
    separator: false,
    toggleType: SystemTrayMenuToggleType.none,
    toggleState: 0,
    destructive: false,
    children: children,
  );
}

void main() {
  test('start payloads round-trip with test bus options', () {
    const payload = StatusNotifierStartPayload(
      address: 'unix:path=/tmp/trickster-sni-bus',
      heartbeatInterval: Duration(milliseconds: 20),
      recoveryBackoff: <Duration>[
        Duration(milliseconds: 10),
        Duration(milliseconds: 30),
      ],
    );

    final decoded = StatusNotifierStartPayload.decode(payload.toJson());

    expect(decoded.address, payload.address);
    expect(decoded.heartbeatInterval, payload.heartbeatInterval);
    expect(decoded.recoveryBackoff, payload.recoveryBackoff);
    expect(const StatusNotifierStartPayload().toJson(), isNull);
  });

  test('commands round-trip by operation and request id', () {
    final commands = <StatusNotifierCommand>[
      const StatusNotifierCommand(
        requestId: 1,
        operation: StatusNotifierWorkerOperation.start,
        payload: <String, Object?>{'address': 'unix:path=/tmp/bus'},
      ),
      StatusNotifierCommand(
        requestId: 2,
        operation: StatusNotifierWorkerOperation.invoke,
        payload: const StatusNotifierInvokePayload(
          itemId: 'item',
          action: SystemTrayAction.secondaryActivate,
          dx: 12.5,
          dy: -3.0,
        ).toMessage(),
      ),
      StatusNotifierCommand(
        requestId: 3,
        operation: StatusNotifierWorkerOperation.loadMenu,
        payload: const StatusNotifierItemIdPayload('item').toMessage(),
      ),
      StatusNotifierCommand(
        requestId: 4,
        operation: StatusNotifierWorkerOperation.activateMenuEntry,
        payload: const StatusNotifierActivateMenuPayload(
          itemId: 'item',
          entryId: 7,
        ).toMessage(),
      ),
      const StatusNotifierCommand(
        requestId: 5,
        operation: StatusNotifierWorkerOperation.dispose,
      ),
    ];

    for (final command in commands) {
      final decoded = StatusNotifierCommand.decode(command.toMessage());
      expect(decoded.requestId, command.requestId);
      expect(decoded.operation, command.operation);
    }
  });

  test('invoke payloads preserve rounded and fractional coordinates', () {
    final decoded = StatusNotifierInvokePayload.decode(
      const StatusNotifierInvokePayload(
        itemId: 'item',
        action: SystemTrayAction.contextMenu,
        dx: 12.75,
        dy: -4.25,
      ).toMessage(),
    );

    expect(decoded.itemId, 'item');
    expect(decoded.action, SystemTrayAction.contextMenu);
    expect(decoded.dx, 12.75);
    expect(decoded.dy, -4.25);
  });

  test('snapshot round-trips rgba, file, none, and unchanged icons', () {
    final rgba = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
    final snapshot = StatusNotifierSnapshot(<StatusNotifierSnapshotItem>[
      _item(
        id: 'rgba',
        icon: StatusNotifierIcon.rgba(
          width: 2,
          height: 1,
          digest: 42,
          rgba: rgba,
        ),
      ),
      _item(id: 'file', icon: StatusNotifierIcon.file('/tmp/icon.svg')),
      _item(id: 'none'),
      _item(id: 'unchanged', icon: StatusNotifierIcon.unchanged()),
    ]);

    final message = snapshot.toMessage();
    final decoded = StatusNotifierSnapshot.decodeItems(message[1]);

    expect(decoded, hasLength(4));
    expect(decoded[0].id, 'rgba');
    expect(decoded[0].icon.kind, StatusNotifierIconKind.rgba);
    expect(decoded[0].icon.width, 2);
    expect(decoded[0].icon.height, 1);
    expect(decoded[0].icon.digest, 42);
    expect(decoded[0].icon.rgba, rgba);
    expect(decoded[1].icon.kind, StatusNotifierIconKind.file);
    expect(decoded[1].icon.path, '/tmp/icon.svg');
    expect(decoded[2].icon.kind, StatusNotifierIconKind.none);
    expect(decoded[3].icon.kind, StatusNotifierIconKind.unchanged);
  });

  test('menu trees round-trip with labels and toggles', () {
    final entries = <SystemTrayMenuEntry>[
      _menuEntry(10, label: 'Play'),
      _menuEntry(
        11,
        label: 'More',
        children: <SystemTrayMenuEntry>[_menuEntry(12, label: 'Subitem')],
      ),
    ];

    final decoded = decodeStatusNotifierMenuEntries(
      encodeStatusNotifierMenuEntries(entries),
    );

    expect(decoded, entries);
  });

  test('replies and start results round-trip', () {
    final ok = StatusNotifierReply.decode(
      const StatusNotifierReply(
        requestId: 3,
        ok: true,
        result: true,
      ).toMessage(),
    );
    expect(ok.requestId, 3);
    expect(ok.ok, isTrue);
    expect(ok.result, isTrue);

    final failed = StatusNotifierReply.decode(
      const StatusNotifierReply(
        requestId: 4,
        ok: false,
        error: 'bad',
        stack: 'stack',
      ).toMessage(),
    );
    expect(failed.ok, isFalse);
    expect(failed.error, 'bad');

    final result = StatusNotifierStartResult.decode(
      const StatusNotifierStartResult(
        isolateName: 'trickster-sni-worker',
        protocolVersion: StatusNotifierProtocolLimits.protocolVersion,
      ).toJson(),
    );
    expect(result.isolateName, 'trickster-sni-worker');
  });

  test('malformed commands and replies are rejected', () {
    expect(() => StatusNotifierCommand.decode(null), _wireError);
    expect(
      () => StatusNotifierCommand.decode(<Object?>[1, 99, null]),
      _wireError,
    );
    expect(
      () => StatusNotifierCommand.decode(<Object?>[-1, 0, null]),
      _wireError,
    );
    expect(() => StatusNotifierReply.decode(<Object?>[1, true]), _wireError);
    expect(
      () => StatusNotifierReply.decode(<Object?>[1, false, 3]),
      _wireError,
    );
    expect(
      () => StatusNotifierStartPayload.decode(<Object?, Object?>{1: 'x'}),
      _wireError,
    );
  });

  test('oversized and malformed icons are rejected', () {
    expect(
      () => StatusNotifierIcon.decode(<Object?>[0, 1, 0, 0, null, '']),
      _wireError,
    );
    expect(
      () => StatusNotifierIcon.decode(<Object?>[1, 0, 1, 0, null, '']),
      _wireError,
    );
    expect(
      () => StatusNotifierIcon.decode(<Object?>[1, 2, 1, 0, null, '']),
      _wireError,
    );
    expect(
      () => StatusNotifierIcon.decode(<Object?>[2, 0, 0, 0, null, '']),
      _wireError,
    );
  });

  test('oversized snapshots, strings, and payloads are rejected', () {
    final tooMany = <Object?>[
      for (var i = 0; i < StatusNotifierProtocolLimits.maxItems + 1; i++)
        _item(id: 'item-$i').encode(),
    ];
    expect(() => StatusNotifierSnapshot.decodeItems(tooMany), _wireError);
    expect(
      () => StatusNotifierSnapshotItem.decode(
        _item(id: 'x' * (StatusNotifierProtocolLimits.maxId + 1)).encode(),
      ),
      _wireError,
    );
    expect(
      () => StatusNotifierInvokePayload.decode(<Object?>[
        'item',
        SystemTrayAction.activate.index,
        double.nan,
        0.0,
      ]),
      _wireError,
    );
    expect(
      () => StatusNotifierStartPayload.decode(<String, Object?>{
        'recovery_backoff_ms': <int>[for (var i = 0; i < 9; i++) 10],
      }),
      _wireError,
    );
  });

  test('oversized and malformed menus are rejected', () {
    final tooMany = <SystemTrayMenuEntry>[
      for (var i = 0; i < StatusNotifierProtocolLimits.maxMenuItems + 1; i++)
        _menuEntry(i + 1),
    ];
    expect(() => encodeStatusNotifierMenuEntries(tooMany), _wireError);

    var deep = _menuEntry(1);
    for (var depth = 0; depth < 6; depth++) {
      deep = _menuEntry(1, children: <SystemTrayMenuEntry>[deep]);
    }
    expect(
      () => encodeStatusNotifierMenuEntries(<SystemTrayMenuEntry>[deep]),
      _wireError,
    );
    expect(
      () => decodeStatusNotifierMenuEntries(<Object?>[
        <Object?>[
          1,
          'x' * (StatusNotifierProtocolLimits.maxMenuLabel + 1),
          true,
          true,
          false,
          0,
          0,
          false,
          <Object?>[],
        ],
      ]),
      _wireError,
    );
    expect(
      () => decodeStatusNotifierMenuEntries(<Object?>[
        <Object?>[1, 'Entry', true, true, false, 99, 0, false, <Object?>[]],
      ]),
      _wireError,
    );
  });
}
