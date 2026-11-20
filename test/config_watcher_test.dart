import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/watcher.dart';

class _WatchHarness {
  final List<StreamController<FileSystemEvent>> controllers =
      <StreamController<FileSystemEvent>>[];

  Stream<FileSystemEvent> open(Directory _) {
    final controller = StreamController<FileSystemEvent>(sync: true);
    controllers.add(controller);
    return controller.stream;
  }

  StreamController<FileSystemEvent> get current => controllers.last;

  Future<void> close() async {
    for (final controller in controllers) {
      await controller.close();
    }
  }
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('trickster-watch');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('start keeps a single live watch', () async {
    final harness = _WatchHarness();
    final watcher = ConfigWatcher(
      directory: directory,
      onChanged: () {},
      watch: harness.open,
    );
    try {
      watcher.start();
      watcher.start();
      expect(harness.controllers, hasLength(1));
    } finally {
      await watcher.dispose();
      await harness.close();
    }
  });

  test('an errored watch resubscribes and keeps the debounce', () async {
    final harness = _WatchHarness();
    var changes = 0;
    final watcher = ConfigWatcher(
      directory: directory,
      debounce: const Duration(milliseconds: 30),
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 20),
      onChanged: () => changes += 1,
      watch: harness.open,
    );
    try {
      watcher.start();
      harness.current.addError(StateError('watch failed'));
      expect(changes, 0);
      await _waitFor(() => harness.controllers.length == 2);

      harness.current
        ..add(FileSystemCreateEvent('settings.json', false))
        ..add(FileSystemCreateEvent('outputs.conf', false));
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(changes, 0);
      await _waitFor(() => changes == 1);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(changes, 1);
    } finally {
      await watcher.dispose();
      await harness.close();
    }
  });

  test('a closed watch resubscribes', () async {
    final harness = _WatchHarness();
    var changes = 0;
    final watcher = ConfigWatcher(
      directory: directory,
      debounce: const Duration(milliseconds: 20),
      retryDelay: const Duration(milliseconds: 10),
      retryDelayMax: const Duration(milliseconds: 20),
      onChanged: () => changes += 1,
      watch: harness.open,
    );
    try {
      watcher.start();
      await harness.current.close();
      await _waitFor(() => harness.controllers.length == 2);

      harness.current.add(FileSystemCreateEvent('settings.json', false));
      await _waitFor(() => changes == 1);
    } finally {
      await watcher.dispose();
      await harness.close();
    }
  });

  test('consecutive failures back off and cap the retry delay', () async {
    final opened = <DateTime>[];
    final harness = _WatchHarness();
    final watcher = ConfigWatcher(
      directory: directory,
      debounce: const Duration(milliseconds: 10),
      retryDelay: const Duration(milliseconds: 20),
      retryDelayMax: const Duration(milliseconds: 40),
      onChanged: () {},
      watch: (directory) {
        opened.add(DateTime.now());
        final controller = StreamController<FileSystemEvent>(sync: true);
        harness.controllers.add(controller);
        scheduleMicrotask(
          () => controller.addError(StateError('watch failed')),
        );
        return controller.stream;
      },
    );
    try {
      watcher.start();
      // Nine subscriptions take ~20 + 40 * 7 ms with the cap. Without one,
      // the eighth retry alone would be 2560 ms.
      await _waitFor(
        () => harness.controllers.length == 9,
        timeout: const Duration(seconds: 3),
      );

      final delays = <int>[
        for (var index = 1; index < opened.length; index += 1)
          opened[index].difference(opened[index - 1]).inMilliseconds,
      ];
      expect(delays[0], greaterThanOrEqualTo(15));
      expect(delays[1], greaterThanOrEqualTo(35));
      expect(delays[2], greaterThanOrEqualTo(35));
    } finally {
      await watcher.dispose();
      await harness.close();
    }
  });

  test('dispose cancels a pending restart', () async {
    final harness = _WatchHarness();
    final watcher = ConfigWatcher(
      directory: directory,
      debounce: const Duration(milliseconds: 10),
      retryDelay: const Duration(milliseconds: 100),
      retryDelayMax: const Duration(milliseconds: 200),
      onChanged: () {},
      watch: harness.open,
    );
    try {
      watcher.start();
      harness.current.addError(StateError('watch failed'));
      await watcher.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(harness.controllers, hasLength(1));
      expect(harness.current.hasListener, isFalse);
    } finally {
      await watcher.dispose();
      await harness.close();
    }
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
