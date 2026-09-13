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
  testWidgets('rail shows one pip per workspace and prints no names', (
    tester,
  ) async {
    await _pump(tester, _focused('2'));
    expect(find.text('web'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('workspace-pip-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('workspace-pip-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('workspace-pip-3')),
      findsOneWidget,
    );
  });

  testWidgets('lens aligns with the focused id', (tester) async {
    await _pump(tester, _focused('1'));
    expect(_alignment(tester), const Alignment(-1, 0));
    await _pump(tester, _focused('2'));
    expect(_alignment(tester), Alignment.center);
    await _pump(tester, _focused('3'));
    expect(_alignment(tester), const Alignment(1, 0));
  });

  testWidgets('lens follows the bar axis', (tester) async {
    await _pump(tester, _focused('3'), horizontal: false);
    expect(_alignment(tester), const Alignment(0, 1));
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
    final pip = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('workspace-pip-1')),
        matching: find.byType(AnimatedContainer),
      ),
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

  testWidgets('pips distinguish empty, occupied, and urgent states', (
    tester,
  ) async {
    await _pump(tester, const [
      Workspace(id: '1', name: '1'),
      Workspace(id: '2', name: '2', occupied: true),
      Workspace(id: '3', name: '3', urgent: true),
    ]);
    final empty = _pipColor(tester, '1');
    final occupied = _pipColor(tester, '2');
    final urgent = _pipColor(tester, '3');
    expect(occupied, ShellMediaColors.lightForeground);
    expect(urgent, ShellTelemetryColors.warning);
    expect({empty, occupied, urgent}, hasLength(3));
  });

  testWidgets('focused pip carries the accent', (tester) async {
    await _pump(tester, _focused('2'));
    expect(_pipColor(tester, '2'), _accent.color);
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

Color? _pipColor(WidgetTester tester, String id) {
  final pip = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byKey(ValueKey<String>('workspace-pip-$id')),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (pip.decoration as BoxDecoration?)?.color;
}
