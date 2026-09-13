import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/bar/tray_tooltip.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/state/tray_tooltip.dart';
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

Future<void> _pumpButton(
  WidgetTester tester,
  TrayTooltipController controller,
) {
  return tester.pumpWidget(
    TricksterLocalizationScope(
      child: TrayTooltipScope(
        notifier: controller,
        child: const Center(
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

void main() {
  testWidgets('retargets one surface as hover moves between items', (
    tester,
  ) async {
    final shell = _FakeLayerShell();
    final controller = TrayTooltipController(layerShell: shell);
    addTearDown(controller.dispose);

    await controller.show(
      barViewId: 0,
      itemId: 'a',
      label: 'First',
      accent: _accent,
      click: const Offset(100, 16),
      side: SystemBarSide.top,
      thickness: 32,
    );
    await controller.show(
      barViewId: 0,
      itemId: 'b',
      label: 'Second',
      accent: _accent,
      click: const Offset(200, 16),
      side: SystemBarSide.top,
      thickness: 32,
    );
    expect(shell.opened, <int>[0]);
    expect(shell.closed, isEmpty);
    expect(controller.session?.label, 'Second');
    expect(controller.session?.viewId, 100);

    await controller.close(itemId: 'a');
    expect(controller.isOpen, isTrue);
    await controller.close(itemId: 'b');
    expect(controller.isOpen, isFalse);
    expect(shell.closed, <int>[100]);
  });

  testWidgets('a failed surface open stays closed without throwing', (
    tester,
  ) async {
    final shell = _FakeLayerShell()..failOpen = true;
    final controller = TrayTooltipController(layerShell: shell);
    addTearDown(controller.dispose);

    await controller.show(
      barViewId: 0,
      itemId: 'a',
      label: 'First',
      accent: _accent,
      click: const Offset(100, 16),
      side: SystemBarSide.top,
      thickness: 32,
    );
    expect(controller.isOpen, isFalse);
    expect(shell.shown, isEmpty);
  });

  testWidgets('hover intent shows the tooltip and exit hides it', (
    tester,
  ) async {
    final shell = _FakeLayerShell();
    final controller = TrayTooltipController(layerShell: shell);
    addTearDown(controller.dispose);
    await _pumpButton(tester, controller);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(TrayItemButton)));
    await tester.pump();
    expect(controller.isOpen, isFalse);

    await tester.pump(const Duration(milliseconds: 600));
    expect(shell.opened, <int>[0]);
    expect(shell.shown, <int>[100]);
    expect(controller.session?.itemId, 'item');
    expect(controller.session?.label, 'qBittorrent');

    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(controller.isOpen, isFalse);
    expect(shell.closed, <int>[100]);
  });

  testWidgets('the pill sits below the bar, centered on the item', (
    tester,
  ) async {
    const session = TrayTooltipSession(
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
          child: TrayTooltipSurface(session: session),
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

  testWidgets('the pill clamps inside the output edge', (tester) async {
    const session = TrayTooltipSession(
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
          child: TrayTooltipSurface(session: session),
        ),
      ),
    );
    final right = tester.getBottomRight(find.text('qBittorrent')).dx;
    expect(right, lessThanOrEqualTo(800));
  });
}
