import 'dart:isolate' show TransferableTypedData;
import 'dart:typed_data';

import 'package:trickster/src/services/status_notifier_models.dart';

/// Bounds for one StatusNotifier worker message.
abstract final class StatusNotifierProtocolLimits {
  static const int protocolVersion = 1;
  static const int maxItems = 64;
  static const int maxMenuItems = 256;
  static const int maxMenuDepth = 5;
  static const int maxMenuLabel = 512;
  static const int maxId = 8192;
  static const int maxTitle = 256;
  static const int maxIconName = 512;
  static const int maxIconThemePath = 4096;
  static const int maxMenuPath = 4096;
  static const int maxIconDimension = 64;
  static const int maxIconBytes = maxIconDimension * maxIconDimension * 4;
  static const int maxIconPath = 4096;
  static const int maxString = 4096;
  static const int maxBackoffEntries = 8;
  static const int maxDelayMillis = 600000;
}

/// Commands accepted by the StatusNotifier worker isolate.
enum StatusNotifierWorkerOperation {
  start,
  invoke,
  loadMenu,
  activateMenuEntry,
  dispose,
}

/// How one worker snapshot carries an item icon.
enum StatusNotifierIconKind { none, rgba, file, unchanged }

/// A malformed, oversized, or otherwise untrusted worker payload.
class StatusNotifierWireException implements Exception {
  const StatusNotifierWireException(this.message);

  final String message;

  @override
  String toString() => 'StatusNotifierWireException: $message';
}

Never _invalid(String message) => throw StatusNotifierWireException(message);

List<Object?> _asList(Object? value, String what, {int? length}) {
  if (value is! List) {
    _invalid('$what is not a list');
  }
  final list = List<Object?>.from(value);
  if (length != null && list.length != length) {
    _invalid('$what has ${list.length} fields, expected $length');
  }
  return list;
}

String _string(Object? value, String what, int maxLength) {
  if (value is! String || value.length > maxLength) {
    _invalid('$what is not a string of at most $maxLength characters');
  }
  return value;
}

Map<String, Object?> _asMap(Object? value, String what) {
  if (value is! Map) {
    _invalid('$what is not a map');
  }
  try {
    return Map<String, Object?>.from(value);
  } on Object {
    _invalid('$what has non-string keys');
  }
}

int _integer(Object? value, String what, {int min = 0, int? max}) {
  if (value is! int || value < min || (max != null && value > max)) {
    _invalid('$what is not an integer in range');
  }
  return value;
}

bool _boolean(Object? value, String what) {
  if (value is! bool) {
    _invalid('$what is not a boolean');
  }
  return value;
}

double _finiteDouble(Object? value, String what) {
  if (value is! num || !value.isFinite) {
    _invalid('$what is not a finite number');
  }
  return value.toDouble();
}

T _enumValue<T>(Object? value, List<T> values, String what) {
  final index = _integer(value, what, max: values.length - 1);
  return values[index];
}

/// A bounded icon payload. RGBA bytes are premultiplied, matching
/// [SystemTrayIconPixmap].
class StatusNotifierIcon {
  StatusNotifierIcon._({
    required this.kind,
    this.width = 0,
    this.height = 0,
    this.digest = 0,
    this.rgba,
    this.path = '',
  });

  factory StatusNotifierIcon.none() =>
      StatusNotifierIcon._(kind: StatusNotifierIconKind.none);

  factory StatusNotifierIcon.unchanged() =>
      StatusNotifierIcon._(kind: StatusNotifierIconKind.unchanged);

  factory StatusNotifierIcon.rgba({
    required int width,
    required int height,
    required int digest,
    required Uint8List rgba,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        width > StatusNotifierProtocolLimits.maxIconDimension ||
        height > StatusNotifierProtocolLimits.maxIconDimension ||
        rgba.length != width * height * 4) {
      _invalid('invalid RGBA icon dimensions');
    }
    return StatusNotifierIcon._(
      kind: StatusNotifierIconKind.rgba,
      width: width,
      height: height,
      digest: digest,
      rgba: rgba,
    );
  }

  factory StatusNotifierIcon.file(String path) {
    if (path.isEmpty ||
        path.length > StatusNotifierProtocolLimits.maxIconPath) {
      _invalid('invalid icon path');
    }
    return StatusNotifierIcon._(kind: StatusNotifierIconKind.file, path: path);
  }

  final StatusNotifierIconKind kind;
  final int width;
  final int height;
  final int digest;
  final Uint8List? rgba;
  final String path;

  List<Object?> encode() => <Object?>[
    kind.index,
    width,
    height,
    digest,
    rgba == null ? null : TransferableTypedData.fromList(<Uint8List>[rgba!]),
    path,
  ];

  static StatusNotifierIcon decode(Object? value) {
    final fields = _asList(value, 'icon', length: 6);
    final kind = _enumValue(
      fields[0],
      StatusNotifierIconKind.values,
      'icon kind',
    );
    final width = _integer(fields[1], 'icon width');
    final height = _integer(fields[2], 'icon height');
    final digest = _integer(fields[3], 'icon digest');
    final path = _string(
      fields[5],
      'icon path',
      StatusNotifierProtocolLimits.maxIconPath,
    );
    switch (kind) {
      case StatusNotifierIconKind.none:
      case StatusNotifierIconKind.unchanged:
        if (width != 0 ||
            height != 0 ||
            digest != 0 ||
            fields[4] != null ||
            path.isNotEmpty) {
          _invalid('empty icon carries a payload');
        }
        return StatusNotifierIcon._(kind: kind);
      case StatusNotifierIconKind.rgba:
        if (width <= 0 ||
            height <= 0 ||
            width > StatusNotifierProtocolLimits.maxIconDimension ||
            height > StatusNotifierProtocolLimits.maxIconDimension) {
          _invalid('RGBA icon dimensions are out of bounds');
        }
        final bytes = fields[4];
        if (bytes is! TransferableTypedData) {
          _invalid('RGBA icon bytes are missing');
        }
        final rgba = bytes.materialize().asUint8List();
        if (rgba.length != width * height * 4 ||
            rgba.length > StatusNotifierProtocolLimits.maxIconBytes ||
            path.isNotEmpty) {
          _invalid('RGBA icon byte length is invalid');
        }
        return StatusNotifierIcon._(
          kind: kind,
          width: width,
          height: height,
          digest: digest,
          rgba: rgba,
        );
      case StatusNotifierIconKind.file:
        if (width != 0 ||
            height != 0 ||
            digest != 0 ||
            fields[4] != null ||
            path.isEmpty) {
          _invalid('file icon carries the wrong payload');
        }
        return StatusNotifierIcon._(kind: kind, path: path);
    }
  }
}

/// One item in a worker state event.
class StatusNotifierSnapshotItem {
  const StatusNotifierSnapshotItem({
    required this.id,
    required this.title,
    required this.status,
    required this.iconName,
    required this.iconThemePath,
    required this.icon,
    required this.menuAvailable,
    required this.primaryOpensMenu,
    required this.menuPath,
  });

  final String id;
  final String title;
  final SystemTrayStatus status;
  final String iconName;
  final String iconThemePath;
  final StatusNotifierIcon icon;
  final bool menuAvailable;
  final bool primaryOpensMenu;
  final String menuPath;

  List<Object?> encode() => <Object?>[
    id,
    title,
    status.index,
    iconName,
    iconThemePath,
    icon.encode(),
    menuAvailable,
    primaryOpensMenu,
    menuPath,
  ];

  static StatusNotifierSnapshotItem decode(Object? value) {
    final fields = _asList(value, 'item', length: 9);
    return StatusNotifierSnapshotItem(
      id: _string(fields[0], 'item id', StatusNotifierProtocolLimits.maxId),
      title: _string(
        fields[1],
        'item title',
        StatusNotifierProtocolLimits.maxTitle,
      ),
      status: _enumValue(fields[2], SystemTrayStatus.values, 'item status'),
      iconName: _string(
        fields[3],
        'item icon name',
        StatusNotifierProtocolLimits.maxIconName,
      ),
      iconThemePath: _string(
        fields[4],
        'item icon theme path',
        StatusNotifierProtocolLimits.maxIconThemePath,
      ),
      icon: StatusNotifierIcon.decode(fields[5]),
      menuAvailable: _boolean(fields[6], 'item menu availability'),
      primaryOpensMenu: _boolean(fields[7], 'item primary menu flag'),
      menuPath: _string(
        fields[8],
        'item menu path',
        StatusNotifierProtocolLimits.maxMenuPath,
      ),
    );
  }

  SystemTrayItem toSystemTrayItem({SystemTrayIconPixmap? iconPixmap}) {
    return SystemTrayItem(
      id: id,
      title: title,
      status: status,
      iconName: iconName,
      iconThemePath: iconThemePath,
      iconPixmap: iconPixmap,
      menuAvailable: menuAvailable,
      primaryOpensMenu: primaryOpensMenu,
      menuPath: menuPath,
    );
  }
}

/// A bounded state event: `['state', items]`.
class StatusNotifierSnapshot {
  const StatusNotifierSnapshot(this.items);

  final List<StatusNotifierSnapshotItem> items;

  List<Object?> toMessage() => <Object?>[
    'state',
    <Object?>[for (final item in items) item.encode()],
  ];

  static List<StatusNotifierSnapshotItem> decodeItems(Object? value) {
    final list = _asList(value, 'snapshot items');
    if (list.length > StatusNotifierProtocolLimits.maxItems) {
      _invalid('snapshot has too many items');
    }
    return List<StatusNotifierSnapshotItem>.unmodifiable(
      list.map(StatusNotifierSnapshotItem.decode),
    );
  }
}

/// A bounded start command payload. Production sends null; tests may point the
/// worker at a fake session bus and shorten recovery timings.
class StatusNotifierStartPayload {
  const StatusNotifierStartPayload({
    this.address,
    this.heartbeatInterval,
    this.recoveryBackoff,
  });

  final String? address;
  final Duration? heartbeatInterval;
  final List<Duration>? recoveryBackoff;

  Map<String, Object?>? toJson() {
    if (address == null &&
        heartbeatInterval == null &&
        recoveryBackoff == null) {
      return null;
    }
    return <String, Object?>{
      if (address != null) 'address': address,
      if (heartbeatInterval != null)
        'heartbeat_ms': heartbeatInterval!.inMilliseconds,
      if (recoveryBackoff != null)
        'recovery_backoff_ms': <int>[
          for (final delay in recoveryBackoff!) delay.inMilliseconds,
        ],
    };
  }

  static StatusNotifierStartPayload decode(Object? value) {
    if (value == null) {
      return const StatusNotifierStartPayload();
    }
    final map = _asMap(value, 'start payload');
    final rawAddress = map['address'];
    final address = rawAddress == null
        ? null
        : _string(
            rawAddress,
            'start address',
            StatusNotifierProtocolLimits.maxString,
          );
    final rawHeartbeat = map['heartbeat_ms'];
    final heartbeat = rawHeartbeat == null
        ? null
        : Duration(
            milliseconds: _integer(
              rawHeartbeat,
              'start heartbeat',
              min: 1,
              max: StatusNotifierProtocolLimits.maxDelayMillis,
            ),
          );
    final rawBackoff = map['recovery_backoff_ms'];
    List<Duration>? backoff;
    if (rawBackoff != null) {
      final values = _asList(rawBackoff, 'start recovery backoff');
      if (values.length > StatusNotifierProtocolLimits.maxBackoffEntries) {
        _invalid('start recovery backoff has too many entries');
      }
      backoff = <Duration>[
        for (final value in values)
          Duration(
            milliseconds: _integer(
              value,
              'start recovery delay',
              min: 1,
              max: StatusNotifierProtocolLimits.maxDelayMillis,
            ),
          ),
      ];
    }
    return StatusNotifierStartPayload(
      address: address,
      heartbeatInterval: heartbeat,
      recoveryBackoff: backoff,
    );
  }
}

class StatusNotifierInvokePayload {
  const StatusNotifierInvokePayload({
    required this.itemId,
    required this.action,
    required this.dx,
    required this.dy,
  });

  final String itemId;
  final SystemTrayAction action;
  final double dx;
  final double dy;

  List<Object?> toMessage() => <Object?>[itemId, action.index, dx, dy];

  static StatusNotifierInvokePayload decode(Object? value) {
    final fields = _asList(value, 'invoke payload', length: 4);
    return StatusNotifierInvokePayload(
      itemId: _string(
        fields[0],
        'invoke item id',
        StatusNotifierProtocolLimits.maxId,
      ),
      action: _enumValue(fields[1], SystemTrayAction.values, 'invoke action'),
      dx: _finiteDouble(fields[2], 'invoke dx'),
      dy: _finiteDouble(fields[3], 'invoke dy'),
    );
  }
}

class StatusNotifierItemIdPayload {
  const StatusNotifierItemIdPayload(this.itemId);

  final String itemId;

  Object toMessage() => itemId;

  static StatusNotifierItemIdPayload decode(Object? value) {
    return StatusNotifierItemIdPayload(
      _string(value, 'item id', StatusNotifierProtocolLimits.maxId),
    );
  }
}

class StatusNotifierActivateMenuPayload {
  const StatusNotifierActivateMenuPayload({
    required this.itemId,
    required this.entryId,
  });

  final String itemId;
  final int entryId;

  List<Object?> toMessage() => <Object?>[itemId, entryId];

  static StatusNotifierActivateMenuPayload decode(Object? value) {
    final fields = _asList(value, 'menu activation payload', length: 2);
    return StatusNotifierActivateMenuPayload(
      itemId: _string(
        fields[0],
        'menu activation item id',
        StatusNotifierProtocolLimits.maxId,
      ),
      entryId: _integer(fields[1], 'menu activation entry id', min: 1),
    );
  }
}

/// One request sent to the worker: `[requestId, operation, payload]`.
class StatusNotifierCommand {
  const StatusNotifierCommand({
    required this.requestId,
    required this.operation,
    this.payload,
  });

  final int requestId;
  final StatusNotifierWorkerOperation operation;
  final Object? payload;

  List<Object?> toMessage() => <Object?>[requestId, operation.index, payload];

  static StatusNotifierCommand decode(Object? value) {
    final fields = _asList(value, 'command', length: 3);
    return StatusNotifierCommand(
      requestId: _integer(fields[0], 'request id'),
      operation: _enumValue(
        fields[1],
        StatusNotifierWorkerOperation.values,
        'command operation',
      ),
      payload: fields[2],
    );
  }
}

/// One command reply: `[requestId, ok, result?, error?, stack?]`.
class StatusNotifierReply {
  const StatusNotifierReply({
    required this.requestId,
    required this.ok,
    this.result,
    this.error,
    this.stack,
  });

  final int requestId;
  final bool ok;
  final Object? result;
  final String? error;
  final String? stack;

  List<Object?> toMessage() => ok
      ? <Object?>[requestId, true, result]
      : <Object?>[requestId, false, error, stack];

  static StatusNotifierReply decode(Object? value) {
    final fields = _asList(value, 'reply');
    if (fields.length < 3 || fields.length > 5) {
      _invalid('reply has the wrong number of fields');
    }
    final requestId = _integer(fields[0], 'reply request id');
    final ok = _boolean(fields[1], 'reply status');
    if (ok) {
      return StatusNotifierReply(
        requestId: requestId,
        ok: true,
        result: fields[2],
      );
    }
    return StatusNotifierReply(
      requestId: requestId,
      ok: false,
      error: _string(
        fields[2],
        'reply error',
        StatusNotifierProtocolLimits.maxString,
      ),
      stack: fields.length > 3
          ? _string(
              fields[3],
              'reply stack',
              StatusNotifierProtocolLimits.maxString,
            )
          : null,
    );
  }
}

/// The start reply's diagnostic result.
class StatusNotifierStartResult {
  const StatusNotifierStartResult({
    required this.isolateName,
    required this.protocolVersion,
  });

  final String isolateName;
  final int protocolVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'isolate': isolateName,
    'protocol': protocolVersion,
  };

  static StatusNotifierStartResult decode(Object? value) {
    final map = _asMap(value, 'start result');
    return StatusNotifierStartResult(
      isolateName: _string(map['isolate'], 'start isolate name', 256),
      protocolVersion: _integer(map['protocol'], 'start protocol version'),
    );
  }
}

class StatusNotifierErrorEvent {
  const StatusNotifierErrorEvent(this.message);

  final String message;

  List<Object?> toMessage() => <Object?>['error', message];

  static String? tryDecodeMessage(Object? value) {
    if (value is! List || value.length < 2 || value.first != 'error') {
      return null;
    }
    final message = value[1];
    return message is String &&
            message.length <= StatusNotifierProtocolLimits.maxString
        ? message
        : null;
  }
}

/// Encodes menu entries with the worker's depth and count bounds.
List<Object?> encodeStatusNotifierMenuEntries(
  List<SystemTrayMenuEntry> entries,
) {
  final budget = _ProtocolMenuBudget(StatusNotifierProtocolLimits.maxMenuItems);
  return _encodeMenuLevel(entries, budget, 0);
}

List<Object?> _encodeMenuLevel(
  List<SystemTrayMenuEntry> entries,
  _ProtocolMenuBudget budget,
  int depth,
) {
  if (depth > StatusNotifierProtocolLimits.maxMenuDepth) {
    _invalid('menu depth exceeds the limit');
  }
  final encoded = <Object?>[];
  for (final entry in entries) {
    if (budget.remaining <= 0) {
      _invalid('menu item count exceeds the limit');
    }
    budget.remaining -= 1;
    if (entry.label.length > StatusNotifierProtocolLimits.maxMenuLabel) {
      _invalid('menu label exceeds the limit');
    }
    encoded.add(<Object?>[
      entry.id,
      entry.label,
      entry.enabled,
      entry.visible,
      entry.separator,
      entry.toggleType.index,
      entry.toggleState,
      entry.destructive,
      _encodeMenuLevel(entry.children, budget, depth + 1),
    ]);
  }
  return encoded;
}

List<SystemTrayMenuEntry> decodeStatusNotifierMenuEntries(Object? value) {
  final list = _asList(value, 'menu entries');
  final budget = _ProtocolMenuBudget(StatusNotifierProtocolLimits.maxMenuItems);
  return List<SystemTrayMenuEntry>.unmodifiable(
    _decodeMenuLevel(list, budget, 0),
  );
}

List<SystemTrayMenuEntry> _decodeMenuLevel(
  List<Object?> value,
  _ProtocolMenuBudget budget,
  int depth,
) {
  if (depth > StatusNotifierProtocolLimits.maxMenuDepth) {
    _invalid('menu depth exceeds the limit');
  }
  final entries = <SystemTrayMenuEntry>[];
  for (final raw in value) {
    if (budget.remaining <= 0) {
      _invalid('menu item count exceeds the limit');
    }
    budget.remaining -= 1;
    final fields = _asList(raw, 'menu entry', length: 9);
    final children = _asList(fields[8], 'menu children');
    if (depth >= StatusNotifierProtocolLimits.maxMenuDepth &&
        children.isNotEmpty) {
      _invalid('menu children exceed the depth limit');
    }
    entries.add(
      SystemTrayMenuEntry(
        id: _integer(fields[0], 'menu id'),
        label: _string(
          fields[1],
          'menu label',
          StatusNotifierProtocolLimits.maxMenuLabel,
        ),
        enabled: _boolean(fields[2], 'menu enabled'),
        visible: _boolean(fields[3], 'menu visible'),
        separator: _boolean(fields[4], 'menu separator'),
        toggleType: _enumValue(
          fields[5],
          SystemTrayMenuToggleType.values,
          'menu toggle type',
        ),
        toggleState: _integer(fields[6], 'menu toggle state'),
        destructive: _boolean(fields[7], 'menu destructive'),
        children: List<SystemTrayMenuEntry>.unmodifiable(
          _decodeMenuLevel(children, budget, depth + 1),
        ),
      ),
    );
  }
  return entries;
}

class _ProtocolMenuBudget {
  _ProtocolMenuBudget(this.remaining);

  int remaining;
}
