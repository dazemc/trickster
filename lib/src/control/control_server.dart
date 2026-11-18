import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:trickster/src/platform/control_socket.dart';

/// Handles one decoded control request. The returned map is the JSON reply.
typedef ControlHandler =
    FutureOr<Map<String, Object?>> Function(Map<String, Object?> request);

/// The bar's control socket server: one JSON request line per client, one
/// JSON reply line, then the connection closes. Short-lived clients only —
/// `tricksterctl` never runs a second UI.
class ControlServer {
  ControlServer({required this.handler, String? socketPath})
    : socketPath = socketPath ?? controlSocketPath();

  final ControlHandler handler;
  final String socketPath;

  ServerSocket? _server;
  final _clients = <Socket>{};
  var _ownsSocket = false;

  /// Binds the control socket. Returns false when an existing socket already
  /// has a live owner; a second bar must not steal or later unlink the first
  /// bar's control channel. A stale file from a crashed owner is replaced.
  Future<bool> start() async {
    if (_server != null) {
      return true;
    }
    final file = File(socketPath);
    if (file.existsSync()) {
      try {
        final probe = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
        ).timeout(const Duration(milliseconds: 200));
        probe.destroy();
        return false;
      } on Object {
        // No live owner answered: this is a stale socket file, safe to remove.
        if (file.existsSync()) {
          file.deleteSync();
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
    server.listen(_onConnection, onError: (_) {});
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

  Future<void> dispose() async {
    for (final client in _clients.toList()) {
      await client.close();
    }
    _clients.clear();
    final server = _server;
    _server = null;
    await server?.close();
    if (!_ownsSocket) {
      return;
    }
    _ownsSocket = false;
    final file = File(socketPath);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } on FileSystemException {
        // Another process already cleaned it up.
      }
    }
  }
}
