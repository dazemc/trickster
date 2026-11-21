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

/// The bar answered and rejected the request (permission, full disk, bad
/// document). This is not transport loss: the live socket is still usable, so
/// [FallbackOutputsTransport] surfaces the error instead of flipping to file.
class OutputsRequestException implements Exception {
  const OutputsRequestException(this.message);

  final String message;

  @override
  String toString() => 'OutputsRequestException: $message';
}

class FileOutputsTransport implements OutputsDocumentTransport {
  FileOutputsTransport(this.file);

  final File file;

  static int _temporaryCounter = 0;

  File get _previous => File('${file.path}.prev');

  /// Validates a document before it can be considered readable. An empty or
  /// header-only file parses to defaults, but it is not a usable outputs
  /// document: treating it as valid would hide a torn write.
  static bool _isValidDocument(String document) {
    if (!RegExp(
      r'^[ \t]*system_bar[ \t]*=',
      multiLine: true,
    ).hasMatch(document)) {
      return false;
    }
    return _isParseableDocument(document);
  }

  /// A document that the grammar can parse, even if it has no `system_bar=`
  /// line yet. A user-edited file with comments and unrelated keys is a
  /// perfectly good base for inserting that line; an empty or malformed file
  /// is not.
  static bool _isParseableDocument(String document) {
    if (document.trim().isEmpty) {
      return false;
    }
    try {
      OutputsConfig.parse(document);
      return true;
    } on FormatException {
      return false;
    }
  }

  static File _temporaryFor(File target) {
    final unique =
        '$pid.${DateTime.now().microsecondsSinceEpoch}.'
        '${_temporaryCounter++}';
    return File('${target.path}.tmp.$unique');
  }

  /// Replaces [target] atomically: the bytes are flushed into a unique temp
  /// file in the same directory, then renamed over the target. A crash or a
  /// full disk before the rename leaves the previous document whole.
  static void _writeAtomically(File target, String document) {
    final temporary = _temporaryFor(target);
    try {
      temporary.writeAsStringSync(document, flush: true);
      temporary.renameSync(target.path);
    } on Object {
      if (temporary.existsSync()) {
        try {
          temporary.deleteSync();
        } on Object {
          // Best effort: the temp file is never a source of truth.
        }
      }
      rethrow;
    }
  }

  /// Copies the current live document to `.prev`, but only while it is
  /// valid. When the live file was torn and read recovered from `.prev`,
  /// overwriting the snapshot with the torn bytes would destroy the last
  /// good document.
  void _snapshotPrevious() {
    if (!file.existsSync()) {
      return;
    }
    final String previous;
    try {
      previous = file.readAsStringSync();
    } on Object {
      return;
    }
    if (!_isValidDocument(previous)) {
      return;
    }
    _writeAtomically(_previous, previous);
  }

  /// Returns the first valid document from the live file or its `.prev`
  /// snapshot, or null when neither exists.
  String? _readValidDocument() {
    for (final candidate in <File>[file, _previous]) {
      if (!candidate.existsSync()) {
        continue;
      }
      final String document;
      try {
        document = candidate.readAsStringSync();
      } on Object {
        continue;
      }
      if (_isValidDocument(document)) {
        return document;
      }
    }
    return null;
  }

  /// The document a write should merge into. A live file with comments and
  /// unrelated keys but no `system_bar=` line is still preserved; the write
  /// inserts the line instead of replacing the file.
  String? _readMergeSource() {
    for (final candidate in <File>[file, _previous]) {
      if (!candidate.existsSync()) {
        continue;
      }
      final String document;
      try {
        document = candidate.readAsStringSync();
      } on Object {
        continue;
      }
      if (_isParseableDocument(document)) {
        return document;
      }
    }
    return null;
  }

  static bool _isSystemBarLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      return false;
    }
    final separator = trimmed.indexOf('=');
    if (separator <= 0) {
      return false;
    }
    return trimmed.substring(0, separator).trim() == 'system_bar';
  }

  /// Replaces the existing `system_bar=` line (or inserts one) while keeping
  /// every comment and unrelated key byte-for-byte. `outputs.conf` is a
  /// user-edited Denial-style file, so a settings save must not canonicalize
  /// away the rest of it.
  static String _mergeSystemBar(String source, OutputsConfig config) {
    final line = config.encodeLine();
    final merged = <String>[];
    var replaced = false;
    for (final raw in source.split('\n')) {
      final content = raw.endsWith('\r')
          ? raw.substring(0, raw.length - 1)
          : raw;
      if (!_isSystemBarLine(content)) {
        merged.add(raw);
        continue;
      }
      if (!replaced) {
        merged.add(line);
        replaced = true;
      }
      // Duplicate system_bar lines collapse into the one we just wrote.
    }
    if (!replaced) {
      if (merged.isNotEmpty && merged.last.isEmpty) {
        merged.insert(merged.length - 1, line);
      } else {
        merged.add(line);
      }
    }
    final result = merged.join('\n');
    return result.endsWith('\n') ? result : '$result\n';
  }

  @override
  Future<String> read() async {
    // The live document wins. A missing, unreadable, empty, or invalid live
    // file falls through to the previous snapshot, so a torn write never
    // silently resets placement to defaults while a good snapshot exists.
    return _readValidDocument() ?? const OutputsConfig().encode();
  }

  @override
  Future<String> write(String document) async {
    // Validation happens before anything touches the disk.
    final config = OutputsConfig.parse(document);
    final existing = _readMergeSource();
    final encoded = existing == null
        ? config.encode()
        : _mergeSystemBar(existing, config);
    file.parent.createSync(recursive: true);
    _snapshotPrevious();
    _writeAtomically(file, encoded);
    return encoded;
  }
}

/// Prefers the live bar's control socket and flips permanently to the file
/// transport only after genuine transport loss. A server-side rejection
/// (permission, disk, malformed document) propagates to the caller while the
/// socket stays in use.
class FallbackOutputsTransport implements OutputsDocumentTransport {
  FallbackOutputsTransport({required this.socket, required this.file});

  final OutputsDocumentTransport socket;
  final OutputsDocumentTransport file;

  var _usingSocket = true;

  bool get usingSocket => _usingSocket;

  @override
  Future<String> read() async {
    if (_usingSocket) {
      try {
        return await socket.read();
      } on ControlSocketException {
        _usingSocket = false;
      }
    }
    return file.read();
  }

  @override
  Future<String> write(String document) async {
    if (_usingSocket) {
      try {
        return await socket.write(document);
      } on ControlSocketException {
        _usingSocket = false;
      }
    }
    return file.write(document);
  }
}

/// Talks to the bar's control socket instead of the file.
class SocketOutputsTransport implements OutputsDocumentTransport {
  SocketOutputsTransport({
    String? socketPath,
    Future<Map<String, Object?>> Function(Map<String, Object?> request)?
    request,
  }) : _socketPath = socketPath,
       _request = request;

  final String? _socketPath;
  final Future<Map<String, Object?>> Function(Map<String, Object?> request)?
  _request;

  Future<Map<String, Object?>> _send(Map<String, Object?> request) {
    final send = _request;
    return send != null
        ? send(request)
        : controlRequest(request, socketPath: _socketPath);
  }

  @override
  Future<String> read() async {
    final reply = await _send(const <String, Object?>{
      'command': 'outputs.read',
    });
    return _document(reply);
  }

  @override
  Future<String> write(String document) async {
    final reply = await _send(<String, Object?>{
      'command': 'outputs.write',
      'document': document,
    });
    return _document(reply);
  }

  String _document(Map<String, Object?> reply) {
    if (reply['ok'] != true) {
      // A rejection is not a dead socket. Throwing a distinct exception keeps
      // [FallbackOutputsTransport] on the socket and lets the settings page
      // show the reason instead of silently rewriting the file.
      throw OutputsRequestException(
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
