import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

void main() {
  test('series maps to pixels with the newest sample at the right edge', () {
    const size = Size(38, 14);
    final step = size.width / (CpuSample.capacity - 1);
    final points = sparklinePoints(
      const [0.0, 0.5, 1.0],
      size,
      CpuSample.capacity,
    );
    expect(points.length, 3);
    expect(points[0].dx, closeTo(size.width - 2 * step, 1e-9));
    expect(points[1].dx, closeTo(size.width - step, 1e-9));
    expect(points[2].dx, size.width);
    expect(points[0].dy, size.height);
    expect(points[1].dy, closeTo(size.height / 2, 1e-9));
    expect(points[2].dy, 0);
    expect(sparklinePoints(const [], size, CpuSample.capacity), isEmpty);
    expect(
      sparklinePoints(const [0.5], Size.zero, CpuSample.capacity),
      isEmpty,
    );
  });

  testWidgets('pill paints the sparkline once two samples exist', (
    tester,
  ) async {
    await _pump(tester, const CpuSample(0.42, history: [0.1, 0.42]));
    expect(find.byKey(LoadMeter.sparklineKey), paints..path());
  });

  testWidgets('pill leaves the sparkline blank with one sample', (
    tester,
  ) async {
    await _pump(tester, const CpuSample(0.42, history: [0.42]));
    expect(find.byKey(LoadMeter.sparklineKey), isNot(paints..path()));
  });

  testWidgets('caption stays the generic CPU tag while the name is data', (
    tester,
  ) async {
    await _pump(tester, const CpuSample(0.42, name: 'AMD Ryzen 9 5950X'));
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('AMD Ryzen 9 5950X'), findsNothing);
  });

  testWidgets('vertical shows the caption and percent', (tester) async {
    await tester.pumpWidget(
      withOverlayBlocs(
        const TricksterLocalizationScope(
          child: Center(
            child: CpuPill(
              accent: _accent,
              sample: CpuSample(0.42),
              vertical: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), findsOneWidget);
  });

  testWidgets('a custom prefix replaces the caption', (tester) async {
    await _pump(
      tester,
      const CpuSample(0.42),
      captionSource: MeterCaptionSource.custom,
      captionPrefix: 'CPU0',
    );
    expect(find.text('CPU0'), findsOneWidget);
    expect(find.text('CPU'), findsNothing);

    // Custom without a prefix falls back to the generic caption.
    await _pump(
      tester,
      const CpuSample(0.42),
      captionSource: MeterCaptionSource.custom,
    );
    expect(find.text('CPU'), findsOneWidget);
  });

  testWidgets('a vertical caption ellipsizes inside a thin strip', (
    tester,
  ) async {
    await tester.pumpWidget(
      withOverlayBlocs(
        TricksterLocalizationScope(
          child: Center(
            child: SizedBox(
              width: 40,
              child: CpuPill(
                accent: _accent,
                sample: const CpuSample(
                  0.42,
                  name: 'AMD Ryzen 9 5950X 16-Core Processor',
                ),
                captionSource: MeterCaptionSource.device,
                vertical: true,
              ),
            ),
          ),
        ),
      ),
    );
    // No overflow: the caption gives way instead of pushing the pill apart.
    final label = tester.widget<Text>(
      find.text('AMD Ryzen 9 5950X 16-Core Processor'),
    );
    expect(label.overflow, TextOverflow.ellipsis);
  });

  testWidgets('device captions and thresholds follow the options', (
    tester,
  ) async {
    await _pump(
      tester,
      const CpuSample(0.42, name: 'AMD Ryzen 9 5950X'),
      captionSource: MeterCaptionSource.device,
    );
    expect(find.text('AMD Ryzen 9 5950X'), findsOneWidget);
    expect(find.text('CPU'), findsNothing);

    await _pump(tester, const CpuSample(0.97));
    expect(_percentColor(tester, '97%'), ShellTelemetryColors.danger);

    await _pump(tester, const CpuSample(0.88));
    expect(_percentColor(tester, '88%'), ShellTelemetryColors.warning);

    await _pump(tester, const CpuSample(0.42));
    expect(_percentColor(tester, '42%'), isNot(ShellTelemetryColors.warning));
  });
}

Color? _percentColor(WidgetTester tester, String text) {
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
  CpuSample sample, {
  MeterCaptionSource captionSource = MeterCaptionSource.generic,
  String? captionPrefix,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        child: Center(
          child: CpuPill(
            accent: _accent,
            sample: sample,
            captionSource: captionSource,
            captionPrefix: captionPrefix,
          ),
        ),
      ),
    ),
  );
}
