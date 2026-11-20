import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:trickster/src/platform/control_socket.dart';

/// Handles one decoded control request. The returned map is the JSON reply.
typedef ControlHandler =
    FutureOr<Map<String, Object?>> Function(Map<String, Object?> request);

/// Opens the accept stream for a bound [ServerSocket]. Tests replace this to
/// surface a listener error without waiting for a real socket failure.
typedef ControlAcceptListener =
    StreamSubscription<Socket> Function(
      ServerSocket server,
      void Function(Socket socket) onSocket,
      void Function(Object error, StackTrace stackTrace) onError,
      void Function() onDone,
    );

/// The bar's control socket server: one JSON request line per client, one
/// JSON reply line, then the connection closes. Short-lived clients only —
/// `tricksterctl` never runs a second UI.
class ControlServer {
  ControlServer({
    required this.handler,
    String? socketPath,
    this.retryDelay = const Duration(milliseconds: 500),
    this.retryDelayMax = const Duration(seconds: 30),
    @visibleForTesting ControlAcceptListener? acceptListener,
  }) : socketPath = socketPath ?? controlSocketPath(),
       _acceptListener = acceptListener ?? _listen;

  final ControlHandler handler;
  final String socketPath;

  /// Delay before the first rebind after the accept stream fails.
  final Duration retryDelay;

  /// Upper bound for the exponential rebind delay.
  final Duration retryDelayMax;

  final ControlAcceptListener _acceptListener;

  ServerSocket? _server;
  StreamSubscription<Socket>? _acceptSubscription;
  final _clients = <Socket>{};
  var _ownsSocket = false;
  var _stopping = false;
  var _generation = 0;
  Timer? _retryTimer;
  Duration? _nextRetryDelay;
  Future<bool>? _binding;
  Future<void>? _disposeFuture;

  static StreamSubscription<Socket> _listen(
    ServerSocket server,
    void Function(Socket socket) onSocket,
    void Function(Object error, StackTrace stackTrace) onError,
    void Function() onDone,
  ) => server.listen(onSocket, onError: onError, onDone: onDone);

  /// Whether a rebind is waiting on the retry timer.
  @visibleForTesting
  bool get hasPendingRetry => _retryTimer != null;

  /// Binds the control socket. Returns false when an existing socket already
  /// has a live owner; a second bar must not steal or later unlink the first
  /// bar's control channel. A stale file from a crashed owner is replaced.
  ///
  /// A failed accept stream is rebound after an exponential backoff, unless a
  /// live owner answers the path probe. Dispose cancels every pending retry.
  Future<bool> start() {
    if (_stopping) {
      return Future<bool>.value(false);
    }
    if (_server != null) {
      return Future<bool>.value(true);
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    return _bindSingleFlight();
  }

  /// Shares one bind between a concurrent [start] and a retry.
  Future<bool> _bindSingleFlight() {
    final pending = _binding;
    if (pending != null) {
      return pending;
    }
    late final Future<bool> tracked;
    tracked = _bind().whenComplete(() {
      if (identical(_binding, tracked)) {
        _binding = null;
      }
    });
    _binding = tracked;
    return tracked;
  }

  Future<bool> _bind() async {
    if (_stopping) {
      return false;
    }
    final file = File(socketPath);
    if (file.existsSync()) {
      try {
        final probe = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        ).timeout(const Duration(milliseconds: 200));
        probe.destroy();
        _ownsSocket = false;
        return false;
      } on Object {
        // No live owner answered: this is a stale socket file, safe to remove.
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } on FileSystemException {
            // Another process already cleaned it up.
          }
        }
      }
    }
    Directory(file.parent.path).createSync(recursive: true);
    final server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    _server = server;
    _ownsSocket = true;
    if (_stopping) {
      // Dispose waited for this bind. It takes the path after the close; never
      // leave the freshly bound socket installed or open.
      _server = null;
      await server.close();
      return false;
    }
    final generation = ++_generation;
    final StreamSubscription<Socket> subscription;
    try {
      subscription = _acceptListener(
        server,
        _onConnection,
        (error, stackTrace) => unawaited(_handleListenerDrop(generation)),
        () => unawaited(_handleListenerDrop(generation)),
      );
    } on Object {
      _server = null;
      _ownsSocket = false;
      await server.close();
      rethrow;
    }
    _acceptSubscription = subscription;
    if (_stopping) {
      _acceptSubscription = null;
      await subscription.cancel();
      _server = null;
      await server.close();
      return false;
    }
    _nextRetryDelay = null;
    return true;
  }

  void _onConnection(Socket socket) {
    _clients.add(socket);
    unawaited(socket.done.whenComplete(() => _clients.remove(socket)));
    utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(
          (line) async {
            Map<String, Object?> reply;
            try {
              final decoded = jsonDecode(line);
              if (decoded is! Map) {
                throw const FormatException('request must be an object');
              }
              reply = await handler(decoded.cast<String, Object?>());
            } on Object catch (error) {
              reply = <String, Object?>{'ok': false, 'error': '$error'};
            }
            socket.write('${jsonEncode(reply)}\n');
            await socket.flush();
            await socket.close();
          },
          onError: (_) {},
          onDone: () {},
        );
  }

  /// Ends the failed accept stream once, then schedules a fresh bind.
  ///
  /// The generation check makes this exactly once per subscription: an error
  /// followed by a close cannot schedule two retries.
  Future<void> _handleListenerDrop(int generation) async {
    if (_stopping || generation != _generation) {
      return;
    }
    _generation += 1;
    await _releaseServer();
    if (_stopping) {
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_stopping || _retryTimer != null) {
      return;
    }
    final delay = _nextRetryDelay ?? retryDelay;
    final doubled = delay * 2;
    _nextRetryDelay = doubled > retryDelayMax ? retryDelayMax : doubled;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_retry());
    });
  }

  Future<void> _retry() async {
    if (_stopping) {
      return;
    }
    bool bound;
    try {
      bound = await _bindSingleFlight();
    } on Object {
      if (_stopping) {
        return;
      }
      _scheduleRetry();
      return;
    }
    if (_stopping || bound) {
      return;
    }
    // A live owner answered the path probe: never steal it, and stop probing.
    _nextRetryDelay = null;
  }

  Future<void> _releaseServer() async {
    final subscription = _acceptSubscription;
    _acceptSubscription = null;
    final server = _server;
    _server = null;
    final owned = _ownsSocket;
    _ownsSocket = false;
    await subscription?.cancel();
    await server?.close();
    // A concurrent start may have claimed the path while this release was
    // closing the old server; never unlink its fresh socket.
    if (!owned || _ownsSocket) {
      return;
    }
    final file = File(socketPath);
    if (!file.existsSync()) {
      return;
    }
    try {
      file.deleteSync();
    } on FileSystemException {
      // Another process already cleaned it up.
    }
  }

  /// Ends the listener and every client. Pending retries are cancelled and an
  /// owned socket path is removed; a live foreign owner is never unlinked.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _stopping = true;
    _generation += 1;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _releaseServer();

    // A bind may have been in flight; close whatever it installed after the
    // first release.
    final binding = _binding;
    if (binding != null) {
      try {
        await binding;
      } on Object {
        // The bind failed; there is nothing to close.
      }
      await _releaseServer();
    }

    for (final client in _clients.toList()) {
      await client.close();
    }
    _clients.clear();
  }
}
