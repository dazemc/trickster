import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/brightness.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/brightness.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));
const _sample = BrightnessSample(
  current: 63,
  max: 100,
  actual: 63,
  device: 'intel_backlight',
  type: 'firmware',
  scale: 'linear',
);

Future<void> _pump(
  WidgetTester tester,
  BrightnessSample sample, {
  bool vertical = false,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        child: Center(
          child: BrightnessPill(
            accent: _accent,
            sample: sample,
            vertical: vertical,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('brightness pill shows BRI and the driver percentage', (
    tester,
  ) async {
    await _pump(tester, _sample);
    expect(find.text('BRI'), findsOneWidget);
    expect(find.text('63%', findRichText: true), findsOneWidget);
    final meter = tester.widget<LoadMeter>(find.byType(LoadMeter));
    expect(meter.valueColor, isNull);
    expect(meter.sparkline, isFalse);
  });

  testWidgets('tooltip names the backlight device', (tester) async {
    await _pump(tester, _sample);
    final tooltip = tester.widget<PillTooltip>(find.byType(PillTooltip));
    expect(tooltip.label, 'Brightness 63% · intel_backlight');
  });

  testWidgets('tooltip falls back when the device has no name', (tester) async {
    await _pump(tester, const BrightnessSample(current: 40, max: 100));
    final tooltip = tester.widget<PillTooltip>(find.byType(PillTooltip));
    expect(tooltip.label, 'Brightness 40%');
  });

  testWidgets('semantics announce the caption and percent', (tester) async {
    await _pump(tester, _sample);
    final handle = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('BRI'))
          .getSemanticsData()
          .value,
      '63%',
    );
    handle.dispose();
  });

  testWidgets('a missing reading renders nothing, never 0%', (tester) async {
    await _pump(tester, const BrightnessSample());
    expect(find.byType(LoadMeter), findsNothing);
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets('zero brightness stays visible as 0%', (tester) async {
    await _pump(
      tester,
      const BrightnessSample(current: 0, max: 100, device: 'panel'),
    );
    expect(find.byType(LoadMeter), findsOneWidget);
    expect(find.text('0%', findRichText: true), findsOneWidget);
  });

  testWidgets('vertical strips stack the caption over the reading', (
    tester,
  ) async {
    await _pump(tester, _sample, vertical: true);
    final meter = tester.widget<LoadMeter>(find.byType(LoadMeter));
    expect(meter.vertical, isTrue);
    expect(meter.stacked, isTrue);
    expect(find.text('BRI'), findsOneWidget);
    expect(find.text('63%', findRichText: true), findsOneWidget);
  });
}
