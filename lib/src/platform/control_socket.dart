import 'dart:convert';
import 'dart:io';

/// The bar's control socket location: `$XDG_RUNTIME_DIR/trickster/control.sock`.
String controlSocketPath({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final runtimeDir = env['XDG_RUNTIME_DIR'];
  return '${runtimeDir == null || runtimeDir.isEmpty ? '/tmp' : runtimeDir}'
      '/trickster/control.sock';
}

/// A control request failed: the socket is missing, refused the connection,
/// timed out, or answered something malformed. Callers treat this as
/// "the bar is not reachable", never as a crash.
class ControlSocketException implements Exception {
  const ControlSocketException(this.message);

  final String message;

  @override
  String toString() => 'ControlSocketException: $message';
}

/// Sends one JSON request line to the bar's control socket and returns the
/// one JSON reply line. Shared by the settings transport and `tricksterctl`.
Future<Map<String, Object?>> controlRequest(
  Map<String, Object?> request, {
  String? socketPath,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final path = socketPath ?? controlSocketPath();
  Socket socket;
  try {
    socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    ).timeout(timeout);
  } on Object catch (error) {
    throw ControlSocketException('$path unavailable: $error');
  }
  try {
    socket.write('${jsonEncode(request)}\n');
    final line = await utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .first
        .timeout(timeout);
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw ControlSocketException('$path replied with a non-object');
    }
    return decoded.cast<String, Object?>();
  } on ControlSocketException {
    rethrow;
  } on Object catch (error) {
    throw ControlSocketException('$path request failed: $error');
  } finally {
    await socket.close();
  }
}
