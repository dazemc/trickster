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

  Future<void> start() async {
    if (_server != null) {
      return;
    }
    final file = File(socketPath);
    if (file.existsSync()) {
      // A stale socket from a crashed bar would refuse the bind.
      file.deleteSync();
    }
    Directory(file.parent.path).createSync(recursive: true);
    final server = await ServerSocket.bind(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
    );
    _server = server;
    server.listen(_onConnection, onError: (_) {});
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
