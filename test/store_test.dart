import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';

class _RacingTransport implements SettingsDocumentTransport {
  _RacingTransport(this.document);

  SettingsDocument document;
  var writes = 0;

  @override
  Future<SettingsDocument> read() async => document;

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    writes++;
    if (writes == 1) {
      // Simulate a concurrent native write racing the shell projection.
      this.document = SettingsDocument(
        revision: expectedRevision + 1,
        json: this.document.json,
      );
      throw StateError('revision advanced concurrently');
    }
    final settings = BarSettings.decode(document);
    this.document = SettingsDocument(
      revision: settings.revision,
      json: document,
    );
    return this.document;
  }
}

class _MutableTransport implements SettingsDocumentTransport {
  _MutableTransport(this.document);

  SettingsDocument document;

  @override
  Future<SettingsDocument> read() async => document;

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    if (expectedRevision != this.document.revision) {
      throw StateError('revision ${this.document.revision} != $expectedRevision');
    }
    final settings = BarSettings.decode(document);
    this.document = SettingsDocument(
      revision: settings.revision,
      json: document,
    );
    return this.document;
  }
}

void main() {
  group('NativeSettingsStore', () {
    test('adopts a lower revision from an external rollback', () async {
      final transport = _MutableTransport(
        const SettingsDocument(revision: 5, json: '{"revision": 5}'),
      );
      final store = NativeSettingsStore(transport);
      await store.read();
      expect(store.revision, 5);

      // A restored older document is the new source of truth.
      transport.document = const SettingsDocument(
        revision: 3,
        json: '{"revision": 3}',
      );
      await store.read();
      expect(store.revision, 3);

      await store.write(const BarSettings(modules: ['clock']));
      expect(store.revision, 4);
      expect(transport.document.revision, 4);
    });

    test('retries once after a concurrent revision advance', () async {
      final transport = _RacingTransport(
        const SettingsDocument(revision: 1, json: '{"revision": 1}'),
      );
      final store = NativeSettingsStore(transport);
      await store.write(const BarSettings(modules: ['clock']));
      expect(transport.writes, 2);
      expect(store.revision, 3);
      expect(transport.document.revision, 3);
    });

    test('file transport round-trips and keeps revisions', () async {
      final directory = await Directory.systemTemp.createTemp('trickster');
      try {
        final file = File('${directory.path}/settings.json');
        final transport = FileSettingsTransport(file);
        final first = await transport.read();
        expect(first.revision, 1);
        expect(file.existsSync(), isTrue);

        final next = await transport.write(
          expectedRevision: first.revision,
          document: const BarSettings(revision: 2).encode(),
        );
        expect(next.revision, 2);
        expect(
          () => transport.write(
            expectedRevision: 1,
            document: const BarSettings(revision: 9).encode(),
          ),
          throwsStateError,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
    test('file transport writes atomically and recovers from .prev', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trickster-atomic',
      );
      try {
        final file = File('${directory.path}/settings.json');
        final first = await FileSettingsTransport(file).read();
        expect(first.revision, 1);

        final transport = FileSettingsTransport(file);
        await transport.write(
          expectedRevision: 1,
          document: const BarSettings(revision: 2).encode(),
        );
        expect(File('${file.path}.tmp').existsSync(), isFalse);
        final previous = File('${file.path}.prev');
        expect(previous.existsSync(), isTrue);
        expect(BarSettings.decode(previous.readAsStringSync()).revision, 1);

        // Simulate a crash that leaves a torn live document.
        file.writeAsStringSync('{"revision":2,"modules":');
        final recovered = await FileSettingsTransport(file).read();
        expect(recovered.revision, 1);
        expect(BarSettings.decode(recovered.json).revision, 1);

        // The recovered revision is usable for the next write.
        await FileSettingsTransport(file).write(
          expectedRevision: 1,
          document: const BarSettings(revision: 2).encode(),
        );
        expect(BarSettings.decode(file.readAsStringSync()).revision, 2);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
