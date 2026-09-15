import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/shell_keys.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

const _trayItem = SystemTrayItem(
  id: 'item-1',
  title: 'qBittorrent',
  status: SystemTrayStatus.active,
  iconName: '',
  iconThemePath: '',
  iconPixmap: null,
  menuAvailable: false,
  primaryOpensMenu: false,
);

/// Mirrors the shell keymap the app root installs.
Widget _keymap(Widget child) => withOverlayBlocs(
  Shortcuts(
    shortcuts: shellShortcuts,
    child: Actions(
      actions: WidgetsApp.defaultActions,
      child: FocusScope(
        autofocus: true,
        child: TricksterLocalizationScope(child: Center(child: child)),
      ),
    ),
  ),
);

/// Walks the live semantics tree so assertions read the merged node, not
/// whichever ancestor [WidgetTester.getSemantics] happens to return.
SemanticsNode _nodeByLabel(WidgetTester tester, String label) {
  final view = tester.binding.renderViews.first;
  final root = view.owner!.semanticsOwner!.rootSemanticsNode!;
  final matches = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.label == label) {
      matches.add(node);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return matches.single;
}

void main() {
  testWidgets('load meters announce caption and percent', (tester) async {
    await tester.pumpWidget(
      _keymap(const CpuPill(accent: _accent, sample: CpuSample(0.42))),
    );
    final handle = tester.ensureSemantics();
    final cpu = _nodeByLabel(tester, 'CPU');
    expect(cpu.getSemanticsData().value, '42%');

    await tester.pumpWidget(
      _keymap(
        const GpuPill(
          accent: _accent,
          load: GpuLoad(
            id: 'card0',
            label: 'AMD0',
            name: 'RTX 4070 Ti',
            usage: 0.42,
            history: [0.42],
          ),
          captionSource: MeterCaptionSource.device,
        ),
      ),
    );
    expect(_nodeByLabel(tester, 'RTX 4070 Ti').getSemanticsData().value, '42%');
    expect(find.bySemanticsLabel('AMD0'), findsNothing);
    handle.dispose();
  });

  testWidgets('clock announces one label with the full date and time', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [BlocProvider(create: (_) => ClockBloc())],
        child: _keymap(const ClockPill(accent: _accent)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final handle = tester.ensureSemantics();
    final clock = _nodeByLabel(tester, 'Clock');
    expect(clock.getSemanticsData().value, matches(RegExp(r'.+\d{1,2}:\d{2}')));
    handle.dispose();
  });

  testWidgets('tray items announce label, status, hint, and tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _keymap(
        TrayItemButton(accent: _accent, item: _trayItem, onActivate: (_, _) {}),
      ),
    );
    final handle = tester.ensureSemantics();
    final tray = _nodeByLabel(tester, 'qBittorrent');
    expect(tray.getSemanticsData().value, 'Active');
    expect(tray.getSemanticsData().hint, 'Activates the item');
    expect(tray.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('battery and tray activate from the keyboard alone', (
    tester,
  ) async {
    var batteryPressed = 0;
    var trayActivated = 0;
    await tester.pumpWidget(
      _keymap(
        FocusTraversalGroup(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BatteryPill(
                accent: _accent,
                status: const BatteryStatus(capacity: 87, charging: true),
                onPressed: () => batteryPressed++,
              ),
              const SizedBox(width: 8),
              TrayItemButton(
                accent: _accent,
                item: _trayItem,
                onActivate: (_, _) => trayActivated++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(batteryPressed, 1);
    expect(trayActivated, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(trayActivated, 1);
  });

  testWidgets('workspace pips expose selection and activate by keyboard', (
    tester,
  ) async {
    var focused = '';
    await tester.pumpWidget(
      _keymap(
        FocusTraversalGroup(
          child: WorkspacesPill(
            accent: _accent,
            horizontal: true,
            workspaces: const [
              Workspace(id: '1', name: '1', occupied: true),
              Workspace(id: '2', name: '2', focused: true),
            ],
            onPressed: (workspace) => focused = workspace.id,
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    final active = _nodeByLabel(tester, 'Workspace 2, empty, active');
    expect(
      active.getSemanticsData().flagsCollection.isSelected,
      ui.Tristate.isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(focused, '1');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(focused, '2');
    handle.dispose();
  });
}
