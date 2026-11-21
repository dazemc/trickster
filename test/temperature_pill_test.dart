import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/temperature.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/temperature.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));
const _cpu = TemperatureSample(
  celsius: 36,
  label: 'Tctl',
  chip: 'k10temp',
  isCpu: true,
  history: [34, 36],
);

Color? _valueColor(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(
    find.byWidgetPredicate(
      (candidate) =>
          candidate is Text && candidate.textSpan?.toPlainText() == text,
    ),
  );
  return widget.textSpan?.style?.color;
}

Future<void> _pump(
  WidgetTester tester,
  TemperatureSample sample, {
  MeterCaptionSource captionSource = MeterCaptionSource.generic,
  String? captionPrefix,
  bool sparkline = true,
  bool vertical = false,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        child: Center(
          child: TemperaturePill(
            accent: _accent,
            sample: sample,
            captionSource: captionSource,
            captionPrefix: captionPrefix,
            sparkline: sparkline,
            vertical: vertical,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('temperature pill shows CPU and Celsius', (tester) async {
    await _pump(tester, _cpu);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('36°C', findRichText: true), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), paints..path());
  });

  testWidgets('a non-CPU fallback uses TEMP', (tester) async {
    await _pump(
      tester,
      const TemperatureSample(celsius: 45, chip: 'nvme', history: [45]),
    );
    expect(find.text('TEMP'), findsOneWidget);
    expect(find.text('CPU'), findsNothing);
    expect(find.text('45°C', findRichText: true), findsOneWidget);
  });

  testWidgets('a missing sensor renders nothing, never 0°C', (tester) async {
    await _pump(tester, const TemperatureSample());
    expect(find.byType(LoadMeter), findsNothing);
    expect(find.textContaining('0°C'), findsNothing);
  });

  testWidgets('custom caption replaces the generic tag', (tester) async {
    await _pump(
      tester,
      _cpu,
      captionSource: MeterCaptionSource.custom,
      captionPrefix: 'SoC',
    );
    expect(find.text('SoC'), findsOneWidget);
    expect(find.text('CPU'), findsNothing);
  });

  testWidgets('Celsius thresholds tint the value', (tester) async {
    Future<void> pump(int celsius, {Color? warnColor, Color? criticalColor}) {
      return tester.pumpWidget(
        withOverlayBlocs(
          TricksterLocalizationScope(
            child: Center(
              child: TemperaturePill(
                accent: _accent,
                sample: TemperatureSample(
                  celsius: celsius.toDouble(),
                  isCpu: true,
                  history: [celsius.toDouble()],
                ),
                warnColor: warnColor,
                criticalColor: criticalColor,
              ),
            ),
          ),
        ),
      );
    }

    await pump(96);
    expect(_valueColor(tester, '96°C'), ShellTelemetryColors.danger);

    await pump(85);
    expect(_valueColor(tester, '85°C'), ShellTelemetryColors.warning);

    await pump(36);
    expect(_valueColor(tester, '36°C'), isNot(ShellTelemetryColors.warning));

    await pump(
      96,
      warnColor: _accent.color,
      criticalColor: const Color(0xff00ff00),
    );
    expect(_valueColor(tester, '96°C'), const Color(0xff00ff00));

    await pump(85, warnColor: _accent.color);
    expect(_valueColor(tester, '85°C'), _accent.color);
  });

  testWidgets('sparkline and vertical layout follow the options', (
    tester,
  ) async {
    await _pump(tester, _cpu, sparkline: false);
    expect(find.byKey(LoadMeter.sparklineKey), findsNothing);

    await _pump(tester, _cpu, vertical: true);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('36°C'), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), findsOneWidget);
  });
}
