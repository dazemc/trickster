import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart' show PipStyle;
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

const _three = [
  Workspace(id: '1', name: '1'),
  Workspace(id: '2', name: 'web'),
  Workspace(id: '3', name: '3'),
];

List<Workspace> _focused(String id) => [
  for (final workspace in _three)
    Workspace(
      id: workspace.id,
      name: workspace.name,
      focused: workspace.id == id,
    ),
];

Future<void> _pump(
  WidgetTester tester,
  List<Workspace> workspaces, {
  bool horizontal = true,
  bool reduceMotion = false,
  PipStyle style = PipStyle.number,
  ValueChanged<Workspace>? onPressed,
}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: withOverlayBlocs(
        TricksterLocalizationScope(
          child: Center(
            child: WorkspacesPill(
              accent: _accent,
              workspaces: workspaces,
              horizontal: horizontal,
              style: style,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    ),
  );
}

Alignment _alignment(WidgetTester tester) =>
    tester.widget<AnimatedAlign>(find.byKey(WorkspacesPill.lensKey)).alignment
        as Alignment;

void main() {
  testWidgets('rail prints one label per workspace', (tester) async {
    await _pump(tester, _focused('2'));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('web'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('lens aligns with the focused id', (tester) async {
    await _pump(tester, _focused('1'));
    expect(_alignment(tester), Alignment.centerLeft);
    await _pump(tester, _focused('2'));
    expect(_alignment(tester), Alignment.center);
    await _pump(tester, _focused('3'));
    expect(_alignment(tester), Alignment.centerRight);
  });

  testWidgets('lens follows the bar axis', (tester) async {
    await _pump(tester, _focused('3'), horizontal: false);
    expect(_alignment(tester), Alignment.bottomCenter);
  });

  testWidgets('reduced motion zeroes the rail animations', (tester) async {
    await _pump(tester, const [
      Workspace(id: '1', name: '1'),
      Workspace(id: '2', name: '2', focused: true),
    ], reduceMotion: true);
    final lens = tester.widget<AnimatedAlign>(
      find.byKey(WorkspacesPill.lensKey),
    );
    expect(lens.duration, Duration.zero);
    final pip = tester.widget<AnimatedDefaultTextStyle>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('workspace-pip-1')),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .last,
    );
    expect(pip.duration, Duration.zero);
  });

  testWidgets('each pip fires the callback with its own workspace', (
    tester,
  ) async {
    final pressed = <Workspace>[];
    await _pump(tester, _focused('2'), onPressed: pressed.add);
    await tester.tap(find.byKey(const ValueKey<String>('workspace-pip-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('workspace-pip-3')));
    await tester.pump();
    expect(pressed, [_three[0], _three[2]]);
  });

  testWidgets('pip semantics announce name, state, and selection', (
    tester,
  ) async {
    await _pump(tester, _focused('2'), onPressed: (_) {});
    expect(
      find.bySemanticsLabel('Workspace web, empty, active'),
      findsOneWidget,
    );
  });

  testWidgets('pip labels style active, occupied, and empty states', (
    tester,
  ) async {
    await _pump(tester, const [
      Workspace(id: '1', name: '1'),
      Workspace(id: '2', name: '2', occupied: true),
      Workspace(id: '3', name: '3', focused: true),
    ]);
    final empty = _pipStyle(tester, '1');
    final occupied = _pipStyle(tester, '2');
    final active = _pipStyle(tester, '3');
    expect(
      empty.color,
      ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.3),
    );
    expect(occupied.color, ShellMediaColors.lightForeground);
    expect(active.color, _accent.color);
    expect(active.fontSize, ShellText.systemBarValue.fontSize! + 1);
    expect(empty.fontSize, ShellText.systemBarCaption.fontSize! + 2);
  });

  testWidgets('active lens deforms on switch and settles', (tester) async {
    await _pump(tester, _focused('1'));
    await _pump(tester, _focused('2'));
    await tester.pump();
    final scales = <double>[];
    for (var step = 0; step < 50; step++) {
      await tester.pump(const Duration(milliseconds: 8));
      scales.add(_lensScale(tester).$1);
    }
    expect(scales.reduce((a, b) => a > b ? a : b), closeTo(1.34, 0.02));
    expect(scales.reduce((a, b) => a < b ? a : b), closeTo(0.94, 0.02));
    expect(scales.last, closeTo(1.0, 0.001));
  });

  testWidgets('vertical lens trades the deformation axes', (tester) async {
    await _pump(tester, _focused('1'), horizontal: false);
    await _pump(tester, _focused('3'), horizontal: false);
    await tester.pump();
    var peak = (scaleX: 1.0, scaleY: 1.0);
    for (var step = 0; step < 50; step++) {
      await tester.pump(const Duration(milliseconds: 8));
      final (scaleX, scaleY) = _lensScale(tester);
      if (scaleY > peak.scaleY) {
        peak = (scaleX: scaleX, scaleY: scaleY);
      }
    }
    expect(peak.scaleY, closeTo(1.34, 0.02));
    expect(peak.scaleX, closeTo(1 - 0.34 * 0.34, 0.02));
  });

  testWidgets(
    'dot style paints one tinted dot per workspace and keeps the lens',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _focused('2'), style: PipStyle.dot);

      // No name glyphs, one dot per workspace.
      expect(find.text('1'), findsNothing);
      expect(find.text('web'), findsNothing);
      for (final id in ['1', '2', '3']) {
        expect(
          find.byKey(ValueKey<String>('workspace-dot-$id')),
          findsOneWidget,
        );
      }
      // The focused dot wears the accent; the rest keep the label tints.
      expect(_dotColor(tester, '2'), _accent.color);
      expect(
        _dotColor(tester, '1'),
        ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.3),
      );
      // The active lens and the labels survive the style change.
      expect(find.byKey(WorkspacesPill.lensKey), findsOneWidget);
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('workspace-pip-2')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.label, 'Workspace web, empty, active');
      handle.dispose();
    },
  );

  testWidgets('roman style paints numerals and falls back to names', (
    tester,
  ) async {
    await _pump(tester, _focused('3'), style: PipStyle.roman);

    expect(find.text('I'), findsOneWidget);
    expect(find.text('III'), findsOneWidget);
    // A named workspace has no numeral and stays as it is.
    expect(find.text('web'), findsOneWidget);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('long roman numerals share one uniform scale', (tester) async {
    await _pump(tester, const [
      Workspace(id: '1', name: '1', focused: true),
      Workspace(id: '8', name: '8'),
    ], style: PipStyle.roman);
    expect(find.text('I'), findsOneWidget);
    expect(find.text('VIII'), findsOneWidget);

    double scaleOf(String id) {
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byKey(ValueKey<String>('workspace-pip-$id')),
              matching: find.byType(Transform),
            )
            .first,
      );
      return transform.transform.entry(0, 0);
    }

    // Both pips paint at the same, shrunk scale: the wide numeral fits and
    // the narrow one is not left visibly larger.
    expect(scaleOf('1'), scaleOf('8'));
    expect(scaleOf('1'), lessThan(1));
  });

  test('roman numerals cover the compact range', () {
    expect(romanNumeral(1), 'I');
    expect(romanNumeral(4), 'IV');
    expect(romanNumeral(9), 'IX');
    expect(romanNumeral(40), 'XL');
    expect(romanNumeral(444), 'CDXLIV');
    expect(romanNumeral(3999), 'MMMCMXCIX');
    expect(romanNumeral(0), isNull);
    expect(romanNumeral(4000), isNull);
    expect(pipLabel('7', PipStyle.roman), 'VII');
    expect(pipLabel('web', PipStyle.roman), 'web');
    expect(pipLabel('7', PipStyle.number), '7');
  });

  testWidgets('reduced motion keeps the lens at rest', (tester) async {
    await _pump(tester, _focused('1'), reduceMotion: true);
    await _pump(tester, _focused('2'), reduceMotion: true);
    for (var step = 0; step < 50; step++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(_lensScale(tester).$1, 1);
    }
  });

  testWidgets('active lens uses the ported dark fill', (tester) async {
    await _pump(tester, _focused('2'));
    final lens = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(WorkspacesPill.lensKey),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = lens.decoration as BoxDecoration;
    expect(decoration.color, ShellMediaColors.darkness.withValues(alpha: 0.36));
  });
}

(double, double) _lensScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byKey(WorkspacesPill.lensKey),
      matching: find.byType(Transform),
    ),
  );
  return (transform.transform.entry(0, 0), transform.transform.entry(1, 1));
}

TextStyle _pipStyle(WidgetTester tester, String id) {
  final pip = tester.widget<AnimatedDefaultTextStyle>(
    find
        .descendant(
          of: find.byKey(ValueKey<String>('workspace-pip-$id')),
          matching: find.byType(AnimatedDefaultTextStyle),
        )
        .last,
  );
  return pip.style;
}

Color _dotColor(WidgetTester tester, String id) {
  final dot = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byKey(ValueKey<String>('workspace-dot-$id')),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (dot.decoration! as BoxDecoration).color!;
}
