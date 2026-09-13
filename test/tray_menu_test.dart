import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/bar/tray_menu.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/tray_menu.dart';
import 'package:trickster/src/theme/accent.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

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
  SystemTrayMenuEntry(
    id: 20,
    label: 'Delete',
    enabled: true,
    visible: true,
    separator: false,
    toggleType: SystemTrayMenuToggleType.none,
    toggleState: 0,
    destructive: true,
    children: <SystemTrayMenuEntry>[],
  ),
];

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell() : super(channel: const MethodChannel('test/trickster'));

  final opened = <int>[];
  final shown = <int>[];
  final closed = <int>[];
  var nextViewId = 100;
  var failOpen = false;

  @override
  Future<int?> openMenuSurface({
    required int barViewId,
    required String side,
  }) async {
    opened.add(barViewId);
    if (failOpen) {
      return null;
    }
    return nextViewId++;
  }

  @override
  Future<void> showMenuSurface({required int viewId}) async {
    shown.add(viewId);
  }

  @override
  Future<void> closeMenuSurface({required int viewId}) async {
    closed.add(viewId);
  }
}

class _FakeTrayService extends StatusNotifierService {
  _FakeTrayService(this.entries);

  final List<SystemTrayMenuEntry>? entries;
  final invoked = <SystemTrayAction>[];
  final activated = <int>[];

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> invoke(
    SystemTrayItem item,
    SystemTrayAction action,
    Offset position,
  ) async {
    invoked.add(action);
    return true;
  }

  @override
  Future<List<SystemTrayMenuEntry>?> loadMenu(SystemTrayItem item) async =>
      entries;

  @override
  Future<bool> activateMenuEntry(SystemTrayItem item, int entryId) async {
    activated.add(entryId);
    return true;
  }
}

const _click = Offset(120, 10);

Future<void> _show(TrayMenuController controller) {
  return controller.show(
    barViewId: 0,
    item: _item,
    entries: _entries,
    accent: _accent,
    click: _click,
    side: SystemBarSide.top,
    thickness: 32,
  );
}

Future<void> _pumpMenu(
  WidgetTester tester,
  TrayMenuController controller,
  TrayBloc bloc,
) async {
  await _show(controller);
  await tester.pumpWidget(
    BlocProvider<TrayBloc>.value(
      value: bloc,
      child: TricksterLocalizationScope(
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: TapRegionSurface(
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final session = controller.session;
                      if (session == null) {
                        return const SizedBox.shrink();
                      }
                      return TrayMenuSurface(
                        session: session,
                        controller: controller,
                      );
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
}

Future<void> _pumpPill(
  WidgetTester tester,
  TrayMenuController controller,
  TrayBloc bloc, {
  bool menuAvailable = true,
}) {
  return tester.pumpWidget(
    BlocProvider<TrayBloc>.value(
      value: bloc,
      child: TricksterLocalizationScope(
        child: TrayMenuScope(
          notifier: controller,
          child: Center(
            child: TrayPill(
              accent: _accent,
              items: [
                SystemTrayItem(
                  id: _item.id,
                  title: _item.title,
                  status: _item.status,
                  iconName: _item.iconName,
                  iconThemePath: _item.iconThemePath,
                  iconPixmap: _item.iconPixmap,
                  menuAvailable: menuAvailable,
                  primaryOpensMenu: _item.primaryOpensMenu,
                ),
              ],
              onActivate: (item, position) {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('menu surface renders entries and activates the selected one', (
    tester,
  ) async {
    final shell = _FakeLayerShell();
    final controller = TrayMenuController(layerShell: shell);
    final service = _FakeTrayService(_entries);
    final bloc = TrayBloc(service: service);
    addTearDown(bloc.close);
    await _pumpMenu(tester, controller, bloc);
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(service.activated, [10]);
    expect(controller.session, isNull);
    expect(shell.closed, contains(100));
  });

  testWidgets('tapping outside dismisses the menu surface', (tester) async {
    final shell = _FakeLayerShell();
    final controller = TrayMenuController(layerShell: shell);
    final bloc = TrayBloc(service: _FakeTrayService(_entries));
    addTearDown(bloc.close);
    await _pumpMenu(tester, controller, bloc);
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsNothing);
    expect(shell.closed, contains(100));
  });

  testWidgets('a secondary click outside dismisses the menu surface', (
    tester,
  ) async {
    final shell = _FakeLayerShell();
    final controller = TrayMenuController(layerShell: shell);
    final bloc = TrayBloc(service: _FakeTrayService(_entries));
    addTearDown(bloc.close);
    await _pumpMenu(tester, controller, bloc);
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsNothing);
    expect(shell.closed, contains(100));
  });

  testWidgets('escape dismisses the menu surface', (tester) async {
    final shell = _FakeLayerShell();
    final controller = TrayMenuController(layerShell: shell);
    final bloc = TrayBloc(service: _FakeTrayService(_entries));
    addTearDown(bloc.close);
    await _pumpMenu(tester, controller, bloc);
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsNothing);
    expect(shell.closed, contains(100));
  });

  testWidgets('right-click hands the loaded menu to the controller', (
    tester,
  ) async {
    final shell = _FakeLayerShell();
    final controller = TrayMenuController(layerShell: shell);
    final bloc = TrayBloc(service: _FakeTrayService(_entries));
    addTearDown(bloc.close);
    await _pumpPill(tester, controller, bloc);

    await tester.tap(
      find.byKey(const ValueKey<String>('tray-item-item')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(shell.opened, [tester.view.viewId]);
    expect(controller.session?.entries, hasLength(2));
    expect(shell.shown, contains(controller.session!.viewId));
  });

  testWidgets('items without a menu fall back to the D-Bus context menu', (
    tester,
  ) async {
    final shell = _FakeLayerShell();
    final service = _FakeTrayService(null);
    final controller = TrayMenuController(layerShell: shell);
    final bloc = TrayBloc(service: service);
    addTearDown(bloc.close);
    await _pumpPill(tester, controller, bloc, menuAvailable: false);

    await tester.tap(
      find.byKey(const ValueKey<String>('tray-item-item')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(shell.opened, isEmpty);
    expect(service.invoked, [SystemTrayAction.contextMenu]);
  });

  testWidgets('a failed surface falls back to the D-Bus context menu', (
    tester,
  ) async {
    final shell = _FakeLayerShell()..failOpen = true;
    final service = _FakeTrayService(_entries);
    final controller = TrayMenuController(layerShell: shell);
    final bloc = TrayBloc(service: service);
    addTearDown(bloc.close);
    await _pumpPill(tester, controller, bloc);

    await tester.tap(
      find.byKey(const ValueKey<String>('tray-item-item')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(shell.opened, isNotEmpty);
    expect(controller.session, isNull);
    expect(service.invoked, [SystemTrayAction.contextMenu]);
  });

  test('opening a menu destroys the previous surface', () async {
    final shell = _FakeLayerShell();
    final controller = TrayMenuController(layerShell: shell);
    Future<bool> open() => controller.show(
      barViewId: 0,
      item: _item,
      entries: _entries,
      accent: _accent,
      click: Offset.zero,
      side: SystemBarSide.top,
      thickness: 32,
    );

    expect(await open(), isTrue);
    final first = controller.session!.viewId;
    expect(await open(), isTrue);

    expect(shell.closed, contains(first));
    expect(controller.session!.viewId, isNot(first));
  });
}
