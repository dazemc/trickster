import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/theme/accent.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell() : super(channel: const MethodChannel('test/trickster'));

  final opened = <int>[];
  final shown = <int>[];
  final closed = <int>[];
  var nextViewId = 100;

  @override
  Future<int?> openTooltipSurface({
    required int barViewId,
    required String side,
  }) async {
    opened.add(barViewId);
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

Future<void> _pump(
  WidgetTester tester,
  OverlayTooltipBloc bloc, {
  CpuSample sample = const CpuSample(0.42),
}) {
  return tester.pumpWidget(
    BlocProvider<OverlayTooltipBloc>.value(
      value: bloc,
      child: TricksterLocalizationScope(
        child: StripGeometry(
          side: SystemBarSide.top,
          thickness: 32,
          child: Center(
            child: CpuPill(accent: _accent, sample: sample),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('pill hover shows a detail tooltip and hides on exit', (
    tester,
  ) async {
    final shell = _FakeLayerShell();
    final bloc = OverlayTooltipBloc(layerShell: shell);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(CpuPill)));
    await tester.pump();
    expect(bloc.state.isOpen, isFalse);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(shell.opened, <int>[tester.view.viewId]);
    expect(bloc.state.session?.label, 'CPU 42%');
    expect(shell.shown, <int>[100]);

    // Hide-on-exit is the same controller path the tray tooltip tests cover;
    // the mouse tracker delivers exits on frames this test cannot pin down.
  });

  testWidgets('a live label update retargets the open tooltip', (tester) async {
    final shell = _FakeLayerShell();
    final bloc = OverlayTooltipBloc(layerShell: shell);
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(CpuPill)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(bloc.state.session?.label, 'CPU 42%');

    // Rebuilding the pill with a new sample updates the open tooltip.
    await _pump(tester, bloc, sample: const CpuSample(0.77));
    await tester.pump();
    expect(bloc.state.session?.label, 'CPU 77%');
    expect(shell.opened, hasLength(1));
  });
}
