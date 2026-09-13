import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

const _workspaces = [
  Workspace(id: '1', name: '1', focused: true),
  Workspace(id: '2', name: '2', urgent: true),
];

Future<void> _pumpStrip(
  WidgetTester tester, {
  BarSettings settings = const BarSettings(),
  Locale locale = const Locale('en', 'US'),
}) async {
  // States are seeded via constructors, never via events: awaiting the
  // real event loop (pumpEventQueue) inside FakeAsync hangs forever.
  // Providers own their blocs (create, not value): provider disposal closes
  // blocs unawaited, while awaiting close() in FakeAsync deadlocks on the
  // bloc's internal event pipeline.
  return tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SettingsBloc(settings)),
        BlocProvider(create: (_) => SessionBloc()),
        BlocProvider(create: (_) => OutputsBloc()),
        BlocProvider(create: (_) => ClockBloc()),
        BlocProvider(
          create: (_) => CpuBloc(initial: const CpuSample(0.42)),
        ),
        BlocProvider(
          create: (_) => BatteryBloc(
            initial: const BatteryStatus(capacity: 87, charging: true),
          ),
        ),
        BlocProvider(
          create: (_) => WorkspacesBloc(
            initial: const WorkspacesState(_workspaces),
          ),
        ),
      ],
      child: Localizations(
        locale: locale,
        delegates: const [GlobalWidgetsLocalizations.delegate],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: TricksterBarStrip(side: SystemBarSide.top),
        ),
      ),
    ),
  );
}

Future<void> _pumpClock(WidgetTester tester, Locale locale) {
  return tester.pumpWidget(
    MultiBlocProvider(
      providers: [BlocProvider(create: (_) => ClockBloc())],
      child: Localizations(
        locale: locale,
        delegates: const [GlobalWidgetsLocalizations.delegate],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: ClockPill(accent: WallpaperAccent(Color(0xffd0bcff))),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_US');
    await initializeDateFormatting('de_DE');
  });
  testWidgets('strip shows clock, cpu, battery, and workspaces', (
    tester,
  ) async {
    await _pumpStrip(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CPU 42%', findRichText: true), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('disabled modules render nothing', (tester) async {
    await _pumpStrip(
      tester,
      settings: const BarSettings(modules: ['clock']),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CPU 42%', findRichText: true), findsNothing);
    expect(find.text('87%'), findsNothing);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('strip tints captions with the settings accent', (tester) async {
    const accent = Color(0xffff0000);
    await _pumpStrip(
      tester,
      settings: const BarSettings(accent: accent),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final expected = const WallpaperAccent(accent).captionColor();
    final caption = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.style?.fontSize == ShellText.systemBarCaption.fontSize,
      ),
    );
    expect(caption.style?.color, expected);
  });

  testWidgets('clock follows the US 12-hour cycle', (tester) async {
    await _pumpClock(tester, const Locale('en', 'US'));
    await tester.pump(const Duration(milliseconds: 500));
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(texts, anyOf(contains('AM'), contains('PM')));
  });

  testWidgets('action card announces, taps, and rings on focus', (
    tester,
  ) async {
    var pressed = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en', 'US'),
        delegates: const [GlobalWidgetsLocalizations.delegate],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: TricksterActionCard(
            accent: const WallpaperAccent(Color(0xffd0bcff)),
            label: 'Test action',
            onPressed: () => pressed++,
            focusNode: node,
            child: const Text('go'),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Test action'), findsOneWidget);
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(pressed, 1);
    node.requestFocus();
    // Focus notification is delivered asynchronously behind the full
    // ancestor chain; the first pump applies focus, the second rebuilds.
    await tester.pump();
    await tester.pump();
    final ringed = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).border != null,
    );
    expect(ringed, findsOneWidget);
  });

  test('bar date caption follows the locale', () {
    final fixed = DateTime(2026, 9, 12);
    expect(formatBarDate(fixed, 'en_US'), 'Sep 12');
    expect(formatBarDate(fixed, 'de_DE'), contains('Sept'));
  });

  testWidgets('clock follows the German 24-hour cycle', (tester) async {
    await _pumpClock(tester, const Locale('de', 'DE'));
    await tester.pump(const Duration(milliseconds: 500));
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(texts, isNot(anyOf(contains('AM'), contains('PM'))));
    expect(texts, matches(RegExp(r'\b\d{2}:\d{2}\b')));
  });
}
