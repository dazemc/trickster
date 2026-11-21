import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/keyboard_layout.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/keyboard_layout.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));
const _state = KeyboardLayoutState(
  available: true,
  backend: 'hyprland',
  active: 'US',
  index: 0,
  names: ['us', 'ru'],
);

Future<void> _pump(
  WidgetTester tester,
  KeyboardLayoutState state, {
  bool vertical = false,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        child: Center(
          child: KeyboardLayoutPill(
            accent: _accent,
            state: state,
            vertical: vertical,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('keyboard pill shows KB and the active layout', (tester) async {
    await _pump(tester, _state);
    expect(find.text('KB'), findsOneWidget);
    expect(find.text('US'), findsOneWidget);
    final tooltip = tester.widget<PillTooltip>(find.byType(PillTooltip));
    expect(tooltip.label, contains('US / RU'));
  });

  testWidgets('unavailable state renders nothing', (tester) async {
    await _pump(
      tester,
      const KeyboardLayoutState(available: false, backend: 'hyprland'),
    );
    expect(find.byType(KeyboardLayoutPill), findsOneWidget);
    expect(find.text('KB'), findsNothing);
    expect(find.textContaining('US'), findsNothing);
  });

  testWidgets('a state without an active layout renders nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      const KeyboardLayoutState(
        available: true,
        backend: 'hyprland',
        names: ['us'],
      ),
    );
    expect(find.text('KB'), findsNothing);
  });

  testWidgets('vertical layout stacks KB over the layout', (tester) async {
    await _pump(tester, _state, vertical: true);
    expect(find.text('KB'), findsOneWidget);
    expect(find.text('US'), findsOneWidget);
  });

  testWidgets('keyboard pill exposes the caption and active semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _state);
    final node = tester.getSemantics(find.bySemanticsLabel('KB'));
    expect(node.value, 'US');
    expect(node.label, 'KB');
    handle.dispose();
  });
}
