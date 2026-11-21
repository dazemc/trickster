import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/bar_menu.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/platform/settings_launcher.dart';
import 'package:trickster/src/services/overlay_coordinator.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/state/bar_menu_bloc.dart';
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/tray_menu.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));
const _click = Offset(120, 10);

const _item = SystemTrayItem(
  id: 'item',
  title: 'Test Tray',
  status: SystemTrayStatus.active,
  iconName: 'icon',
  iconThemePath: '',
  iconPixmap: null,
  menuAvailable: true,
  primaryOpensMenu: false,
  menuPath: '/Menu',
);

const _entries = <SystemTrayMenuEntry>[
  SystemTrayMenuEntry(
    id: 10,
    label: 'Play',
    enabled: true,
    visible: true,
    separator: false,
    toggleType: SystemTrayMenuToggleType.none,
    toggleState: 0,
    destructive: false,
    children: <SystemTrayMenuEntry>[],
  ),
];

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell({this.throwOnClose = false})
    : super(channel: const MethodChannel('test/trickster/bar-menu'));

  final bool throwOnClose;
  final events = <String>[];
  final opened = <(int, String)>[];
  final shown = <int>[];
  final closed = <int>[];
  var nextViewId = 100;
  var failOpen = false;

  @override
  Future<int?> openMenuSurface({
    required int barViewId,
    required String side,
  }) async {
    opened.add((barViewId, side));
    if (failOpen) {
      return null;
    }
    final viewId = nextViewId++;
    events.add('open-$viewId');
    return viewId;
  }

  @override
  Future<void> showMenuSurface({required int viewId}) async {
    shown.add(viewId);
    events.add('show-$viewId');
  }

  @override
  Future<void> closeMenuSurface({required int viewId}) async {
    closed.add(viewId);
    events.add('close-$viewId');
    if (throwOnClose) {
      throw StateError('surface already destroyed');
    }
  }
}

class _FakeTrayService extends StatusNotifierService {
  _FakeTrayService(this.entries);

  final List<SystemTrayMenuEntry>? entries;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<List<SystemTrayMenuEntry>?> loadMenu(SystemTrayItem item) async =>
      entries;
}

BarMenuBloc _menuBloc(
  _FakeLayerShell shell, {
  BarMenuSettingsLauncher? launch,
}) {
  return BarMenuBloc(
    layerShell: shell,
    launchSettings: launch ?? () async => true,
  );
}

void _request(BarMenuBloc menu, {Offset click = _click}) {
  menu.add(
    BarMenuRequested(
      barViewId: 0,
      accent: _accent,
      click: click,
      side: SystemBarSide.top,
      thickness: 32,
    ),
  );
}

void _requestTray(TrayMenuBloc menu) {
  menu.add(
    const TrayMenuRequested(
      barViewId: 0,
      item: _item,
      entries: _entries,
      accent: _accent,
      click: _click,
      side: SystemBarSide.top,
      thickness: 32,
    ),
  );
}

Future<void> _settle() => pumpEventQueue();

/// Pumps the overlay the way the app's view slot does, with the bar menu
/// panel mounted while a session is open.
Future<void> _pumpMenu(WidgetTester tester, BarMenuBloc menu) async {
  _request(menu);
  await tester.pumpWidget(
    BlocProvider<BarMenuBloc>.value(
      value: menu,
      child: TricksterLocalizationScope(
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: TapRegionSurface(
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => BlocBuilder<BarMenuBloc, BarMenuState>(
                    builder: (context, state) {
                      final session = state.session;
                      if (session == null) {
                        return const SizedBox.shrink();
                      }
                      return BarMenuSurface(session: session);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('BarMenuBloc', () {
    test('opens one overlay surface and keeps the session', () async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);

      _request(menu);
      await _settle();

      expect(shell.opened, [(0, 'top')]);
      expect(shell.shown, [100]);
      final session = menu.state.session;
      expect(session, isNotNull);
      expect(session!.viewId, 100);
      expect(session.click, _click);
      expect(session.side, SystemBarSide.top);
      expect(menu.state.isBarMenuView(100), isTrue);
    });

    test('a duplicate request never opens a second surface', () async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);

      _request(menu);
      _request(menu);
      await _settle();

      expect(shell.opened, hasLength(1));
      expect(shell.shown, hasLength(1));
      expect(shell.closed, isEmpty);
    });

    test('dismissing closes the native surface', () async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);
      _request(menu);
      await _settle();

      menu.add(const BarMenuDismissed());
      await _settle();

      expect(menu.state.session, isNull);
      expect(shell.closed, [100]);
    });

    test(
      'selecting settings dismisses before launching exactly once',
      () async {
        final shell = _FakeLayerShell();
        var launches = 0;
        final menu = _menuBloc(
          shell,
          launch: () async {
            launches += 1;
            shell.events.add('launch');
            return true;
          },
        );
        addTearDown(menu.close);
        _request(menu);
        await _settle();

        menu.add(const BarMenuSettingsSelected());
        menu.add(const BarMenuSettingsSelected());
        await _settle();

        expect(launches, 1);
        expect(menu.state.session, isNull);
        expect(shell.closed, [100]);
        expect(
          shell.events.indexOf('close-100'),
          lessThan(shell.events.indexOf('launch')),
        );
      },
    );

    test('a failed surface leaves no session and releases the claim', () async {
      final shell = _FakeLayerShell()..failOpen = true;
      final menu = _menuBloc(shell);
      addTearDown(menu.close);

      _request(menu);
      await _settle();
      expect(menu.state.session, isNull);
      expect(shell.shown, isEmpty);

      shell.failOpen = false;
      _request(menu);
      await _settle();

      expect(menu.state.session, isNotNull);
      expect(shell.opened, hasLength(2));
    });

    test('a missing retained view drops the session', () async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);
      _request(menu);
      await _settle();

      menu.add(const BarMenuViewsRetained(<int>{999}));
      await _settle();

      expect(menu.state.session, isNull);
      expect(menu.state.barMenuViewIds, isEmpty);
    });

    test('closing the bloc closes an open native surface', () async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      _request(menu);
      await _settle();
      final viewId = menu.state.session!.viewId;

      await menu.close();

      expect(shell.closed, [viewId]);
    });

    test('state json round-trips its view bookkeeping', () async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);
      _request(menu);
      await _settle();

      final decoded = BarMenuState.fromJson(menu.state.toJson());

      expect(decoded.barMenuViewIds, menu.state.barMenuViewIds);
      expect(decoded.session, isNull);
    });
  });

  group('overlay coordinator', () {
    test('opening the bar menu dismisses an open tray menu first', () async {
      final shell = _FakeLayerShell();
      final coordinator = OverlayCoordinator(
        dismissTimeout: const Duration(milliseconds: 50),
      );
      final trayMenu = TrayMenuBloc(
        layerShell: shell,
        coordinator: coordinator,
      );
      final barMenu = BarMenuBloc(
        layerShell: shell,
        coordinator: coordinator,
        launchSettings: () async => true,
      );
      addTearDown(coordinator.dispose);
      addTearDown(trayMenu.close);
      addTearDown(barMenu.close);

      _requestTray(trayMenu);
      await _settle();
      final trayView = trayMenu.state.session!.viewId;

      _request(barMenu);
      await _settle();

      expect(trayMenu.state.session, isNull);
      expect(barMenu.state.isOpen, isTrue);
      final barView = barMenu.state.session!.viewId;
      expect(
        shell.events.indexOf('close-$trayView'),
        lessThan(shell.events.indexOf('open-$barView')),
      );
    });

    test('a tooltip request is refused while the bar menu is open', () async {
      final shell = _FakeLayerShell();
      final coordinator = OverlayCoordinator(
        dismissTimeout: const Duration(milliseconds: 50),
      );
      final barMenu = BarMenuBloc(
        layerShell: shell,
        coordinator: coordinator,
        launchSettings: () async => true,
      );
      final tooltip = OverlayTooltipBloc(
        layerShell: shell,
        coordinator: coordinator,
      );
      addTearDown(coordinator.dispose);
      addTearDown(barMenu.close);
      addTearDown(tooltip.close);

      _request(barMenu);
      await _settle();
      tooltip.add(
        const OverlayTooltipRequested(
          barViewId: 0,
          itemId: 'item',
          label: 'Tooltip',
          accent: _accent,
          click: _click,
          side: SystemBarSide.top,
          thickness: 32,
        ),
      );
      await _settle();

      expect(barMenu.state.isOpen, isTrue);
      expect(tooltip.state.session, isNull);
    });
  });

  group('bar menu surface', () {
    testWidgets('renders the settings entry with accessible semantics', (
      tester,
    ) async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);
      final semantics = tester.ensureSemantics();

      await _pumpMenu(tester, menu);

      expect(find.text('Trickster Settings'), findsOneWidget);
      expect(find.bySemanticsLabel('Trickster Settings'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('takes keyboard focus when it opens', (tester) async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);

      await _pumpMenu(tester, menu);
      final focus = tester.widget<Focus>(
        find.byKey(const ValueKey<String>('bar-menu-focus')),
      );

      expect(focus.focusNode!.hasFocus, isTrue);
    });

    testWidgets('selecting the entry dismisses and launches once', (
      tester,
    ) async {
      final shell = _FakeLayerShell();
      var launches = 0;
      final menu = _menuBloc(
        shell,
        launch: () async {
          launches += 1;
          return true;
        },
      );
      addTearDown(menu.close);
      await _pumpMenu(tester, menu);

      await tester.tap(find.text('Trickster Settings'));
      await tester.pumpAndSettle();

      expect(launches, 1);
      expect(menu.state.session, isNull);
      expect(shell.closed, [100]);

      // A late duplicate selection cannot relaunch the process.
      menu.add(const BarMenuSettingsSelected());
      await tester.pumpAndSettle();
      expect(launches, 1);
    });

    testWidgets('tapping outside dismisses the menu', (tester) async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);
      await _pumpMenu(tester, menu);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.text('Trickster Settings'), findsNothing);
      expect(menu.state.session, isNull);
      expect(shell.closed, [100]);
    });

    testWidgets('Escape dismisses the menu', (tester) async {
      final shell = _FakeLayerShell();
      final menu = _menuBloc(shell);
      addTearDown(menu.close);
      await _pumpMenu(tester, menu);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Trickster Settings'), findsNothing);
      expect(menu.state.session, isNull);
      expect(shell.closed, [100]);
    });

    testWidgets('a dead surface does not stop the settings launch', (
      tester,
    ) async {
      final shell = _FakeLayerShell(throwOnClose: true);
      var launches = 0;
      final menu = _menuBloc(
        shell,
        launch: () async {
          launches += 1;
          return true;
        },
      );
      addTearDown(menu.close);
      await _pumpMenu(tester, menu);

      await tester.tap(find.text('Trickster Settings'));
      await tester.pumpAndSettle();

      expect(launches, 1);
      expect(menu.state.session, isNull);
    });
  });

  group('strip hit testing', () {
    testWidgets('empty strip opens the menu; a tray module keeps its own', (
      tester,
    ) async {
      final service = _FakeTrayService(_entries);
      final tray = TrayBloc(
        service: service,
        initial: const TrayState([_item]),
      );
      // The harness provider owns the bloc and disposes it with the tree;
      // awaiting close inside FakeAsync can hang on the event pipeline.
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['tray']),
        trayBuilder: () => tray,
      );
      await tester.pump(const Duration(milliseconds: 500));

      final context = tester.element(find.byType(TricksterBarStrip));
      final barMenu = context.read<BarMenuBloc>();
      final trayMenu = context.read<TrayMenuBloc>();

      // Empty strip: the background detector is behind the zone layout.
      final strip = tester.getRect(find.byType(TricksterBarStrip));
      await tester.tapAt(
        Offset(strip.right - 20, strip.center.dy),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(barMenu.state.isOpen, isTrue);
      expect(trayMenu.state.isOpen, isFalse);

      barMenu.add(const BarMenuDismissed());
      await tester.pump();
      await tester.pump();
      expect(barMenu.state.isOpen, isFalse);

      // Tray pill: the module owns the secondary click and opens its own
      // menu; the bar menu stays closed.
      await tester.tap(
        find.byKey(const ValueKey<String>('tray-item-item')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(barMenu.state.isOpen, isFalse);
      expect(trayMenu.state.isOpen, isTrue);
    });

    testWidgets('a non-interactive pill still claims its whole box', (
      tester,
    ) async {
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['cpu']),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final menu = tester
          .element(find.byType(TricksterBarStrip))
          .read<BarMenuBloc>();

      // The padding inside the pill paints no text, but it is module surface:
      // the zone listener must keep the bar menu out of it.
      final pill = tester.getRect(find.byType(CpuPill));
      await tester.tapAt(
        Offset(pill.left + 2, pill.center.dy),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(menu.state.isOpen, isFalse);
    });
  });

  group('settings launcher', () {
    test('starts the current executable with --settings, detached', () async {
      final calls = <(String, List<String>)>[];
      final launched = await launchTricksterSettings(
        executable: '/usr/bin/trickster',
        start: (executable, arguments) async {
          calls.add((executable, arguments));
          return true;
        },
      );

      expect(launched, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.$1, '/usr/bin/trickster');
      expect(calls.single.$2, <String>['--settings']);
    });

    test('forwards the bar config override to the settings app', () async {
      final calls = <(String, List<String>)>[];
      final launched = await launchTricksterSettings(
        executable: '/usr/bin/trickster',
        configPath: '/home/me/.config/trickster/alt-outputs.conf',
        start: (executable, arguments) async {
          calls.add((executable, arguments));
          return true;
        },
      );

      expect(launched, isTrue);
      expect(calls.single.$2, <String>[
        '--settings',
        '--config',
        '/home/me/.config/trickster/alt-outputs.conf',
      ]);
    });

    test('argument shaping drops an empty override', () {
      expect(settingsLaunchArguments(), <String>['--settings']);
      expect(settingsLaunchArguments(configPath: ''), <String>['--settings']);
      expect(settingsLaunchArguments(configPath: '/tmp/outputs.conf'), <String>[
        '--settings',
        '--config',
        '/tmp/outputs.conf',
      ]);
    });

    test('an empty executable never starts a process', () async {
      var calls = 0;
      final launched = await launchTricksterSettings(
        executable: '',
        start: (executable, arguments) async {
          calls += 1;
          return true;
        },
      );

      expect(launched, isFalse);
      expect(calls, 0);
    });

    test('a failed start reports false', () async {
      final launched = await launchTricksterSettings(
        executable: '/usr/bin/trickster',
        start: (executable, arguments) async => false,
      );

      expect(launched, isFalse);
    });
  });
}
