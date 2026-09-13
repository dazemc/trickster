import 'dart:io';

import 'settings.dart';

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
    final json = file.readAsStringSync();
    final settings = BarSettings.decode(json);
    final document = SettingsDocument(revision: settings.revision, json: json);
    _current = document;
    _lastGood = document;
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
    final previous = File('${file.path}.prev');
    if (file.existsSync()) {
      file.copySync(previous.path);
    }
    file.writeAsStringSync(next.json);
    if (previous.existsSync()) {
      previous.deleteSync();
    }
    _current = next;
    _lastGood = next;
    return next;
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
    if (document.revision > _revision) {
      _revision = document.revision;
    }
  }
}
