import 'dart:async';
import 'dart:isolate';

import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/mpris_worker.dart';

/// Creates one MPRIS worker. Tests inject a fake command/event channel.
typedef MediaPlayerWorkerSpawner =
    Future<MediaPlayerWorkerConnection> Function();

/// UI-isolate facade over the MPRIS worker isolate.
///
/// The proxy owns no D-Bus objects and never constructs [MediaPlayerService].
/// It spawns the worker only when [start] runs, forwards states decoded from
/// JSON-compatible snapshots, and kills the worker on dispose.
class MediaPlayerWorkerProxy implements MediaPlayerClient {
  MediaPlayerWorkerProxy({
    MediaPlayerWorkerSpawner? spawner,
    this.requestTimeout = const Duration(seconds: 4),
  }) : _spawner = spawner ?? spawnMediaPlayerWorker;

  final MediaPlayerWorkerSpawner _spawner;
  final Duration requestTimeout;

  final StreamController<MprisPlaybackState> _snapshots =
      StreamController<MprisPlaybackState>.broadcast(sync: true);
  final Map<int, Completer<void>> _pending = <int, Completer<void>>{};

  MediaPlayerWorkerConnection? _connection;
  SendPort? _commands;
  StreamSubscription<Object?>? _events;
  StreamSubscription<Object?>? _errors;
  StreamSubscription<Object?>? _exits;
  MprisPlaybackState _current = MprisPlaybackState.unavailable();
  Future<void>? _disposeFuture;
  var _nextRequestId = 1;
  var _started = false;
  var _failed = false;
  var _disposed = false;

  @override
  Stream<MprisPlaybackState> get snapshots => _snapshots.stream;

  @override
  MprisPlaybackState get current => _current;

  @override
  Future<void> start({bool paused = false}) async {
    if (_disposed || _started) {
      return;
    }
    _started = true;
    try {
      await _ensureStarted();
      if (_disposed || _failed) {
        return;
      }
      await _request(MediaPlayerWorkerOperation.start, <String, Object?>{
        'paused': paused,
      });
    } on Object {
      if (!_disposed) {
        _markUnavailable();
      }
    }
  }

  Future<void> _ensureStarted() async {
    if (_commands != null) {
      return;
    }
    final connection = await _spawner();
    if (_disposed) {
      connection.kill();
      connection.close();
      return;
    }
    _connection = connection;
    _events = connection.events.listen(
      _onEvent,
      onError: (Object? error) => _onWorkerFailure('$error'),
    );
    _errors = connection.errors.listen(
      (Object? error) => _onWorkerFailure('$error'),
    );
    _exits = connection.exits.listen(
      (_) => _onWorkerFailure('MPRIS worker exited'),
    );
    try {
      final commands = await connection.commands.timeout(requestTimeout);
      if (_disposed) {
        return;
      }
      _commands = commands;
    } on Object {
      _onWorkerFailure('MPRIS worker did not publish a command port');
      rethrow;
    }
  }

  @override
  void pauseRecovery() {
    if (!_started || _disposed || _failed) {
      return;
    }
    unawaited(
      _request(
        MediaPlayerWorkerOperation.pauseRecovery,
      ).catchError((Object _) {}),
    );
  }

  @override
  Future<void> resumeRecovery() =>
      _control(MediaPlayerWorkerOperation.resumeRecovery);

  @override
  Future<void> playPause() => _control(MediaPlayerWorkerOperation.playPause);

  @override
  Future<void> next() => _control(MediaPlayerWorkerOperation.next);

  @override
  Future<void> previous() => _control(MediaPlayerWorkerOperation.previous);

  Future<void> _control(MediaPlayerWorkerOperation operation) async {
    if (!_started || _disposed || _failed) {
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
    if (_disposed || _failed || commands == null) {
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

  void _onEvent(Object? message) {
    if (_disposed || message is! List<Object?> || message.isEmpty) {
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
        _snapshots.add(_current);
      } on Object {
        _markUnavailable();
      }
      return;
    }
    if (kind == 'error') {
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

  void _onWorkerFailure(Object failure) {
    if (_disposed) {
      return;
    }
    _failed = true;
    _commands = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('MPRIS worker failed: $failure'));
      }
    }
    _pending.clear();
    _markUnavailable();
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
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('MPRIS worker disposed'));
      }
    }
    _pending.clear();
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
