import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:trickster/src/state/providers.dart';
import 'package:trickster/src/theme/accent.dart';

class _FixedCpu extends CpuController {
  @override
  CpuSample build() => const CpuSample(0.42);
}

class _FixedBattery extends BatteryController {
  @override
  BatteryStatus build() => const BatteryStatus(capacity: 87, charging: true);
}

class _FixedWorkspaces extends WorkspacesController {
  @override
  List<Workspace> build() => const [
    Workspace(id: '1', name: '1', focused: true),
    Workspace(id: '2', name: '2', urgent: true),
  ];
}

Future<void> _pumpStrip(
  WidgetTester tester, {
  BarSettings settings = const BarSettings(),
  Locale locale = const Locale('en', 'US'),
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => settings),
        cpuProvider.overrideWith(_FixedCpu.new),
        batteryProvider.overrideWith(_FixedBattery.new),
        workspacesProvider.overrideWith(_FixedWorkspaces.new),
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
    ProviderScope(
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
      ProviderScope(
        child: Localizations(
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
