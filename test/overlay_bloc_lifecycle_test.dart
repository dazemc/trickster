import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
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
  _FakeLayerShell({this.throwOnClose = false})
    : super(channel: const MethodChannel('test/trickster/overlay-lifecycle'));

  final bool throwOnClose;
  final List<int> closedMenus = <int>[];
  final List<int> closedTooltips = <int>[];
  var _nextViewId = 100;

  @override
  Future<int?> openMenuSurface({
    required int barViewId,
    required String side,
  }) async {
    return _nextViewId++;
  }

  @override
  Future<void> showMenuSurface({required int viewId}) async {}

  @override
  Future<void> closeMenuSurface({required int viewId}) async {
    closedMenus.add(viewId);
    if (throwOnClose) {
      throw StateError('surface already destroyed');
    }
  }

  @override
  Future<int?> openTooltipSurface({
    required int barViewId,
    required String side,
  }) async {
    return _nextViewId++;
  }

  @override
  Future<void> showTooltipSurface({required int viewId}) async {}

  @override
  Future<void> closeTooltipSurface({required int viewId}) async {
    closedTooltips.add(viewId);
    if (throwOnClose) {
      throw StateError('surface already destroyed');
    }
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

void _requestTooltip(OverlayTooltipBloc bloc) {
  bloc.add(
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
}

Future<void> _settle() => pumpEventQueue();

void main() {
  test('closing the tray menu closes its native overlay', () async {
    final shell = _FakeLayerShell();
    final bloc = TrayMenuBloc(layerShell: shell);
    _requestMenu(bloc);
    await _settle();
    final viewId = bloc.state.session!.viewId;

    await bloc.close();

    expect(shell.closedMenus, <int>[viewId]);
  });

  test('closing the calendar closes its native overlay', () async {
    final shell = _FakeLayerShell();
    final bloc = CalendarBloc(layerShell: shell);
    _requestCalendar(bloc);
    await _settle();
    final viewId = bloc.state.session!.viewId;

    await bloc.close();

    expect(shell.closedMenus, <int>[viewId]);
  });

  test('closing the volume slider closes its native overlay', () async {
    final shell = _FakeLayerShell();
    final bloc = VolumeSliderBloc(layerShell: shell);
    _requestSlider(bloc);
    await _settle();
    final viewId = bloc.state.session!.viewId;

    await bloc.close();

    expect(shell.closedMenus, <int>[viewId]);
  });

  test('closing the tooltip closes its native overlay', () async {
    final shell = _FakeLayerShell();
    final bloc = OverlayTooltipBloc(layerShell: shell);
    _requestTooltip(bloc);
    await _settle();
    final viewId = bloc.state.session!.viewId;

    await bloc.close();

    expect(shell.closedTooltips, <int>[viewId]);
  });

  test('a missing retained tray menu view clears the session', () async {
    final shell = _FakeLayerShell();
    final bloc = TrayMenuBloc(layerShell: shell);
    addTearDown(bloc.close);
    _requestMenu(bloc);
    await _settle();

    bloc.add(const TrayMenuViewsRetained(<int>{999}));
    await _settle();

    expect(bloc.state.session, isNull);
    expect(bloc.state.menuViewIds, isEmpty);
  });

  test('a missing retained calendar view clears the session', () async {
    final shell = _FakeLayerShell();
    final bloc = CalendarBloc(layerShell: shell);
    addTearDown(bloc.close);
    _requestCalendar(bloc);
    await _settle();

    bloc.add(const CalendarViewsRetained(<int>{999}));
    await _settle();

    expect(bloc.state.session, isNull);
    expect(bloc.state.calendarViewIds, isEmpty);
  });

  test('a missing retained slider view clears the session', () async {
    final shell = _FakeLayerShell();
    final bloc = VolumeSliderBloc(layerShell: shell);
    addTearDown(bloc.close);
    _requestSlider(bloc);
    await _settle();

    bloc.add(const VolumeSliderViewsRetained(<int>{999}));
    await _settle();

    expect(bloc.state.session, isNull);
    expect(bloc.state.sliderViewIds, isEmpty);
  });

  test('a missing retained tooltip view clears the session', () async {
    final shell = _FakeLayerShell();
    final bloc = OverlayTooltipBloc(layerShell: shell);
    addTearDown(bloc.close);
    _requestTooltip(bloc);
    await _settle();

    bloc.add(const OverlayTooltipViewsRetained(<int>{999}));
    await _settle();

    expect(bloc.state.session, isNull);
    expect(bloc.state.tooltipViewIds, isEmpty);
  });

  test(
    'closing a bloc tolerates an already-destroyed native surface',
    () async {
      final menuShell = _FakeLayerShell(throwOnClose: true);
      final menu = TrayMenuBloc(layerShell: menuShell);
      _requestMenu(menu);
      await _settle();

      final calendarShell = _FakeLayerShell(throwOnClose: true);
      final calendar = CalendarBloc(layerShell: calendarShell);
      _requestCalendar(calendar);
      await _settle();

      final sliderShell = _FakeLayerShell(throwOnClose: true);
      final slider = VolumeSliderBloc(layerShell: sliderShell);
      _requestSlider(slider);
      await _settle();

      final tooltipShell = _FakeLayerShell(throwOnClose: true);
      final tooltip = OverlayTooltipBloc(layerShell: tooltipShell);
      _requestTooltip(tooltip);
      await _settle();

      await expectLater(menu.close(), completes);
      await expectLater(calendar.close(), completes);
      await expectLater(slider.close(), completes);
      await expectLater(tooltip.close(), completes);
    },
  );
}
