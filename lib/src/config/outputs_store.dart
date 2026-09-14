import 'dart:io';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/control_socket.dart';

/// Reads and writes the `outputs.conf` document. Unlike settings.json there
/// is no revision: the bar owns the file while it runs, and the app writes
/// through it.
abstract interface class OutputsDocumentTransport {
  Future<String> read();

  Future<String> write(String document);
}

class FileOutputsTransport implements OutputsDocumentTransport {
  FileOutputsTransport(this.file);

  final File file;

  @override
  Future<String> read() async {
    if (!file.existsSync()) {
      return const OutputsConfig().encode();
    }
    return file.readAsStringSync();
  }

  @override
  Future<String> write(String document) async {
    // Validation happens before anything touches the disk.
    final config = OutputsConfig.parse(document);
    final encoded = config.encode();
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encoded);
    return encoded;
  }
}

/// Talks to the bar's control socket instead of the file.
class SocketOutputsTransport implements OutputsDocumentTransport {
  SocketOutputsTransport({String? socketPath}) : _socketPath = socketPath;

  final String? _socketPath;

  @override
  Future<String> read() async {
    final reply = await controlRequest(const <String, Object?>{
      'command': 'outputs.read',
    }, socketPath: _socketPath);
    return _document(reply);
  }

  @override
  Future<String> write(String document) async {
    final reply = await controlRequest(<String, Object?>{
      'command': 'outputs.write',
      'document': document,
    }, socketPath: _socketPath);
    return _document(reply);
  }

  String _document(Map<String, Object?> reply) {
    if (reply['ok'] != true) {
      throw ControlSocketException(
        '${reply['error'] ?? 'outputs request failed'}',
      );
    }
    final document = reply['document'];
    if (document is! String) {
      throw const ControlSocketException(
        'control socket sent a malformed outputs document',
      );
    }
    return document;
  }
}
