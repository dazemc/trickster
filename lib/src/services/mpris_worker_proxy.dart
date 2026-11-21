import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/mpris_worker.dart';

/// Creates one MPRIS worker. Tests inject a fake command/event channel.
typedef MediaPlayerWorkerSpawner =
    Future<MediaPlayerWorkerConnection> Function();

/// UI-isolate facade over the MPRIS worker isolate.
///
/// The proxy owns no D-Bus objects and never constructs [MediaPlayerService].
/// It spawns the worker only when [start] runs, respawns it after isolate
/// death with capped backoff, forwards states decoded from JSON-compatible
/// snapshots, and kills the worker on dispose without reviving it.
class MediaPlayerWorkerProxy implements MediaPlayerClient {
  MediaPlayerWorkerProxy({
    MediaPlayerWorkerSpawner? spawner,
    this.requestTimeout = const Duration(seconds: 4),
    this.retryDelay = const Duration(seconds: 1),
    this.retryDelayMax = const Duration(seconds: 30),
  }) : _spawner = spawner ?? spawnMediaPlayerWorker,
       _nextRetryDelay = retryDelay;

  final MediaPlayerWorkerSpawner _spawner;
  final Duration requestTimeout;

  /// Delay before the first respawn after an isolate failure.
  final Duration retryDelay;

  /// Upper bound for the exponential respawn delay.
  final Duration retryDelayMax;

  final StreamController<MprisPlaybackState> _snapshots =
      StreamController<MprisPlaybackState>.broadcast(sync: true);
  final Map<int, Completer<void>> _pending = <int, Completer<void>>{};

  MediaPlayerWorkerConnection? _connection;
  SendPort? _commands;
  StreamSubscription<Object?>? _events;
  StreamSubscription<Object?>? _errors;
  StreamSubscription<Object?>? _exits;
  Future<MediaPlayerWorkerConnection>? _spawning;
  MprisPlaybackState _current = MprisPlaybackState.unavailable();
  Future<void>? _disposeFuture;
  Timer? _retryTimer;
  Duration _nextRetryDelay;
  var _nextRequestId = 1;
  var _connectionGeneration = 0;
  var _started = false;
  var _paused = false;
  var _disposed = false;

  @override
  Stream<MprisPlaybackState> get snapshots => _snapshots.stream;

  @override
  MprisPlaybackState get current => _current;

  /// The delay the next isolate failure would use.
  @visibleForTesting
  Duration get nextRetryDelay => _nextRetryDelay;

  @override
  Future<void> start({bool paused = false}) async {
    if (_disposed || _started) {
      return;
    }
    _started = true;
    _paused = paused;
    await _startWorker();
  }

  Future<void> _startWorker() async {
    if (_disposed || !_started) {
      return;
    }
    try {
      await _ensureConnection();
    } on Object {
      // The startup path already published unavailable and scheduled a retry.
      return;
    }
    if (_disposed || !_started || _commands == null) {
      return;
    }
    try {
      await _request(MediaPlayerWorkerOperation.start, <String, Object?>{
        'paused': _paused,
      });
    } on Object {
      // A normal command or D-Bus failure stays inside the worker; it must
      // not trigger a respawn.
      if (!_disposed) {
        _markUnavailable();
      }
    }
  }

  /// One spawn at a time. A retry that races an in-flight startup joins it.
  Future<MediaPlayerWorkerConnection> _ensureConnection() {
    final connection = _connection;
    if (connection != null && _commands != null) {
      return Future<MediaPlayerWorkerConnection>.value(connection);
    }
    final pending = _spawning;
    if (pending != null) {
      return pending;
    }
    late final Future<MediaPlayerWorkerConnection> tracked;
    tracked = _spawnAndAttach().whenComplete(() {
      if (identical(_spawning, tracked)) {
        _spawning = null;
      }
    });
    _spawning = tracked;
    return tracked;
  }

  Future<MediaPlayerWorkerConnection> _spawnAndAttach() async {
    final MediaPlayerWorkerConnection connection;
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
      throw StateError('MPRIS worker start was cancelled');
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
      (_) => _onWorkerFailure(generation, 'MPRIS worker exited'),
    );
    try {
      final commands = await connection.commands.timeout(requestTimeout);
      if (_disposed || !_started || generation != _connectionGeneration) {
        throw StateError('MPRIS worker start was superseded');
      }
      _commands = commands;
      return connection;
    } on Object catch (error) {
      _onWorkerFailure(generation, error);
      rethrow;
    }
  }

  @override
  void pauseRecovery() {
    if (!_started || _disposed) {
      return;
    }
    _paused = true;
    if (_commands == null) {
      return;
    }
    unawaited(
      _request(
        MediaPlayerWorkerOperation.pauseRecovery,
      ).catchError((Object _) {}),
    );
  }

  @override
  Future<void> resumeRecovery() async {
    if (!_started || _disposed) {
      return;
    }
    _paused = false;
    await _control(MediaPlayerWorkerOperation.resumeRecovery);
  }

  @override
  Future<void> playPause() => _control(MediaPlayerWorkerOperation.playPause);

  @override
  Future<void> next() => _control(MediaPlayerWorkerOperation.next);

  @override
  Future<void> previous() => _control(MediaPlayerWorkerOperation.previous);

  Future<void> _control(MediaPlayerWorkerOperation operation) async {
    if (!_started || _disposed || _commands == null) {
      return;
    }
    try {
      await _request(operation);
    } on Object {
      // A worker failure is surfaced as an unavailable state; a control
      // failure must not crash the pill.
    }
  }

  Future<void> _request(
    MediaPlayerWorkerOperation operation, [
    Object? payload,
  ]) async {
    final commands = _commands;
    if (_disposed || commands == null) {
      throw StateError('MPRIS worker is not running');
    }
    final requestId = _nextRequestId++;
    final completer = Completer<void>();
    _pending[requestId] = completer;
    commands.send(<Object?>[requestId, operation.index, payload]);
    try {
      await completer.future.timeout(requestTimeout);
    } finally {
      _pending.remove(requestId);
    }
  }

  void _onEvent(int generation, Object? message) {
    if (_disposed ||
        generation != _connectionGeneration ||
        message is! List<Object?> ||
        message.isEmpty) {
      return;
    }
    final kind = message[0];
    if (kind == 'state') {
      if (message.length < 2 || message[1] is! Map) {
        return;
      }
      try {
        _current = MprisPlaybackState.fromJson(
          Map<String, dynamic>.from(message[1]! as Map),
        );
        // A live snapshot proves the current worker is healthy; the next
        // isolate failure starts again from the base delay.
        _nextRetryDelay = retryDelay;
        _snapshots.add(_current);
      } on Object {
        _markUnavailable();
      }
      return;
    }
    if (kind == 'error') {
      // The worker caught a D-Bus/snapshot failure and stayed alive; never
      // treat this as an isolate death.
      _markUnavailable();
      return;
    }
    if (kind is! int || message.length < 3 || message[1] is! bool) {
      return;
    }
    final completer = _pending[kind];
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (message[1]! as bool) {
      completer.complete();
      return;
    }
    final description = message[2]?.toString() ?? 'unknown worker error';
    final remoteStack = message.length > 3 ? message[3]?.toString() : null;
    completer.completeError(
      StateError(
        'MPRIS worker error: $description'
        '${remoteStack == null ? '' : '\n$remoteStack'}',
      ),
    );
  }

  /// Handles only isolate death or a failed startup, exactly once per
  /// connection. Worker command errors and in-worker D-Bus failures never
  /// reach this path.
  void _onWorkerFailure(int generation, Object failure) {
    if (_disposed || generation != _connectionGeneration) {
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
    _failPending(StateError('MPRIS worker failed: $failure'));
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
    required MediaPlayerWorkerConnection? connection,
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

  void _markUnavailable() {
    _current = MprisPlaybackState.unavailable();
    if (!_disposed && !_snapshots.isClosed) {
      _snapshots.add(_current);
    }
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _started = false;
    _connectionGeneration += 1;
    _retryTimer?.cancel();
    _retryTimer = null;
    _failPending(StateError('MPRIS worker disposed'));
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
    if (!_snapshots.isClosed) {
      await _snapshots.close();
    }
  }
}
