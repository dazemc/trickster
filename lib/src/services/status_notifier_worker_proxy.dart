import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;

import 'package:trickster/src/services/status_notifier_client.dart';
import 'package:trickster/src/services/status_notifier_models.dart';
import 'package:trickster/src/services/status_notifier_protocol.dart';
import 'package:trickster/src/services/status_notifier_worker.dart';
import 'package:trickster/src/services/tray_icon_decoder.dart';

/// Creates one StatusNotifier worker. Tests inject a fake command/event
/// channel.
typedef StatusNotifierWorkerSpawner =
    Future<StatusNotifierWorkerConnection> Function();

/// UI-isolate facade over the StatusNotifier worker isolate.
///
/// The proxy owns no D-Bus objects and never constructs
/// `StatusNotifierService`. It spawns the worker only when [start] runs,
/// decodes icon-file paths on the UI isolate, respawns after isolate death
/// with capped backoff, and kills the worker on dispose without reviving it.
class StatusNotifierWorkerProxy implements StatusNotifierClient {
  StatusNotifierWorkerProxy({
    StatusNotifierWorkerSpawner? spawner,
    this.startPayload,
    TrayIconDecoder? iconDecoder,
    this.requestTimeout = const Duration(seconds: 10),
    this.startupTimeout = const Duration(seconds: 10),
    this.disposeTimeout = const Duration(seconds: 2),
    this.retryDelay = const Duration(seconds: 1),
    this.retryDelayMax = const Duration(seconds: 30),
  }) : _spawner = spawner ?? spawnStatusNotifierWorker,
       _iconDecoder = iconDecoder ?? TrayIconDecoder(),
       _ownsDecoder = iconDecoder == null,
       _nextRetryDelay = retryDelay;

  final StatusNotifierWorkerSpawner _spawner;
  final StatusNotifierStartPayload? startPayload;
  final Duration requestTimeout;
  final Duration startupTimeout;
  final Duration disposeTimeout;
  final Duration retryDelay;
  final Duration retryDelayMax;
  final TrayIconDecoder _iconDecoder;
  final bool _ownsDecoder;

  final StreamController<List<SystemTrayItem>> _snapshots =
      StreamController<List<SystemTrayItem>>.broadcast(sync: true);
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<String, _IconSlot> _iconSlots = <String, _IconSlot>{};

  StatusNotifierWorkerConnection? _connection;
  SendPort? _commands;
  StreamSubscription<Object?>? _events;
  StreamSubscription<Object?>? _errors;
  StreamSubscription<Object?>? _exits;
  Future<StatusNotifierWorkerConnection>? _spawning;
  Future<void>? _disposeFuture;
  Timer? _retryTimer;
  List<SystemTrayItem> _current = const <SystemTrayItem>[];
  Duration _nextRetryDelay;
  int _nextRequestId = 1;
  int _connectionGeneration = 0;
  bool _started = false;
  bool _disposed = false;
  bool _tearingDown = false;
  String? _workerIsolateName;

  @override
  Stream<List<SystemTrayItem>> get snapshots => _snapshots.stream;

  @override
  List<SystemTrayItem> get current => _current;

  /// The isolate name reported by the worker's start reply, for the real
  /// worker integration test.
  @visibleForTesting
  String? get workerIsolateName => _workerIsolateName;

  @visibleForTesting
  Duration get nextRetryDelay => _nextRetryDelay;

  @override
  Future<void> start() async {
    if (_disposed || _started) {
      return;
    }
    _started = true;
    _nextRetryDelay = retryDelay;
    await _startWorker();
  }

  Future<void> _startWorker() async {
    if (_disposed || _tearingDown || !_started) {
      return;
    }
    try {
      await _ensureConnection();
    } on Object {
      // The startup path already published unavailable and scheduled a retry.
      return;
    }
    if (_disposed || _tearingDown || !_started || _commands == null) {
      return;
    }
    try {
      final result = await _request(
        StatusNotifierWorkerOperation.start,
        startPayload?.toJson(),
      );
      _nextRetryDelay = retryDelay;
      if (result != null) {
        _workerIsolateName = StatusNotifierStartResult.decode(
          result,
        ).isolateName;
      }
    } on Object {
      // A normal start failure stays inside the worker; it must not trigger a
      // respawn. The service keeps recovering on its own.
    }
  }

  /// One spawn at a time. A retry that races an in-flight startup joins it.
  Future<StatusNotifierWorkerConnection> _ensureConnection() {
    final connection = _connection;
    if (connection != null && _commands != null) {
      return Future<StatusNotifierWorkerConnection>.value(connection);
    }
    final pending = _spawning;
    if (pending != null) {
      return pending;
    }
    late final Future<StatusNotifierWorkerConnection> tracked;
    tracked = _spawnAndAttach().whenComplete(() {
      if (identical(_spawning, tracked)) {
        _spawning = null;
      }
    });
    _spawning = tracked;
    return tracked;
  }

  Future<StatusNotifierWorkerConnection> _spawnAndAttach() async {
    final StatusNotifierWorkerConnection connection;
    try {
      connection = await _spawner();
    } on Object {
      if (!_disposed && _started) {
        _markUnavailable();
        _scheduleRetry();
      }
      rethrow;
    }
    if (_disposed || !_started) {
      connection.kill();
      connection.close();
      throw StateError('StatusNotifier worker start was cancelled');
    }
    final generation = ++_connectionGeneration;
    _connection = connection;
    _events = connection.events.listen(
      (message) => _onEvent(generation, message),
      onError: (Object? error) => _onWorkerFailure(generation, '$error'),
    );
    _errors = connection.errors.listen(
      (Object? error) => _onWorkerFailure(generation, '$error'),
    );
    _exits = connection.exits.listen(
      (_) => _onWorkerFailure(generation, 'StatusNotifier worker exited'),
    );
    try {
      final commands = await connection.commands.timeout(startupTimeout);
      if (_disposed || !_started || generation != _connectionGeneration) {
        throw StateError('StatusNotifier worker start was superseded');
      }
      _commands = commands;
      return connection;
    } on Object catch (error) {
      _onWorkerFailure(generation, error);
      rethrow;
    }
  }

  @override
  Future<bool> invoke(
    SystemTrayItem item,
    SystemTrayAction action,
    Offset position,
  ) async {
    if (!_canCommand) {
      return false;
    }
    try {
      final result = await _request(
        StatusNotifierWorkerOperation.invoke,
        StatusNotifierInvokePayload(
          itemId: item.id,
          action: action,
          dx: position.dx,
          dy: position.dy,
        ).toMessage(),
      );
      return result == true;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<SystemTrayMenuEntry>?> loadMenu(SystemTrayItem item) async {
    if (!_canCommand) {
      return null;
    }
    try {
      final result = await _request(
        StatusNotifierWorkerOperation.loadMenu,
        StatusNotifierItemIdPayload(item.id).toMessage(),
      );
      if (result == null) {
        return null;
      }
      return decodeStatusNotifierMenuEntries(result);
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> activateMenuEntry(SystemTrayItem item, int entryId) async {
    if (!_canCommand) {
      return false;
    }
    try {
      final result = await _request(
        StatusNotifierWorkerOperation.activateMenuEntry,
        StatusNotifierActivateMenuPayload(
          itemId: item.id,
          entryId: entryId,
        ).toMessage(),
      );
      return result == true;
    } on Object {
      return false;
    }
  }

  bool get _canCommand =>
      _started && !_disposed && !_tearingDown && _commands != null;

  Future<Object?> _request(
    StatusNotifierWorkerOperation operation, [
    Object? payload,
  ]) async {
    final commands = _commands;
    if (_disposed || commands == null) {
      throw StateError('StatusNotifier worker is not running');
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    commands.send(
      StatusNotifierCommand(
        requestId: requestId,
        operation: operation,
        payload: payload,
      ).toMessage(),
    );
    try {
      return await completer.future.timeout(requestTimeout);
    } finally {
      _pending.remove(requestId);
    }
  }

  void _onEvent(int generation, Object? message) {
    if (_disposed || generation != _connectionGeneration) {
      return;
    }
    if (message is! List || message.isEmpty) {
      return;
    }
    final kind = message.first;
    if (kind == 'state') {
      if (_tearingDown || message.length < 2) {
        return;
      }
      try {
        final items = StatusNotifierSnapshot.decodeItems(message[1]);
        _nextRetryDelay = retryDelay;
        _applySnapshot(items);
      } on Object {
        // A malformed or oversized snapshot is ignored; the next state wins.
      }
      return;
    }
    if (kind == 'error') {
      if (_tearingDown) {
        return;
      }
      // The worker caught a D-Bus/snapshot failure and stayed alive.
      StatusNotifierErrorEvent.tryDecodeMessage(message);
      return;
    }
    if (kind is! int) {
      return;
    }
    final StatusNotifierReply reply;
    try {
      reply = StatusNotifierReply.decode(message);
    } on Object {
      return;
    }
    final completer = _pending[reply.requestId];
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (reply.ok) {
      completer.complete(reply.result);
      return;
    }
    completer.completeError(
      StateError(
        'StatusNotifier worker error: ${reply.error ?? 'unknown error'}'
        '${reply.stack == null ? '' : '\n${reply.stack}'}',
      ),
    );
  }

  void _applySnapshot(List<StatusNotifierSnapshotItem> items) {
    final ids = <String>{};
    final next = <SystemTrayItem>[];
    for (final item in items) {
      ids.add(item.id);
      final slot = _iconSlots.putIfAbsent(item.id, _IconSlot.new);
      _applyIcon(item.id, slot, item.icon);
      next.add(item.toSystemTrayItem(iconPixmap: slot.pixmap));
    }
    final removed = _iconSlots.keys
        .where((id) => !ids.contains(id))
        .toList(growable: false);
    for (final id in removed) {
      final slot = _iconSlots.remove(id);
      if (slot != null) {
        slot.generation += 1;
      }
    }
    _publish(next);
  }

  void _applyIcon(String itemId, _IconSlot slot, StatusNotifierIcon icon) {
    switch (icon.kind) {
      case StatusNotifierIconKind.none:
        if (slot.signature.isNotEmpty) {
          slot.signature = '';
          slot.path = null;
          slot.pixmap = null;
          slot.generation += 1;
        }
        return;
      case StatusNotifierIconKind.unchanged:
        return;
      case StatusNotifierIconKind.rgba:
        final signature = 'rgba:${icon.digest}:${icon.width}x${icon.height}';
        if (slot.signature == signature && slot.pixmap != null) {
          return;
        }
        slot.signature = signature;
        slot.path = null;
        slot.pixmap = SystemTrayIconPixmap(
          width: icon.width,
          height: icon.height,
          rgba: icon.rgba!,
        );
        slot.generation += 1;
        return;
      case StatusNotifierIconKind.file:
        final signature = 'file:${icon.path}';
        if (slot.signature == signature &&
            (slot.pixmap != null || slot.path == icon.path)) {
          return;
        }
        slot.signature = signature;
        slot.path = icon.path;
        slot.pixmap = null;
        final generation = ++slot.generation;
        _decodeIcon(itemId, icon.path, generation);
    }
  }

  void _decodeIcon(String itemId, String path, int generation) {
    unawaited(
      _iconDecoder.decode(path).then<void>((pixmap) {
        if (_disposed || _tearingDown) {
          return;
        }
        final slot = _iconSlots[itemId];
        if (slot == null ||
            slot.generation != generation ||
            slot.path != path) {
          return;
        }
        slot.pixmap = pixmap;
        final index = _current.indexWhere((item) => item.id == itemId);
        if (index < 0) {
          return;
        }
        final next = List<SystemTrayItem>.of(_current);
        next[index] = _withPixmap(next[index], pixmap);
        _publish(next);
      }, onError: (Object error, StackTrace stackTrace) {}),
    );
  }

  SystemTrayItem _withPixmap(
    SystemTrayItem item,
    SystemTrayIconPixmap? pixmap,
  ) {
    return SystemTrayItem(
      id: item.id,
      title: item.title,
      status: item.status,
      iconName: item.iconName,
      iconThemePath: item.iconThemePath,
      iconPixmap: pixmap,
      menuAvailable: item.menuAvailable,
      primaryOpensMenu: item.primaryOpensMenu,
      menuPath: item.menuPath,
    );
  }

  void _publish(List<SystemTrayItem> items) {
    if (_disposed || _snapshots.isClosed) {
      return;
    }
    final next = List<SystemTrayItem>.unmodifiable(items);
    if (listEquals(_current, next)) {
      return;
    }
    _current = next;
    _snapshots.add(next);
  }

  void _markUnavailable() {
    _iconSlots.clear();
    _publish(const <SystemTrayItem>[]);
  }

  /// Handles only isolate death or a failed startup, exactly once per
  /// connection. Worker command errors and in-worker D-Bus failures never
  /// reach this path.
  void _onWorkerFailure(int generation, Object failure) {
    if (_disposed || _tearingDown || generation != _connectionGeneration) {
      return;
    }
    _connectionGeneration += 1;
    final connection = _connection;
    _connection = null;
    _commands = null;
    final events = _events;
    _events = null;
    final errors = _errors;
    _errors = null;
    final exits = _exits;
    _exits = null;
    _failPending(StateError('StatusNotifier worker failed: $failure'));
    unawaited(
      _retireConnection(
        connection: connection,
        events: events,
        errors: errors,
        exits: exits,
      ),
    );
  }

  Future<void> _retireConnection({
    required StatusNotifierWorkerConnection? connection,
    required StreamSubscription<Object?>? events,
    required StreamSubscription<Object?>? errors,
    required StreamSubscription<Object?>? exits,
  }) async {
    await events?.cancel();
    await errors?.cancel();
    await exits?.cancel();
    connection?.kill();
    connection?.close();
    if (_disposed) {
      return;
    }
    _markUnavailable();
    if (!_started) {
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || !_started || _retryTimer != null) {
      return;
    }
    final delay = _nextRetryDelay;
    final doubled = delay * 2;
    _nextRetryDelay = doubled > retryDelayMax ? retryDelayMax : doubled;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_disposed || !_started) {
        return;
      }
      unawaited(_startWorker());
    });
  }

  void _failPending(Object failure) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(failure);
      }
    }
    _pending.clear();
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _tearingDown = true;
    _started = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _failPending(StateError('StatusNotifier worker disposed'));
    final commands = _commands;
    if (commands != null) {
      final requestId = _nextRequestId++;
      final completer = Completer<Object?>();
      _pending[requestId] = completer;
      commands.send(
        StatusNotifierCommand(
          requestId: requestId,
          operation: StatusNotifierWorkerOperation.dispose,
        ).toMessage(),
      );
      try {
        await completer.future.timeout(disposeTimeout);
      } on Object {
        // The worker may already be gone; teardown still owns the ports.
      }
      _pending.remove(requestId);
    }

    _disposed = true;
    _tearingDown = false;
    _connectionGeneration += 1;
    _commands = null;
    final connection = _connection;
    _connection = null;
    await _events?.cancel();
    _events = null;
    await _errors?.cancel();
    _errors = null;
    await _exits?.cancel();
    _exits = null;
    connection?.kill();
    connection?.close();
    _iconSlots.clear();
    _current = const <SystemTrayItem>[];
    if (_ownsDecoder) {
      _iconDecoder.dispose();
    }
    if (!_snapshots.isClosed) {
      await _snapshots.close();
    }
  }
}

class _IconSlot {
  String signature = '';
  String? path;
  SystemTrayIconPixmap? pixmap;
  int generation = 0;
}
