import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/overlay_view.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/state/bar_menu_bloc.dart';
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

/// A bar menu bloc that can be handed a session without going through the
/// native surface path, so view ownership can be tested on its own.
class _BarMenuBloc extends BarMenuBloc {
  _BarMenuBloc() : super(layerShell: SilentLayerShell());

  void open(int viewId) {
    emit(
      BarMenuState(
        session: BarMenuSession(
          viewId: viewId,
          accent: const WallpaperAccent(Color(0xffd0bcff)),
          click: const Offset(20, 8),
          side: SystemBarSide.top,
          thickness: 32,
        ),
        barMenuViewIds: {viewId},
      ),
    );
  }

  void ownWithoutSession(int viewId) {
    emit(BarMenuState(barMenuViewIds: {viewId}));
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
  BarMenuBloc? barMenu,
}) {
  final shell = SilentLayerShell();
  return tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TrayMenuBloc>(
          create: (_) => TrayMenuBloc(layerShell: shell),
        ),
        if (barMenu == null)
          BlocProvider<BarMenuBloc>(
            create: (_) => BarMenuBloc(layerShell: shell),
          )
        else
          BlocProvider<BarMenuBloc>.value(value: barMenu),
        BlocProvider<CalendarBloc>(
          create: (_) => CalendarBloc(layerShell: shell),
        ),
        BlocProvider<VolumeSliderBloc>(
          create: (_) => VolumeSliderBloc(layerShell: shell),
        ),
        BlocProvider<OverlayTooltipBloc>.value(value: tooltip),
      ],
      child: TricksterLocalizationScope(
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Column(
                  children: [
                    SizedBox(
                      width: 300,
                      height: 100,
                      child: OverlayViewSlot(
                        key: const ValueKey<String>('view-a'),
                        viewId: viewA,
                        strip: (context) =>
                            _StripSpy(name: 'a', builds: builds),
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      height: 100,
                      child: OverlayViewSlot(
                        key: const ValueKey<String>('view-b'),
                        viewId: viewB,
                        strip: (context) =>
                            _StripSpy(name: 'b', builds: builds),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    expect(
      find.descendant(of: a, matching: find.text('strip-a')),
      findsNothing,
    );
    expect(builds['a'], 1);
    expect(builds['b'], 1);
  });

  testWidgets('a bar menu belongs only to its own view', (tester) async {
    final builds = <String, int>{};
    final tooltip = _TooltipBloc();
    final barMenu = _BarMenuBloc();
    addTearDown(tooltip.close);
    addTearDown(barMenu.close);
    await _pumpSlots(
      tester,
      builds: builds,
      tooltip: tooltip,
      barMenu: barMenu,
      viewA: 100,
      viewB: 200,
    );

    barMenu.open(100);
    await tester.pump();
    await tester.pumpAndSettle();

    final a = find.byKey(const ValueKey<String>('view-a'));
    final b = find.byKey(const ValueKey<String>('view-b'));
    // The menu is a fullscreen overlay on view A's surface: it replaces A's
    // strip while B keeps painting its own.
    expect(find.text('Trickster Settings'), findsOneWidget);
    expect(
      find.descendant(of: a, matching: find.text('strip-a')),
      findsNothing,
    );
    expect(
      find.descendant(of: b, matching: find.text('strip-b')),
      findsOneWidget,
    );
    expect(builds['b'], 1, reason: 'view B rebuilt on view A bar menu');

    // Ownership starts before the session exists: the native surface is
    // already covering the output during teardown, so it must not flash a
    // strip.
    barMenu.ownWithoutSession(100);
    await tester.pump();
    expect(barMenu.state.session, isNull);
    expect(
      find.descendant(of: a, matching: find.text('strip-a')),
      findsNothing,
    );
    expect(builds['b'], 1);
  });
}
