import 'dart:io';

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/platform/control_socket.dart';

class SettingsDocument {
  const SettingsDocument({required this.revision, required this.json});

  final int revision;
  final String json;
}

/// A write lost the revision race. The caller keeps the disk document and
/// asks the user to retry, rather than replacing the other writer's fields
/// with a stale whole-document snapshot.
class SettingsRevisionConflict implements Exception {
  const SettingsRevisionConflict({
    required this.expected,
    required this.actual,
  });

  final int expected;
  final int actual;

  String get message =>
      'settings changed elsewhere (revision $actual, expected $expected)';

  @override
  String toString() => 'SettingsRevisionConflict: $message';
}

abstract interface class SettingsDocumentTransport {
  Future<SettingsDocument> read();

  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  });
}

class FileSettingsTransport implements SettingsDocumentTransport {
  FileSettingsTransport(this.file, {String Function(File file)? readFile})
    : _readFile = readFile ?? _readFileSync;

  final File file;
  final String Function(File file) _readFile;

  SettingsDocument? _lastGood;

  static String _readFileSync(File file) => file.readAsStringSync();

  /// Synchronous read shared by the async transport and bootstrap. The live
  /// document wins; an unreadable or corrupt live file falls through to the
  /// retained previous snapshot, then to the in-memory last-good copy.
  SettingsDocument readSync() {
    for (final candidate in <File>[file, File('${file.path}.prev')]) {
      if (!candidate.existsSync()) {
        continue;
      }
      final String json;
      try {
        json = _readFile(candidate);
      } on Object {
        // An unreadable candidate is no more authoritative than a torn one.
        continue;
      }
      try {
        final settings = BarSettings.decode(json);
        final document = SettingsDocument(
          revision: settings.revision,
          json: json,
        );
        _lastGood = document;
        return document;
      } on Object {
        // Try the next candidate.
      }
    }
    final remembered = _lastGood;
    if (remembered != null) {
      return remembered;
    }
    if (!file.existsSync()) {
      final created = SettingsDocument(
        revision: 1,
        json: const BarSettings().encode(),
      );
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(created.json);
      _lastGood = created;
      return created;
    }
    // Both files exist but neither decodes and there is nothing remembered:
    // surface the live document's error rather than silently losing settings.
    final json = _readFile(file);
    final settings = BarSettings.decode(json);
    final document = SettingsDocument(revision: settings.revision, json: json);
    return document;
  }

  @override
  Future<SettingsDocument> read() async => readSync();

  /// Replaces `.prev` with the last document that decoded successfully. The
  /// live file may be torn when [read] recovered from `.prev`, so it must
  /// never be copied over the snapshot. The temp rename keeps `.prev` whole
  /// even if this process stops mid-snapshot.
  void _snapshotLastGood() {
    final good = _lastGood;
    if (good == null) {
      return;
    }
    final previous = File('${file.path}.prev');
    final temporary = File('${previous.path}.tmp');
    try {
      temporary.writeAsStringSync(good.json, flush: true);
      temporary.renameSync(previous.path);
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

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    // Always re-read: the revision line belongs to the file, not to this
    // long-lived object. A second transport instance (the bar's and a
    // file-fallback settings app are separate writers) may have advanced it.
    final current = await read();
    if (expectedRevision != current.revision) {
      throw SettingsRevisionConflict(
        expected: expectedRevision,
        actual: current.revision,
      );
    }
    final settings = BarSettings.decode(document);
    final next = SettingsDocument(
      revision: settings.revision,
      json: document.endsWith('\n') ? document : '$document\n',
    );
    final temporary = File('${file.path}.tmp');
    try {
      file.parent.createSync(recursive: true);
      // Snapshot the last document known to decode, never the live file: the
      // live file is corrupt when read recovered from .prev, and copying it
      // here would destroy the only good snapshot before the new write.
      _snapshotLastGood();
      temporary.writeAsStringSync(next.json, flush: true);
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
    _lastGood = next;
    return next;
  }
}

/// Prefers the live bar's control socket and flips permanently to the file
/// transport after the first transport loss. A revision mismatch is left to
/// [NativeSettingsStore] and never flips the transport.
class FallbackSettingsTransport implements SettingsDocumentTransport {
  FallbackSettingsTransport({required this.socket, required this.file});

  final SettingsDocumentTransport socket;
  final SettingsDocumentTransport file;

  var _usingSocket = true;

  bool get usingSocket => _usingSocket;

  @override
  Future<SettingsDocument> read() async {
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
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    if (_usingSocket) {
      try {
        return await socket.write(
          expectedRevision: expectedRevision,
          document: document,
        );
      } on ControlSocketException {
        _usingSocket = false;
      }
    }
    return file.write(expectedRevision: expectedRevision, document: document);
  }
}

/// Talks to the bar's control socket instead of the file. The same
/// `SettingsDocument` protocol rides one JSON request/reply line; revision
/// mismatches stay [StateError] so the store's conflict path is unchanged.
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
    // A watcher read must observe the same revision the save queue just wrote,
    // not the file as it stood before the in-flight write landed.
    await _writeQueue;
    return _readNow();
  }

  Future<BarSettings> _readNow() async {
    final document = await _transport.read();
    _remember(document);
    return BarSettings.decode(document.json);
  }

  Future<SettingsDocument> write(BarSettings settings) {
    final write = _writeQueue.then((_) => _write(settings));
    _writeQueue = write.then<void>((_) {}).catchError((Object _) {});
    return write;
  }

  Future<SettingsDocument> _write(BarSettings settings) async {
    // The caller's snapshot carries the revision it was derived from. A
    // first bar persist can have adopted nothing while the settings app has
    // already written; reading here would otherwise let the stale snapshot
    // overwrite that document at the adopted revision.
    if (_revision <= 0 || settings.revision != _revision) {
      await _readNow();
    }
    if (settings.revision != _revision) {
      throw SettingsRevisionConflict(
        expected: settings.revision,
        actual: _revision,
      );
    }
    final expected = _revision;
    final payload = settings.copyWith(revision: expected + 1).encode();
    try {
      final response = await _transport.write(
        expectedRevision: expected,
        document: payload,
      );
      _remember(response);
      return response;
    } on Object catch (error) {
      if (!_isRevisionConflict(error)) {
        rethrow;
      }
      // Adopt the other writer's document. The caller reloads it into the
      // editor and retries the user's change; resending this whole snapshot
      // here would silently discard the other writer's fields.
      await _readNow();
      throw SettingsRevisionConflict(expected: expected, actual: _revision);
    }
  }

  static bool _isRevisionConflict(Object error) {
    if (error is SettingsRevisionConflict) {
      return true;
    }
    return error is StateError &&
        error.message.toString().toLowerCase().contains('revision');
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
