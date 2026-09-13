import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster_bar/src/config/settings.dart';
import 'package:trickster_bar/src/config/store.dart';

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

void main() {
  group('NativeSettingsStore', () {
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
  });
}
