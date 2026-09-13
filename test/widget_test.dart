import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';
import 'package:trickster/src/theme/tokens.dart';

Future<void> _pumpClock(
  WidgetTester tester,
  Locale locale, {
  ClockFormat format = ClockFormat.locale,
}) {
  return tester.pumpWidget(
    MultiBlocProvider(
      providers: [BlocProvider(create: (_) => ClockBloc())],
      child: TricksterLocalizationScope(
        locale: locale,
        child: Center(
          child: ClockPill(
            accent: const WallpaperAccent(Color(0xffd0bcff)),
            format: format,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_US');
    await initializeDateFormatting('de_DE');
    await initializeDateFormatting('zh');
  });
  testWidgets('strip shows clock, cpu, battery, and workspaces', (
    tester,
  ) async {
    await pumpBarHarness(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('42%', findRichText: true), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('workspace-pip-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('workspace-pip-2')),
      findsOneWidget,
    );
  });

  testWidgets('disabled modules render nothing', (tester) async {
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock']),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CPU'), findsNothing);
    expect(find.text('42%', findRichText: true), findsNothing);
    expect(find.text('87%'), findsNothing);
    expect(find.byKey(const ValueKey<String>('workspace-pip-1')), findsNothing);
  });

  testWidgets('gpu cards follow the service list', (tester) async {
    tester.view.physicalSize = const Size(1600, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpBarHarness(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GpuPill), findsNothing);

    final gpu = tester.element(find.byType(TricksterBarStrip)).read<GpuBloc>();
    gpu.add(
      const GpuSampled([
        GpuLoad(id: 'card0', label: 'AMD0', usage: 0.4, history: [0.2, 0.4]),
        GpuLoad(id: 'card1', label: 'AMD1', usage: 0.8, history: [0.8]),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GpuPill), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('system-bar-gpu-card0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('system-bar-gpu-card1')),
      findsOneWidget,
    );
    expect(find.text('AMD0'), findsOneWidget);
    expect(find.text('AMD1'), findsOneWidget);

    gpu.add(const GpuSampled([]));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GpuPill), findsNothing);
  });

  testWidgets('strip tints captions with the settings accent', (tester) async {
    const accent = Color(0xffff0000);
    await pumpBarHarness(tester, settings: const BarSettings(accent: accent));
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

  testWidgets('clock options force 24h and 12h', (tester) async {
    await _pumpClock(
      tester,
      const Locale('en', 'US'),
      format: ClockFormat.hour24,
    );
    await tester.pump(const Duration(milliseconds: 500));
    var texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(texts, isNot(contains('AM')));
    expect(texts, isNot(contains('PM')));

    await _pumpClock(
      tester,
      const Locale('en', 'US'),
      format: ClockFormat.hour12,
    );
    await tester.pump(const Duration(milliseconds: 500));
    texts = tester
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
      TricksterLocalizationScope(
        locale: const Locale('en', 'US'),
        child: Center(
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

  testWidgets('clock follows the Chinese 24-hour cycle', (tester) async {
    await _pumpClock(tester, const Locale('zh'));
    await tester.pump(const Duration(milliseconds: 500));
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(texts, isNot(anyOf(contains('AM'), contains('PM'))));
    expect(texts, matches(RegExp(r'\b\d{1,2}:\d{2}\b')));
  });
}
