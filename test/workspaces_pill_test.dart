import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/theme/accent.dart';

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
}) {
  return tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: WorkspacesPill(
            accent: _accent,
            workspaces: workspaces,
            horizontal: horizontal,
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

  testWidgets('reduced motion zeroes the lens animation', (tester) async {
    await _pump(tester, _focused('2'), reduceMotion: true);
    final lens = tester.widget<AnimatedAlign>(
      find.byKey(WorkspacesPill.lensKey),
    );
    expect(lens.duration, Duration.zero);
  });
}
