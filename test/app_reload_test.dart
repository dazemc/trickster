import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/app.dart';
import 'package:trickster/src/bootstrap.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';

void main() {
  const defaults = OutputsConfig();

  test('first apply reconciles even when the document is the default', () {
    expect(
      shouldReconcileOutputs(
        firstApply: true,
        previous: defaults,
        next: defaults,
      ),
      isTrue,
    );
  });

  test('identical outputs after the first apply skip reconciliation', () {
    expect(
      shouldReconcileOutputs(
        firstApply: false,
        previous: defaults,
        next: const OutputsConfig(),
      ),
      isFalse,
    );
  });

  test('a connector change reconciles', () {
    expect(
      shouldReconcileOutputs(
        firstApply: false,
        previous: defaults,
        next: const OutputsConfig(connectors: <String>['HDMI-A-1']),
      ),
      isTrue,
    );
  });

  test('side and thickness changes need the reconcile path', () {
    expect(
      shouldReconcileOutputs(
        firstApply: false,
        previous: defaults,
        next: const OutputsConfig(side: SystemBarSide.bottom),
      ),
      isTrue,
    );
    expect(
      shouldReconcileOutputs(
        firstApply: false,
        previous: defaults,
        next: const OutputsConfig(thickness: 40),
      ),
      isTrue,
    );
  });

  test('a settings-only reload keeps the native outputs untouched', () {
    const previous = OutputsConfig(
      side: SystemBarSide.top,
      thickness: 32,
      connectors: <String>['eDP-1'],
    );
    const next = OutputsConfig(
      side: SystemBarSide.top,
      thickness: 32,
      connectors: <String>['eDP-1'],
    );

    expect(
      shouldReconcileOutputs(firstApply: false, previous: previous, next: next),
      isFalse,
    );
  });

  test(
    'a recovered .prev applies on reload, fully invalid keeps last-good',
    () {
      final directory = Directory.systemTemp.createTempSync('trickster-reload');
      addTearDown(() => directory.deleteSync(recursive: true));
      final paths = ConfigPaths(configHome: directory.path);
      Directory(paths.root).createSync(recursive: true);
      const lastGood = OutputsConfig(
        side: SystemBarSide.top,
        thickness: 36,
        connectors: <String>['eDP-1'],
      );
      const lastGoodSettings = BarSettings(revision: 9);

      File(paths.outputs).writeAsStringSync('system_bar=nonsense,40\n');
      File('${paths.outputs}.prev').writeAsStringSync('system_bar=bottom,40\n');

      final recovered = Bootstrap.load(paths: paths);
      expect(recovered.outputsError, isNull);
      expect(recovered.outputsWarning, isNotNull);
      final applied = mergeReloadedConfig(
        loaded: recovered,
        lastGoodOutputs: lastGood,
        lastGoodSettings: lastGoodSettings,
      );
      expect(applied.outputs.side, SystemBarSide.bottom);
      expect(applied.outputs.thickness, 40);

      File('${paths.outputs}.prev').writeAsStringSync('not a document\n');
      final unusable = Bootstrap.load(paths: paths);
      expect(unusable.outputsError, isNotNull);
      expect(unusable.outputsWarning, isNull);
      final retained = mergeReloadedConfig(
        loaded: unusable,
        lastGoodOutputs: lastGood,
        lastGoodSettings: lastGoodSettings,
      );
      expect(retained.outputs, lastGood);
    },
  );
}
