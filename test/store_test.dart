import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/state/settings_bloc.dart';

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
  var reads = 0;

  @override
  Future<SettingsDocument> read() async {
    reads += 1;
    return document;
  }

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    if (expectedRevision != this.document.revision) {
      throw StateError(
        'revision ${this.document.revision} != $expectedRevision',
      );
    }
    final settings = BarSettings.decode(document);
    this.document = SettingsDocument(
      revision: settings.revision,
      json: document,
    );
    return this.document;
  }
}

class _DelayedWriteTransport implements SettingsDocumentTransport {
  _DelayedWriteTransport(this.document);

  SettingsDocument document;
  final writeStarted = Completer<void>();
  final _release = Completer<void>();
  var reads = 0;

  void release() => _release.complete();

  @override
  Future<SettingsDocument> read() async {
    reads += 1;
    return document;
  }

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async {
    writeStarted.complete();
    await _release.future;
    final settings = BarSettings.decode(document);
    this.document = SettingsDocument(
      revision: settings.revision,
      json: document,
    );
    return this.document;
  }
}

class _ServerErrorThenOkTransport implements SettingsDocumentTransport {
  var reads = 0;

  @override
  Future<SettingsDocument> read() async {
    reads += 1;
    if (reads == 1) {
      throw const ControlServerException('permission denied');
    }
    return SettingsDocument(
      revision: 2,
      json: const BarSettings(revision: 2).encode(),
    );
  }

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async => throw const ControlServerException('permission denied');
}

class _CountingFileTransport implements SettingsDocumentTransport {
  var reads = 0;

  @override
  Future<SettingsDocument> read() async {
    reads += 1;
    return SettingsDocument(
      revision: 9,
      json: const BarSettings(revision: 9).encode(),
    );
  }

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async => throw StateError('file transport must not be used');
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

      await store.write(const BarSettings(revision: 3, modules: ['clock']));
      expect(store.revision, 4);
      expect(transport.document.revision, 4);
    });

    test('write returns the written document without a read-back', () async {
      final transport = _MutableTransport(
        const SettingsDocument(revision: 1, json: '{"revision": 1}'),
      );
      final store = NativeSettingsStore(transport);
      await store.read();
      expect(transport.reads, 1);

      final written = await store.write(const BarSettings(modules: ['clock']));
      expect(written.revision, 2);
      expect(BarSettings.decode(written.json).modules, ['clock']);
      expect(transport.reads, 1);
      expect(store.revision, 2);
    });

    test('read waits for an in-flight write', () async {
      final transport = _DelayedWriteTransport(
        const SettingsDocument(revision: 1, json: '{"revision": 1}'),
      );
      final store = NativeSettingsStore(transport);
      await store.read();
      expect(transport.reads, 1);

      final write = store.write(const BarSettings(modules: ['clock']));
      await transport.writeStarted.future;
      final read = store.read();
      await Future<void>.delayed(Duration.zero);
      expect(transport.reads, 1);

      transport.release();
      await write;
      final after = await read;
      expect(transport.reads, 2);
      expect(after.revision, 2);
      expect(after.modules, ['clock']);
    });

    test(
      'surfaces a concurrent revision advance without a blind retry',
      () async {
        final transport = _RacingTransport(
          const SettingsDocument(revision: 1, json: '{"revision": 1}'),
        );
        final store = NativeSettingsStore(transport);
        await expectLater(
          store.write(const BarSettings(modules: ['clock'])),
          throwsA(isA<SettingsRevisionConflict>()),
        );
        expect(transport.writes, 1);
        expect(store.revision, 2);
        expect(transport.document.revision, 2);

        // A deliberate retry starts from the adopted revision and lands.
        await store.write(const BarSettings(revision: 2, modules: ['clock']));
        expect(transport.writes, 2);
        expect(store.revision, 3);
        expect(transport.document.revision, 3);
      },
    );

    test(
      'a first persist from a stale bar snapshot cannot overwrite disk',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'trickster-first-persist',
        );
        try {
          final file = File('${directory.path}/settings.json')
            ..writeAsStringSync(const BarSettings(revision: 1).encode());
          final settingsApp = FileSettingsTransport(file);
          await settingsApp.read();
          await settingsApp.write(
            expectedRevision: 1,
            document: const BarSettings(
              revision: 2,
              media: MediaOptions(mode: MediaMode.compact),
            ).encode(),
          );

          // The bar loaded revision 1 before the settings app wrote revision 2
          // and has never persisted, so its store has no adopted revision.
          final bar = NativeSettingsStore(FileSettingsTransport(file));
          await expectLater(
            bar.write(
              const BarSettings(revision: 1, accent: Color(0xff112233)),
            ),
            throwsA(isA<SettingsRevisionConflict>()),
          );

          final disk = BarSettings.decode(file.readAsStringSync());
          expect(disk.revision, 2);
          expect(disk.media.mode, MediaMode.compact);
          expect(disk.accent, isNull);
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );

    test(
      'a server refusal never flips the socket to the file transport',
      () async {
        final socket = _ServerErrorThenOkTransport();
        final file = _CountingFileTransport();
        final fallback = FallbackSettingsTransport(socket: socket, file: file);

        await expectLater(
          fallback.read(),
          throwsA(isA<ControlServerException>()),
        );
        expect(fallback.usingSocket, isTrue);
        expect(file.reads, 0);

        final next = await fallback.read();
        expect(next.revision, 2);
        expect(fallback.usingSocket, isTrue);
        expect(file.reads, 0);
      },
    );

    test(
      'media persist merges onto an external settings-app revision',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'trickster-media-merge',
        );
        try {
          final file = File('${directory.path}/settings.json')
            ..writeAsStringSync(
              const BarSettings(
                revision: 1,
                media: MediaOptions(mode: MediaMode.full),
              ).encode(),
            );
          final store = NativeSettingsStore(FileSettingsTransport(file));
          await store.read();

          final settingsApp = FileSettingsTransport(file);
          await settingsApp.read();
          await settingsApp.write(
            expectedRevision: 1,
            document: const BarSettings(
              revision: 2,
              locale: 'zh',
              accent: Color(0xff112233),
            ).encode(),
          );

          await persistMediaMode(store, MediaMode.compact);
          final disk = BarSettings.decode(file.readAsStringSync());
          expect(disk.revision, 3);
          expect(disk.media.mode, MediaMode.compact);
          expect(disk.locale, 'zh');
          expect(disk.accent, const Color(0xff112233));
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );

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
          throwsA(isA<SettingsRevisionConflict>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });
    test('two file transports cannot write the same revision', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trickster-cross-writer',
      );
      try {
        final file = File('${directory.path}/settings.json');
        final first = FileSettingsTransport(file);
        final second = FileSettingsTransport(file);
        expect((await first.read()).revision, 1);
        expect((await second.read()).revision, 1);

        await first.write(
          expectedRevision: 1,
          document: const BarSettings(
            revision: 2,
            accent: Color(0xff112233),
          ).encode(),
        );
        await expectLater(
          second.write(
            expectedRevision: 1,
            document: const BarSettings(
              revision: 2,
              accent: Color(0xff445566),
            ).encode(),
          ),
          throwsA(isA<SettingsRevisionConflict>()),
        );
        expect(
          BarSettings.decode(file.readAsStringSync()).accent,
          const Color(0xff112233),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('concurrent writers cannot both win the same revision', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trickster-concurrent',
      );
      try {
        final file = File('${directory.path}/settings.json')
          ..writeAsStringSync(const BarSettings(revision: 1).encode());
        for (var iteration = 0; iteration < 20; iteration += 1) {
          final first = FileSettingsTransport(file);
          final second = FileSettingsTransport(file);
          final current = (await first.read()).revision;
          expect((await second.read()).revision, current);

          final outcomes = await Future.wait<Object?>([
            first
                .write(
                  expectedRevision: current,
                  document: BarSettings(
                    revision: current + 1,
                    accent: const Color(0xff112233),
                  ).encode(),
                )
                .then<Object?>((document) => document)
                .catchError((Object error) => error),
            second
                .write(
                  expectedRevision: current,
                  document: BarSettings(
                    revision: current + 1,
                    accent: const Color(0xff445566),
                  ).encode(),
                )
                .then<Object?>((document) => document)
                .catchError((Object error) => error),
          ]);

          expect(
            outcomes.whereType<SettingsDocument>(),
            hasLength(1),
            reason: 'exactly one writer lands (iteration $iteration)',
          );
          expect(
            outcomes.whereType<SettingsRevisionConflict>(),
            hasLength(1),
            reason: 'the loser sees the conflict (iteration $iteration)',
          );
          final disk = BarSettings.decode(file.readAsStringSync());
          expect(disk.revision, current + 1);
          expect(
            disk.accent,
            anyOf(const Color(0xff112233), const Color(0xff445566)),
          );
        }
        expect(
          File('${file.path}.tmp').existsSync(),
          isFalse,
          reason: 'no fixed-name partial temp',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('a valid live rollback wins over newer memory', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trickster-rollback',
      );
      try {
        final file = File('${directory.path}/settings.json');
        final transport = FileSettingsTransport(file);
        await transport.read();
        await transport.write(
          expectedRevision: 1,
          document: const BarSettings(revision: 2).encode(),
        );
        await transport.write(
          expectedRevision: 2,
          document: const BarSettings(revision: 3).encode(),
        );
        expect((await transport.read()).revision, 3);

        file.writeAsStringSync(const BarSettings(revision: 2).encode());
        expect((await transport.read()).revision, 2);
        await transport.write(
          expectedRevision: 2,
          document: const BarSettings(revision: 3).encode(),
        );
        expect(BarSettings.decode(file.readAsStringSync()).revision, 3);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('recovery never downgrades a newer remembered document', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trickster-newest',
      );
      try {
        final file = File('${directory.path}/settings.json');
        final transport = FileSettingsTransport(file);
        await transport.read();
        await transport.write(
          expectedRevision: 1,
          document: const BarSettings(revision: 2).encode(),
        );
        await transport.write(
          expectedRevision: 2,
          document: const BarSettings(revision: 3).encode(),
        );
        expect(
          BarSettings.decode(
            File('${file.path}.prev').readAsStringSync(),
          ).revision,
          2,
        );

        file.writeAsStringSync('{"revision":3,"modules":');
        final recovered = await transport.read();
        expect(recovered.revision, 3);
        expect(BarSettings.decode(recovered.json).revision, 3);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('an unreadable live file falls through to .prev', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trickster-unreadable',
      );
      try {
        final file = File('${directory.path}/settings.json');
        final previous = File('${file.path}.prev');
        file.writeAsStringSync(const BarSettings(revision: 3).encode());
        previous.writeAsStringSync(const BarSettings(revision: 2).encode());
        final transport = FileSettingsTransport(
          file,
          readFile: (candidate) {
            if (candidate.path == file.path) {
              throw const FileSystemException('permission denied');
            }
            return candidate.readAsStringSync();
          },
        );
        final recovered = await transport.read();
        expect(recovered.revision, 2);
        expect(BarSettings.decode(recovered.json).revision, 2);
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

        // The recovered revision is usable for the next write, and the
        // corrupt live file must not overwrite the good snapshot.
        await FileSettingsTransport(file).write(
          expectedRevision: 1,
          document: const BarSettings(revision: 2).encode(),
        );
        expect(BarSettings.decode(file.readAsStringSync()).revision, 2);
        expect(BarSettings.decode(previous.readAsStringSync()).revision, 1);
        expect(File('${previous.path}.tmp').existsSync(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('file transport keeps .prev one revision behind', () async {
      final directory = await Directory.systemTemp.createTemp(
        'trickster-previous',
      );
      try {
        final file = File('${directory.path}/settings.json');
        final previous = File('${file.path}.prev');
        final transport = FileSettingsTransport(file);

        final first = await transport.read();
        expect(first.revision, 1);
        expect(previous.existsSync(), isFalse);

        await transport.write(
          expectedRevision: 1,
          document: const BarSettings(revision: 2).encode(),
        );
        expect(BarSettings.decode(file.readAsStringSync()).revision, 2);
        expect(BarSettings.decode(previous.readAsStringSync()).revision, 1);
        expect(File('${file.path}.tmp').existsSync(), isFalse);
        expect(File('${previous.path}.tmp').existsSync(), isFalse);

        await transport.write(
          expectedRevision: 2,
          document: const BarSettings(revision: 3).encode(),
        );
        expect(BarSettings.decode(file.readAsStringSync()).revision, 3);
        expect(BarSettings.decode(previous.readAsStringSync()).revision, 2);
        expect(File('${previous.path}.tmp').existsSync(), isFalse);

        await transport.write(
          expectedRevision: 3,
          document: const BarSettings(revision: 4).encode(),
        );
        expect(BarSettings.decode(file.readAsStringSync()).revision, 4);
        expect(BarSettings.decode(previous.readAsStringSync()).revision, 3);
        expect(File('${previous.path}.tmp').existsSync(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
