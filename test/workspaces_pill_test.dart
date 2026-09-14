import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

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
  ValueChanged<Workspace>? onPressed,
}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: TricksterLocalizationScope(
        child: Center(
          child: WorkspacesPill(
            accent: _accent,
            workspaces: workspaces,
            horizontal: horizontal,
            onPressed: onPressed,
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
    expect(empty.color, _accent.captionColor());
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
  test('rail filtering picks exactly the outputs workspaces', () {
    const all = <Workspace>[
      Workspace(id: '1', name: '1', output: 'HDMI-A-1', focused: true),
      Workspace(id: '2', name: '2', output: 'HDMI-A-2'),
      Workspace(id: '3', name: '3', output: 'HDMI-A-1'),
    ];
    expect(
      workspacesForOutput(all, 'HDMI-A-1').map((workspace) => workspace.id),
      <String>['1', '3'],
    );
    expect(
      workspacesForOutput(all, 'HDMI-A-2').map((workspace) => workspace.id),
      <String>['2'],
    );
    expect(workspacesForOutput(all, null), all);
    expect(workspacesForOutput(all, 'DP-1'), isEmpty);
    const unknown = <Workspace>[Workspace(id: '1', name: '1')];
    expect(workspacesForOutput(unknown, 'HDMI-A-1'), unknown);
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
