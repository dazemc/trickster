import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trickster/src/bar/calendar.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/state/calendar_bloc.dart';
import 'package:trickster/src/state/capabilities_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

class _RecordingLayerShell extends LayerShell {
  _RecordingLayerShell()
    : super(channel: const MethodChannel('test/trickster'));

  final opened = <int>[];
  final shown = <int>[];
  final closed = <int>[];
  var nextViewId = 100;

  @override
  Future<int?> openMenuSurface({
    required int barViewId,
    required String side,
  }) async {
    opened.add(barViewId);
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

CalendarRequested _request({
  DateTime? month,
  Offset click = const Offset(120, 10),
  SystemBarSide side = SystemBarSide.top,
}) {
  return CalendarRequested(
    barViewId: 0,
    month: month ?? DateTime(2026, 1, 15),
    accent: _accent,
    click: click,
    side: side,
    thickness: 32,
  );
}

/// Pumps the surface the way the app's overlay entry does: driven by the
/// bloc state, so month changes and dismissal flow through the same path.
Future<void> _pumpSurface(
  WidgetTester tester,
  CalendarBloc calendar, {
  Offset click = const Offset(120, 10),
  SystemBarSide side = SystemBarSide.top,
  bool hostedBlur = true,
  bool hostBlur = true,
}) async {
  calendar.add(_request(click: click, side: side));
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => SettingsBloc(
            BarSettings(appearance: AppearanceOptions(blur: hostedBlur)),
          ),
        ),
        BlocProvider(
          create: (_) =>
              CapabilitiesBloc(initial: Capabilities(blur: hostBlur)),
        ),
        BlocProvider<CalendarBloc>.value(value: calendar),
      ],
      child: TricksterLocalizationScope(
        locale: const Locale('en', 'US'),
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: BlocBuilder<CalendarBloc, CalendarState>(
            builder: (context, state) {
              final session = state.session;
              if (session == null) {
                return const SizedBox.shrink();
              }
              return CalendarSurface(session: session);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The panel's own background decoration (the first box under the key).
BoxDecoration _panelDecoration(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byKey(const ValueKey<String>('calendar-panel')),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_US');
  });

  test('opening creates and shows an overlay surface for the month', () async {
    final shell = _RecordingLayerShell();
    final calendar = CalendarBloc(layerShell: shell);
    addTearDown(calendar.close);

    calendar.add(_request(month: DateTime(2026, 1, 15)));
    final open = await calendar.stream.firstWhere((state) => state.isOpen);

    expect(shell.opened, [0]);
    expect(shell.shown, [100]);
    expect(open.session!.viewId, 100);
    expect(open.session!.month, DateTime(2026, 1));
    expect(open.isCalendarView(100), isTrue);
  });

  test('dismissing closes the surface and forgets the session', () async {
    final shell = _RecordingLayerShell();
    final calendar = CalendarBloc(layerShell: shell);
    addTearDown(calendar.close);
    calendar.add(_request());
    await calendar.stream.firstWhere((state) => state.isOpen);

    calendar.add(const CalendarDismissed());
    final closed = await calendar.stream.firstWhere((state) => !state.isOpen);

    expect(shell.closed, [100]);
    expect(closed.session, isNull);
    expect(closed.isCalendarView(100), isTrue);
  });

  test('changing the month keeps the same surface', () async {
    final shell = _RecordingLayerShell();
    final calendar = CalendarBloc(layerShell: shell);
    addTearDown(calendar.close);
    calendar.add(_request());
    await calendar.stream.firstWhere((state) => state.isOpen);

    calendar.add(const CalendarMonthShifted(1));
    final next = await calendar.stream.firstWhere(
      (state) => state.session?.month == DateTime(2026, 2),
    );

    expect(next.session!.viewId, 100);
    expect(shell.opened, hasLength(1));
    expect(shell.closed, isEmpty);
  });

  test('retaining views drops the ids the engine no longer owns', () async {
    final shell = _RecordingLayerShell();
    final calendar = CalendarBloc(layerShell: shell);
    addTearDown(calendar.close);
    calendar.add(_request());
    await calendar.stream.firstWhere((state) => state.isOpen);

    calendar.add(const CalendarViewsRetained(<int>{7}));
    final retained = await calendar.stream.firstWhere(
      (state) => !state.isCalendarView(100),
    );

    expect(retained.session, isNotNull);
  });

  testWidgets('the surface renders the month grid and marks today', (
    tester,
  ) async {
    final calendar = CalendarBloc(layerShell: _RecordingLayerShell());
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar);

    expect(find.text('January 2026'), findsOneWidget);
    // Monday-first: January 2026 starts on Thursday, so the grid opens on
    // December 29 and runs six full weeks.
    expect(
      find.byKey(const ValueKey<String>('calendar-day-2025-12-29')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('calendar-day-2026-01-15')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('calendar-day-2026-02-08')),
      findsOneWidget,
    );
  });

  testWidgets('the arrows move the month', (tester) async {
    final calendar = CalendarBloc(layerShell: _RecordingLayerShell());
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar);

    await tester.tap(find.byKey(const ValueKey<String>('calendar-next')));
    await tester.pumpAndSettle();
    expect(find.text('February 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('calendar-prev')));
    await tester.tap(find.byKey(const ValueKey<String>('calendar-prev')));
    await tester.pumpAndSettle();
    expect(find.text('December 2025'), findsOneWidget);
  });

  testWidgets('escape dismisses the calendar', (tester) async {
    final shell = _RecordingLayerShell();
    final calendar = CalendarBloc(layerShell: shell);
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar);
    expect(find.text('January 2026'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('January 2026'), findsNothing);
    expect(calendar.state.session, isNull);
    expect(shell.closed, [100]);
  });

  testWidgets('tapping outside dismisses the calendar', (tester) async {
    final shell = _RecordingLayerShell();
    final calendar = CalendarBloc(layerShell: shell);
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar);
    expect(find.text('January 2026'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('January 2026'), findsNothing);
    expect(shell.closed, [100]);
  });

  testWidgets('tapping a day keeps the calendar open', (tester) async {
    final shell = _RecordingLayerShell();
    final calendar = CalendarBloc(layerShell: shell);
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar);

    await tester.tap(
      find.byKey(const ValueKey<String>('calendar-day-2026-01-15')),
    );
    await tester.pumpAndSettle();

    expect(find.text('January 2026'), findsOneWidget);
    expect(shell.closed, isEmpty);
  });

  testWidgets('a clock near the right edge keeps the panel on screen', (
    tester,
  ) async {
    final calendar = CalendarBloc(layerShell: _RecordingLayerShell());
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar, click: const Offset(790, 10));

    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('calendar-panel')),
    );
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(32));
  });

  testWidgets('a bottom strip opens the panel above itself', (tester) async {
    final calendar = CalendarBloc(layerShell: _RecordingLayerShell());
    addTearDown(calendar.close);
    await _pumpSurface(
      tester,
      calendar,
      click: const Offset(400, 588),
      side: SystemBarSide.bottom,
    );

    final rect = tester.getRect(
      find.byKey(const ValueKey<String>('calendar-panel')),
    );
    expect(rect.bottom, lessThanOrEqualTo(600 - 32));
    expect(rect.top, greaterThanOrEqualTo(0));
  });

  testWidgets('the panel goes translucent with hosted blur', (tester) async {
    final calendar = CalendarBloc(layerShell: _RecordingLayerShell());
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar);

    final decoration = _panelDecoration(tester);
    expect(decoration.color, isNull);
    expect(decoration.gradient, isNotNull);
  });

  testWidgets('the panel keeps the accent fill when hosted blur is off', (
    tester,
  ) async {
    final calendar = CalendarBloc(layerShell: _RecordingLayerShell());
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar, hostedBlur: false);

    final decoration = _panelDecoration(tester);
    expect(decoration.color, _accent.cardFill());
    expect(decoration.gradient, isNull);
  });

  testWidgets('the panel keeps the accent fill without host blur support', (
    tester,
  ) async {
    final calendar = CalendarBloc(layerShell: _RecordingLayerShell());
    addTearDown(calendar.close);
    await _pumpSurface(tester, calendar, hostBlur: false);

    final decoration = _panelDecoration(tester);
    expect(decoration.color, _accent.cardFill());
    expect(decoration.gradient, isNull);
  });

  testWidgets('tapping the clock opens the calendar', (tester) async {
    final shell = _RecordingLayerShell();
    final calendar = CalendarBloc(layerShell: shell);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          // Owned by the tree, so their timers die with it.
          BlocProvider(create: (_) => ClockBloc()),
          BlocProvider<CalendarBloc>(create: (_) => calendar),
          BlocProvider(create: (_) => OverlayTooltipBloc(layerShell: shell)),
        ],
        child: TricksterLocalizationScope(
          locale: const Locale('en', 'US'),
          child: const Center(child: ClockPill(accent: _accent)),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(ClockPill));
    await tester.pumpAndSettle();

    expect(shell.opened, [tester.view.viewId]);
    expect(calendar.state.isOpen, isTrue);
  });
}
