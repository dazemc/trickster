import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/overlay_coordinator.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/state/calendar_bloc.dart';
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/state/tray_menu.dart';
import 'package:trickster/src/state/volume_slider_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

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

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell()
    : super(channel: const MethodChannel('test/trickster/overlay-coordinator'));

  final events = <String>[];
  final closedMenus = <int>[];
  final closedTooltips = <int>[];
  var nextViewId = 100;
  var failMenuOpen = false;
  var failTooltipOpen = false;

  @override
  Future<int?> openMenuSurface({
    required int barViewId,
    required String side,
  }) async {
    if (failMenuOpen) {
      return null;
    }
    final viewId = nextViewId++;
    events.add('open-menu-$viewId');
    return viewId;
  }

  @override
  Future<void> showMenuSurface({required int viewId}) async {
    events.add('show-menu-$viewId');
  }

  @override
  Future<void> closeMenuSurface({required int viewId}) async {
    closedMenus.add(viewId);
    events.add('close-menu-$viewId');
  }

  @override
  Future<int?> openTooltipSurface({
    required int barViewId,
    required String side,
  }) async {
    if (failTooltipOpen) {
      return null;
    }
    final viewId = nextViewId++;
    events.add('open-tooltip-$viewId');
    return viewId;
  }

  @override
  Future<void> showTooltipSurface({required int viewId}) async {
    events.add('show-tooltip-$viewId');
  }

  @override
  Future<void> closeTooltipSurface({required int viewId}) async {
    closedTooltips.add(viewId);
    events.add('close-tooltip-$viewId');
  }
}

void _requestMenu(TrayMenuBloc bloc) {
  bloc.add(
    const TrayMenuRequested(
      barViewId: 0,
      item: _item,
      entries: <SystemTrayMenuEntry>[],
      accent: _accent,
      click: _click,
      side: SystemBarSide.top,
      thickness: 32,
    ),
  );
}

void _requestCalendar(CalendarBloc bloc) {
  bloc.add(
    CalendarRequested(
      barViewId: 0,
      month: DateTime(2026, 11),
      accent: _accent,
      click: _click,
      side: SystemBarSide.top,
      thickness: 32,
    ),
  );
}

void _requestSlider(VolumeSliderBloc bloc) {
  bloc.add(
    const VolumeSliderRequested(
      barViewId: 0,
      accent: _accent,
      click: _click,
      side: SystemBarSide.top,
      thickness: 32,
    ),
  );
}

void _requestTooltip(
  OverlayTooltipBloc bloc, {
  String itemId = 'item',
  String label = 'Tooltip',
}) {
  bloc.add(
    OverlayTooltipRequested(
      barViewId: 0,
      itemId: itemId,
      label: label,
      accent: _accent,
      click: _click,
      side: SystemBarSide.top,
      thickness: 32,
    ),
  );
}

Future<void> _settle() => pumpEventQueue();

void main() {
  test('opening the calendar dismisses the open tray menu first', () async {
    final shell = _FakeLayerShell();
    final coordinator = OverlayCoordinator(
      dismissTimeout: const Duration(milliseconds: 50),
    );
    final menu = TrayMenuBloc(layerShell: shell, coordinator: coordinator);
    final calendar = CalendarBloc(layerShell: shell, coordinator: coordinator);
    addTearDown(coordinator.dispose);
    addTearDown(menu.close);
    addTearDown(calendar.close);

    _requestMenu(menu);
    await _settle();
    final menuView = menu.state.session!.viewId;

    _requestCalendar(calendar);
    await _settle();

    expect(menu.state.session, isNull);
    expect(calendar.state.isOpen, isTrue);
    expect(shell.closedMenus, contains(menuView));
    final calendarView = calendar.state.session!.viewId;
    expect(
      shell.events.indexOf('close-menu-$menuView'),
      lessThan(shell.events.indexOf('open-menu-$calendarView')),
    );
  });

  test('a tooltip request is refused while a modal is open', () async {
    final shell = _FakeLayerShell();
    final coordinator = OverlayCoordinator();
    final menu = TrayMenuBloc(layerShell: shell, coordinator: coordinator);
    final tooltip = OverlayTooltipBloc(
      layerShell: shell,
      coordinator: coordinator,
    );
    addTearDown(coordinator.dispose);
    addTearDown(menu.close);
    addTearDown(tooltip.close);

    _requestMenu(menu);
    await _settle();
    _requestTooltip(tooltip);
    await _settle();

    expect(menu.state.isOpen, isTrue);
    expect(tooltip.state.session, isNull);
    expect(
      shell.events.where((event) => event.startsWith('open-tooltip')),
      isEmpty,
    );
  });

  test('opening a menu closes the active tooltip first', () async {
    final shell = _FakeLayerShell();
    final coordinator = OverlayCoordinator();
    final menu = TrayMenuBloc(layerShell: shell, coordinator: coordinator);
    final tooltip = OverlayTooltipBloc(
      layerShell: shell,
      coordinator: coordinator,
    );
    addTearDown(coordinator.dispose);
    addTearDown(menu.close);
    addTearDown(tooltip.close);

    _requestTooltip(tooltip);
    await _settle();
    final tooltipView = tooltip.state.session!.viewId;

    _requestMenu(menu);
    await _settle();

    expect(tooltip.state.session, isNull);
    expect(shell.closedTooltips, contains(tooltipView));
    expect(menu.state.isOpen, isTrue);
    final menuView = menu.state.session!.viewId;
    expect(
      shell.events.indexOf('close-tooltip-$tooltipView'),
      lessThan(shell.events.indexOf('open-menu-$menuView')),
    );
  });

  test('same-kind tooltip requests retarget in place', () async {
    final shell = _FakeLayerShell();
    final coordinator = OverlayCoordinator();
    final tooltip = OverlayTooltipBloc(
      layerShell: shell,
      coordinator: coordinator,
    );
    addTearDown(coordinator.dispose);
    addTearDown(tooltip.close);

    _requestTooltip(tooltip, itemId: 'one', label: 'One');
    await _settle();
    final viewId = tooltip.state.session!.viewId;

    _requestTooltip(tooltip, itemId: 'two', label: 'Two');
    await _settle();

    expect(tooltip.state.session!.viewId, viewId);
    expect(tooltip.state.session!.itemId, 'two');
    expect(tooltip.state.session!.label, 'Two');
    expect(shell.closedTooltips, isEmpty);
  });

  test('same-kind modal requests replace only that modal', () async {
    final shell = _FakeLayerShell();
    final coordinator = OverlayCoordinator();
    final menu = TrayMenuBloc(layerShell: shell, coordinator: coordinator);
    final calendar = CalendarBloc(layerShell: shell, coordinator: coordinator);
    addTearDown(coordinator.dispose);
    addTearDown(menu.close);
    addTearDown(calendar.close);

    _requestMenu(menu);
    await _settle();
    final firstView = menu.state.session!.viewId;

    _requestMenu(menu);
    await _settle();

    expect(menu.state.isOpen, isTrue);
    expect(menu.state.session!.viewId, isNot(firstView));
    expect(shell.closedMenus, contains(firstView));
    expect(calendar.state.isOpen, isFalse);
  });

  test('closing a bloc releases the modal claim', () async {
    final shell = _FakeLayerShell();
    final coordinator = OverlayCoordinator();
    final menu = TrayMenuBloc(layerShell: shell, coordinator: coordinator);
    final tooltip = OverlayTooltipBloc(
      layerShell: shell,
      coordinator: coordinator,
    );
    addTearDown(coordinator.dispose);
    addTearDown(menu.close);
    addTearDown(tooltip.close);

    _requestMenu(menu);
    await _settle();
    await menu.close();

    _requestTooltip(tooltip);
    await _settle();

    expect(tooltip.state.isOpen, isTrue);
  });

  test('dismissing a modal releases the claim', () async {
    final shell = _FakeLayerShell();
    final coordinator = OverlayCoordinator();
    final menu = TrayMenuBloc(layerShell: shell, coordinator: coordinator);
    final tooltip = OverlayTooltipBloc(
      layerShell: shell,
      coordinator: coordinator,
    );
    addTearDown(coordinator.dispose);
    addTearDown(menu.close);
    addTearDown(tooltip.close);

    _requestMenu(menu);
    await _settle();
    menu.add(const TrayMenuDismissed());
    await _settle();

    expect(menu.state.session, isNull);
    _requestTooltip(tooltip);
    await _settle();

    expect(tooltip.state.isOpen, isTrue);
  });

  test('a retained-view clear releases the modal claim', () async {
    final shell = _FakeLayerShell();
    final coordinator = OverlayCoordinator();
    final menu = TrayMenuBloc(layerShell: shell, coordinator: coordinator);
    final tooltip = OverlayTooltipBloc(
      layerShell: shell,
      coordinator: coordinator,
    );
    addTearDown(coordinator.dispose);
    addTearDown(menu.close);
    addTearDown(tooltip.close);

    _requestMenu(menu);
    await _settle();
    menu.add(const TrayMenuViewsRetained(<int>{999}));
    await _settle();

    expect(menu.state.session, isNull);
    _requestTooltip(tooltip);
    await _settle();

    expect(tooltip.state.isOpen, isTrue);
  });

  test('a failed open releases the modal claim', () async {
    final shell = _FakeLayerShell()..failMenuOpen = true;
    final coordinator = OverlayCoordinator();
    final menu = TrayMenuBloc(layerShell: shell, coordinator: coordinator);
    final slider = VolumeSliderBloc(
      layerShell: shell,
      coordinator: coordinator,
    );
    addTearDown(coordinator.dispose);
    addTearDown(menu.close);
    addTearDown(slider.close);

    _requestMenu(menu);
    await _settle();
    expect(menu.state.session, isNull);

    shell.failMenuOpen = false;
    _requestSlider(slider);
    await _settle();

    expect(slider.state.isOpen, isTrue);
  });

  test(
    'a hung dismissal times out instead of blocking the next open',
    () async {
      final coordinator = OverlayCoordinator(
        dismissTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(coordinator.dispose);
      coordinator.register(
        OverlayKind.trayMenu,
        () => Completer<void>().future,
      );

      expect(await coordinator.request(OverlayKind.trayMenu), isTrue);
      expect(
        await coordinator
            .request(OverlayKind.calendar)
            .timeout(const Duration(seconds: 1)),
        isTrue,
      );
      expect(coordinator.hasModal, isTrue);

      coordinator.release(OverlayKind.calendar);
      expect(await coordinator.request(OverlayKind.tooltip), isTrue);
    },
  );
}
