import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Watches [directory] and coalesces bursts of changes into one [onChanged].
///
/// A watch stream that errors or closes is replaced with a fresh subscription
/// after a capped backoff, so a compositor-side or filesystem-side watcher
/// failure cannot silently end live reload. [dispose] is terminal.
class ConfigWatcher {
  ConfigWatcher({
    required this.directory,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 200),
    this.retryDelay = const Duration(milliseconds: 500),
    this.retryDelayMax = const Duration(seconds: 5),
    this.include,
    @visibleForTesting Stream<FileSystemEvent> Function(Directory)? watch,
  }) : _watch = watch ?? _watchDirectory,
       _nextRetryDelay = retryDelay;

  final Directory directory;
  final void Function() onChanged;
  final Duration debounce;

  /// Optional event filter. Events that do not pass never start the debounce
  /// or reset the retry backoff; the watch itself still proves liveness.
  final bool Function(FileSystemEvent event)? include;

  /// Delay before the first resubscribe after the watch stream fails; it
  /// doubles after every consecutive failure.
  final Duration retryDelay;

  /// Upper bound for [retryDelay]'s exponential growth.
  final Duration retryDelayMax;

  final Stream<FileSystemEvent> Function(Directory) _watch;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _timer;
  Timer? _restart;
  Duration _nextRetryDelay;
  var _generation = 0;
  var _disposed = false;

  static Stream<FileSystemEvent> _watchDirectory(Directory directory) =>
      directory.watch();

  /// Starts the watch. The directory is created when possible; a creation
  /// failure (a read-only parent, or a file occupying the path) never escapes
  /// here, because the settings window starts this from `initState`. The
  /// failure goes through the same backoff as a failed watch and is retried.
  void start() {
    if (_disposed) {
      return;
    }
    _subscribe();
  }

  /// Whether a live subscription or a pending debounce/restart is owned;
  /// tests assert [dispose] leaves none.
  @visibleForTesting
  bool get hasPendingWork =>
      _subscription != null || _timer != null || _restart != null;

  void _subscribe() {
    if (_disposed || _subscription != null || _restart != null) {
      return;
    }
    _ensureDirectory();
    final generation = _generation;
    final StreamSubscription<FileSystemEvent> subscription;
    try {
      subscription = _watch(directory).listen(
        (event) {
          if (include?.call(event) ?? true) {
            _handleEvent(generation);
          }
        },
        onError: (Object _) => _handleDrop(generation),
        onDone: () => _handleDrop(generation),
        cancelOnError: true,
      );
    } on Object {
      _handleDrop(generation);
      return;
    }
    if (_disposed || generation != _generation) {
      unawaited(subscription.cancel());
      return;
    }
    _subscription = subscription;
  }

  /// Creates [directory] when absent. Failures are not fatal: [_watch] below
  /// reports the same condition and [_handleDrop] schedules the retry, which
  /// attempts creation again.
  void _ensureDirectory() {
    try {
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
    } on Object {
      // Deferred to the watch and retry path.
    }
  }

  void _handleEvent(int generation) {
    if (_disposed || generation != _generation) {
      return;
    }
    // A live watch proves the retry path recovered; the next failure starts
    // the backoff from the base delay again.
    _nextRetryDelay = retryDelay;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      _timer = null;
      onChanged();
    });
  }

  /// Ends the current subscription's line and schedules a fresh watch.
  ///
  /// The generation check makes this exactly once per subscription: an error
  /// followed by a close (or a synchronous failure inside `listen`) cannot
  /// schedule two restarts.
  void _handleDrop(int generation) {
    if (_disposed || generation != _generation) {
      return;
    }
    _generation += 1;
    _subscription = null;
    _restart?.cancel();
    final delay = _nextRetryDelay;
    final next = delay * 2;
    _nextRetryDelay = next > retryDelayMax ? retryDelayMax : next;
    _restart = Timer(delay, () {
      _restart = null;
      _subscribe();
    });
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    _timer?.cancel();
    _timer = null;
    _restart?.cancel();
    _restart = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
