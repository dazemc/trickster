import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to mention notifier or cubit state, with the reason. Empty
/// on purpose: every piece of observable state is a bloc. The rule leaves
/// only per-frame widget-local details (animation controllers, hover and
/// press flags) in `State` objects, and no banned token names those.
const _exceptions = <String, String>{};

/// The shapes the architecture forbids under `lib/`.
const _banned = <String>[
  'ChangeNotifier',
  'InheritedNotifier',
  'Cubit',
];

void main() {
  test('lib/ carries no notifier or cubit state', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'run this from the package root (flutter test does)',
    );
    final offenders = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (_exceptions.containsKey(entity.path)) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final token in _banned) {
        if (source.contains(token)) {
          offenders.add('${entity.path}: $token');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'observable state belongs to a bloc under lib/src/state: move it '
          'there with explicit events, or list an approved exception in '
          'test/bloc_only_test.dart',
    );
  });

  test('every listed exception names a real file and a reason', () {
    for (final entry in _exceptions.entries) {
      expect(
        File(entry.key).existsSync(),
        isTrue,
        reason: '${entry.key} is listed but does not exist',
      );
      expect(entry.value.trim(), isNotEmpty);
    }
  });
}
