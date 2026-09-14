import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/settings_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onPressed,
  bool enabled = true,
}) {
  return tester.pumpWidget(
    TricksterLocalizationScope(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SettingsResetButton(
            label: 'Reset clock format',
            enabled: enabled,
            onPressed: onPressed,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('fires once per tap and exposes its label', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await _pump(tester, onPressed: () => taps++);
    expect(find.bySemanticsLabel('Reset clock format'), findsOneWidget);
    await tester.tap(find.byType(SettingsResetButton));
    await tester.pump();
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('disabled state refuses taps and reports disabled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await _pump(tester, onPressed: () => taps++, enabled: false);
    await tester.tap(find.byType(SettingsResetButton));
    await tester.pump();
    expect(taps, 0);
    final node = tester.getSemantics(
      find.bySemanticsLabel('Reset clock format'),
    );
    expect(
      node.getSemanticsData().flagsCollection.isEnabled,
      ui.Tristate.isFalse,
    );
    handle.dispose();
  });
}
