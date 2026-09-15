import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/overlay_tooltip.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/theme/accent.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

const _item = SystemTrayItem(
  id: 'item',
  title: 'qBittorrent',
  status: SystemTrayStatus.active,
  iconName: 'qbit',
  iconThemePath: '',
  iconPixmap: null,
  menuAvailable: true,
  primaryOpensMenu: false,
);

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell() : super(channel: const MethodChannel('test/trickster'));

  final opened = <int>[];
  final shown = <int>[];
  final closed = <int>[];
  var nextViewId = 100;
  var failOpen = false;

  @override
  Future<int?> openTooltipSurface({
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
  Future<void> showTooltipSurface({required int viewId}) async {
    shown.add(viewId);
  }

  @override
  Future<void> closeTooltipSurface({required int viewId}) async {
    closed.add(viewId);
  }
}

Future<void> _pumpButton(WidgetTester tester, OverlayTooltipBloc bloc) {
  return tester.pumpWidget(
    BlocProvider<OverlayTooltipBloc>.value(
      value: bloc,
      child: const TricksterLocalizationScope(
        child: Center(
          child: TrayItemButton(
            accent: _accent,
            item: _item,
            onActivate: _noop,
          ),
        ),
      ),
    ),
  );
}

void _noop(SystemTrayItem item, Offset position) {}

OverlayTooltipRequested _request(
  String itemId,
  String label, {
  Offset click = const Offset(100, 16),
  SystemBarSide side = SystemBarSide.top,
}) {
  return OverlayTooltipRequested(
    barViewId: 0,
    itemId: itemId,
    label: label,
    accent: _accent,
    click: click,
    side: side,
    thickness: 32,
  );
}

void main() {
  test('retargets one surface as hover moves between items', () async {
    final shell = _FakeLayerShell();
    final bloc = OverlayTooltipBloc(layerShell: shell);
    addTearDown(bloc.close);

    bloc.add(_request('a', 'First'));
    bloc.add(_request('b', 'Second', click: const Offset(200, 16)));
    await pumpEventQueue();
    expect(shell.opened, <int>[0]);
    expect(shell.closed, isEmpty);
    expect(bloc.state.session?.label, 'Second');
    expect(bloc.state.session?.viewId, 100);

    bloc.add(const OverlayTooltipDismissed(itemId: 'a'));
    await pumpEventQueue();
    expect(bloc.state.isOpen, isTrue);
    bloc.add(const OverlayTooltipDismissed(itemId: 'b'));
    await pumpEventQueue();
    expect(bloc.state.isOpen, isFalse);
    expect(shell.closed, <int>[100]);
  });

  test('a failed surface open stays closed without throwing', () async {
    final shell = _FakeLayerShell()..failOpen = true;
    final bloc = OverlayTooltipBloc(layerShell: shell);
    addTearDown(bloc.close);

    bloc.add(_request('a', 'First'));
    await pumpEventQueue();
    expect(bloc.state.isOpen, isFalse);
    expect(shell.shown, isEmpty);
  });

  testWidgets('hover intent shows the tooltip and exit hides it', (
    tester,
  ) async {
    final shell = _FakeLayerShell();
    final bloc = OverlayTooltipBloc(layerShell: shell);
    addTearDown(bloc.close);
    await _pumpButton(tester, bloc);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(TrayItemButton)));
    await tester.pump();
    expect(bloc.state.isOpen, isFalse);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(shell.opened, <int>[0]);
    expect(shell.shown, <int>[100]);
    expect(bloc.state.session?.itemId, 'item');
    expect(bloc.state.session?.label, 'qBittorrent');

    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    await tester.pump();
    expect(bloc.state.isOpen, isFalse);
    expect(shell.closed, <int>[100]);
  });

  testWidgets('the pill sits below the bar, centered on the item', (
    tester,
  ) async {
    const session = OverlayTooltipSession(
      viewId: 100,
      itemId: 'item',
      label: 'qBittorrent',
      accent: _accent,
      click: Offset(400, 16),
      side: SystemBarSide.top,
      thickness: 32,
    );
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(800, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: OverlayTooltipSurface(session: session),
        ),
      ),
    );
    final center = tester.getCenter(find.text('qBittorrent'));
    expect(center.dx, closeTo(400, 0.5));
    expect(
      tester.getTopLeft(find.text('qBittorrent')).dy,
      greaterThanOrEqualTo(36),
    );
    final pill = tester.getSize(find.byType(SystemBarCard));
    expect(pill.width, lessThan(200));
    expect(pill.height, lessThan(32));
  });

  testWidgets('side bars place the pill beside the bar', (tester) async {
    const session = OverlayTooltipSession(
      viewId: 100,
      itemId: 'item',
      label: 'qBittorrent',
      accent: _accent,
      click: Offset(20, 300),
      side: SystemBarSide.left,
      thickness: 72,
    );
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(800, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: OverlayTooltipSurface(session: session),
        ),
      ),
    );
    expect(tester.getTopLeft(find.byType(SystemBarCard)).dx, 76);
    expect(tester.getCenter(find.byType(SystemBarCard)).dy, closeTo(300, 0.5));
  });

  testWidgets('the pill clamps inside the output edge', (tester) async {
    const session = OverlayTooltipSession(
      viewId: 100,
      itemId: 'item',
      label: 'qBittorrent',
      accent: _accent,
      click: Offset(799, 16),
      side: SystemBarSide.top,
      thickness: 32,
    );
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(800, 600)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: OverlayTooltipSurface(session: session),
        ),
      ),
    );
    final right = tester.getBottomRight(find.text('qBittorrent')).dx;
    expect(right, lessThanOrEqualTo(800));
  });
}
