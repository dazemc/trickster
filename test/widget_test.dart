import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trickster_bar/src/bar/bar.dart';
import 'package:trickster_bar/src/bar/clock.dart';
import 'package:trickster_bar/src/config/settings.dart';
import 'package:trickster_bar/src/layout/system_bar.dart';
import 'package:trickster_bar/src/services/battery.dart';
import 'package:trickster_bar/src/services/cpu.dart';
import 'package:trickster_bar/src/services/workspaces.dart';
import 'package:trickster_bar/src/state/providers.dart';
import 'package:trickster_bar/src/theme/accent.dart';

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
