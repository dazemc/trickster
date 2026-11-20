import 'dart:io';

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/platform/control_socket.dart';

class SettingsDocument {
  const SettingsDocument({required this.revision, required this.json});

  final int revision;
  final String json;
}

abstract interface class SettingsDocumentTransport {
  Future<SettingsDocument> read();

  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  });
}

class FileSettingsTransport implements SettingsDocumentTransport {
  FileSettingsTransport(this.file);

  final File file;

  SettingsDocument? _current;
  SettingsDocument? _lastGood;

  SettingsDocument? get lastGood => _lastGood;

  @override
  Future<SettingsDocument> read() async {
    // The live document wins; a torn write or a corrupt edit falls back to
    // the retained previous snapshot, then to the in-memory last-good copy.
    for (final candidate in <File>[file, File('${file.path}.prev')]) {
      if (!candidate.existsSync()) {
        continue;
      }
      final json = candidate.readAsStringSync();
      try {
        final settings = BarSettings.decode(json);
        final document = SettingsDocument(
          revision: settings.revision,
          json: json,
        );
        _current = document;
        _lastGood = document;
        return document;
      } on Object {
        // Try the next candidate.
      }
    }
    final remembered = _lastGood;
    if (remembered != null) {
      _current = remembered;
      return remembered;
    }
    if (!file.existsSync()) {
      final created = SettingsDocument(
        revision: 1,
        json: const BarSettings().encode(),
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(created.json);
      _current = created;
      _lastGood = created;
      return created;
    }
    // Both files exist but neither decodes and there is nothing remembered:
    // surface the live document's error rather than silently losing settings.
    final json = file.readAsStringSync();
    final settings = BarSettings.decode(json);
    final document = SettingsDocument(revision: settings.revision, json: json);
    _current = document;
    return document;
  }

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    final current = _current ?? await read();
    if (expectedRevision != current.revision) {
      throw StateError(
        'settings revision ${current.revision} != expected $expectedRevision',
      );
    }
    final settings = BarSettings.decode(document);
    final next = SettingsDocument(
      revision: settings.revision,
      json: document.endsWith('\n') ? document : '$document\n',
    );
    final temporary = File('${file.path}.tmp');
    final previous = File('${file.path}.prev');
    try {
      file.parent.createSync(recursive: true);
      if (file.existsSync()) {
        file.copySync(previous.path);
      }
      temporary.writeAsStringSync(next.json);
      // Atomic replace: a crash before this point leaves the live document
      // (or its .prev snapshot) intact; no reader ever sees a partial file.
      temporary.renameSync(file.path);
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
    _current = next;
    _lastGood = next;
    return next;
  }
}

/// Talks to the bar's control socket instead of the file. The same
/// `SettingsDocument` protocol rides one JSON request/reply line; revision
/// mismatches stay [StateError] so the store's retry path is unchanged.
class SocketSettingsTransport implements SettingsDocumentTransport {
  SocketSettingsTransport({String? socketPath}) : _socketPath = socketPath;

  final String? _socketPath;

  @override
  Future<SettingsDocument> read() async {
    final reply = await controlRequest(const <String, Object?>{
      'command': 'settings.read',
    }, socketPath: _socketPath);
    return _decode(reply);
  }

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    final reply = await controlRequest(<String, Object?>{
      'command': 'settings.write',
      'expectedRevision': expectedRevision,
      'document': document,
    }, socketPath: _socketPath);
    return _decode(reply);
  }

  SettingsDocument _decode(Map<String, Object?> reply) {
    if (reply['ok'] != true) {
      final error = '${reply['error'] ?? 'control request failed'}';
      if (error.toLowerCase().contains('revision')) {
        throw StateError(error);
      }
      throw ControlSocketException(error);
    }
    final revision = reply['revision'];
    final document = reply['document'];
    if (revision is! int || document is! String) {
      throw const ControlSocketException(
        'control socket sent a malformed settings document',
      );
    }
    return SettingsDocument(revision: revision, json: document);
  }
}

class NativeSettingsStore {
  NativeSettingsStore(this._transport);

  final SettingsDocumentTransport _transport;
  Future<void> _writeQueue = Future<void>.value();
  int _revision = 0;

  int get revision => _revision;

  Future<BarSettings> read() async {
    final document = await _transport.read();
    _remember(document);
    return BarSettings.decode(document.json);
  }

  Future<void> write(BarSettings settings) {
    final write = _writeQueue.then((_) => _write(settings));
    _writeQueue = write.catchError((_) {});
    return write;
  }

  Future<void> _write(BarSettings settings) async {
    if (_revision <= 0) {
      await read();
    }
    final payload = settings.copyWith(revision: _revision + 1).encode();
    try {
      final response = await _transport.write(
        expectedRevision: _revision,
        document: payload,
      );
      _remember(response);
    } on StateError {
      await read();
      final retry = settings.copyWith(revision: _revision + 1).encode();
      final response = await _transport.write(
        expectedRevision: _revision,
        document: retry,
      );
      _remember(response);
    }
  }

  void _remember(SettingsDocument document) {
    if (document.revision <= 0) {
      throw StateError('Trickster returned an invalid settings revision');
    }
    // Adopt the document's revision exactly, including a lower one after an
    // external rollback. Keeping a stale higher revision makes every later
    // write fail its expectedRevision check against the rolled-back file.
    _revision = document.revision;
  }
}
