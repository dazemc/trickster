import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/overlay_view.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/state/calendar_bloc.dart';
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/state/tray_menu.dart';
import 'package:trickster/src/state/volume_slider_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

/// A tooltip bloc that can be handed a session without going through the
/// native surface path, so the view wiring can be tested on its own.
class _TooltipBloc extends OverlayTooltipBloc {
  _TooltipBloc() : super(layerShell: SilentLayerShell());

  void open(int viewId, String label) {
    emit(
      OverlayTooltipState(
        session: OverlayTooltipSession(
          viewId: viewId,
          itemId: 'item',
          label: label,
          accent: const WallpaperAccent(Color(0xffd0bcff)),
          click: const Offset(20, 8),
          side: SystemBarSide.top,
          thickness: 32,
        ),
        tooltipViewIds: {viewId},
      ),
    );
  }

  void ownWithoutSession(int viewId) {
    emit(OverlayTooltipState(tooltipViewIds: {viewId}));
  }
}

/// Counts how often a view's strip is built; a strip whose overlay state did
/// not change is never handed a new widget, so its count stays put.
class _StripSpy extends StatefulWidget {
  const _StripSpy({required this.name, required this.builds});

  final String name;
  final Map<String, int> builds;

  @override
  State<_StripSpy> createState() => _StripSpyState();
}

class _StripSpyState extends State<_StripSpy> {
  @override
  Widget build(BuildContext context) {
    widget.builds[widget.name] = (widget.builds[widget.name] ?? 0) + 1;
    return Text('strip-${widget.name}');
  }
}

Future<void> _pumpSlots(
  WidgetTester tester, {
  required Map<String, int> builds,
  required OverlayTooltipBloc tooltip,
  required int viewA,
  required int viewB,
}) {
  final shell = SilentLayerShell();
  return tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TrayMenuBloc>(
          create: (_) => TrayMenuBloc(layerShell: shell),
        ),
        BlocProvider<CalendarBloc>(
          create: (_) => CalendarBloc(layerShell: shell),
        ),
        BlocProvider<VolumeSliderBloc>(
          create: (_) => VolumeSliderBloc(layerShell: shell),
        ),
        BlocProvider<OverlayTooltipBloc>.value(value: tooltip),
      ],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            SizedBox(
              width: 300,
              height: 100,
              child: OverlayViewSlot(
                key: const ValueKey<String>('view-a'),
                viewId: viewA,
                strip: (context) => _StripSpy(name: 'a', builds: builds),
              ),
            ),
            SizedBox(
              width: 300,
              height: 100,
              child: OverlayViewSlot(
                key: const ValueKey<String>('view-b'),
                viewId: viewB,
                strip: (context) => _StripSpy(name: 'b', builds: builds),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a tooltip on one view leaves another view strip untouched', (
    tester,
  ) async {
    final builds = <String, int>{};
    final tooltip = _TooltipBloc();
    addTearDown(tooltip.close);
    await _pumpSlots(
      tester,
      builds: builds,
      tooltip: tooltip,
      viewA: 100,
      viewB: 200,
    );
    expect(builds, <String, int>{'a': 1, 'b': 1});

    final a = find.byKey(const ValueKey<String>('view-a'));
    final b = find.byKey(const ValueKey<String>('view-b'));

    tooltip.open(100, 'Tooltip A');
    await tester.pump();
    await tester.pump();

    // View A sees its own tooltip; view B keeps painting its idle strip.
    expect(
      find.descendant(of: a, matching: find.text('Tooltip A')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: b, matching: find.text('Tooltip A')),
      findsNothing,
    );
    expect(
      find.descendant(of: a, matching: find.text('strip-a')),
      findsNothing,
    );
    expect(
      find.descendant(of: b, matching: find.text('strip-b')),
      findsOneWidget,
    );
    expect(builds['b'], 1, reason: 'view B strip rebuilt on view A hover');

    // Retargeting the same tooltip never reaches the other view either.
    tooltip.open(100, 'Tooltip A again');
    await tester.pump();
    await tester.pump();
    expect(
      find.descendant(of: a, matching: find.text('Tooltip A again')),
      findsOneWidget,
    );
    expect(builds['b'], 1, reason: 'view B strip rebuilt on view A retarget');
  });

  testWidgets('an owned overlay view without a session paints no strip', (
    tester,
  ) async {
    final builds = <String, int>{};
    final tooltip = _TooltipBloc();
    addTearDown(tooltip.close);
    await _pumpSlots(
      tester,
      builds: builds,
      tooltip: tooltip,
      viewA: 100,
      viewB: 200,
    );

    tooltip.ownWithoutSession(100);
    await tester.pump();
    await tester.pump();

    final a = find.byKey(const ValueKey<String>('view-a'));
    expect(find.descendant(of: a, matching: find.text('strip-a')), findsNothing);
    expect(builds['a'], 1);
    expect(builds['b'], 1);
  });
}
