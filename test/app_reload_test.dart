import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/app.dart';
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
}
