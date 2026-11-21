import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/ram.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/ram.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));
const _sample = RamSample(
  usedBytes: 4 * 1024 * 1024,
  totalBytes: 8 * 1024 * 1024,
  history: [0.25, 0.5],
);

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
  RamSample sample, {
  MeterCaptionSource captionSource = MeterCaptionSource.generic,
  String? captionPrefix,
  bool sparkline = true,
  bool vertical = false,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        child: Center(
          child: RamPill(
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
  testWidgets('ram pill shows RAM and the used percentage', (tester) async {
    await _pump(tester, _sample);
    expect(find.text('RAM'), findsOneWidget);
    expect(find.text('50%', findRichText: true), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), paints..path());
  });

  testWidgets('a missing reading renders nothing, never a zero percent', (
    tester,
  ) async {
    await _pump(tester, const RamSample());
    expect(find.byType(LoadMeter), findsNothing);
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets('thresholds and their colors tint the reading', (tester) async {
    Future<void> pump({
      required int used,
      Color? warnColor,
      Color? criticalColor,
    }) {
      return tester.pumpWidget(
        withOverlayBlocs(
          TricksterLocalizationScope(
            child: Center(
              child: RamPill(
                accent: _accent,
                sample: RamSample(
                  usedBytes: used,
                  totalBytes: 100,
                  history: [used / 100],
                ),
                warnColor: warnColor,
                criticalColor: criticalColor,
              ),
            ),
          ),
        ),
      );
    }

    await pump(used: 97);
    expect(_percentColor(tester, '97%'), ShellTelemetryColors.danger);

    await pump(used: 88);
    expect(_percentColor(tester, '88%'), ShellTelemetryColors.warning);

    await pump(used: 42);
    expect(_percentColor(tester, '42%'), isNot(ShellTelemetryColors.warning));

    await pump(
      used: 97,
      warnColor: _accent.color,
      criticalColor: const Color(0xff00ff00),
    );
    expect(_percentColor(tester, '97%'), const Color(0xff00ff00));

    await pump(used: 88, warnColor: _accent.color);
    expect(_percentColor(tester, '88%'), _accent.color);
  });

  testWidgets('a custom prefix replaces the RAM caption', (tester) async {
    await _pump(
      tester,
      _sample,
      captionSource: MeterCaptionSource.custom,
      captionPrefix: 'MEM',
    );
    expect(find.text('MEM'), findsOneWidget);
    expect(find.text('RAM'), findsNothing);
  });

  testWidgets('a custom source without a prefix falls back to RAM', (
    tester,
  ) async {
    await _pump(tester, _sample, captionSource: MeterCaptionSource.custom);
    expect(find.text('RAM'), findsOneWidget);
  });

  testWidgets('sparkline and vertical layout follow the options', (
    tester,
  ) async {
    await _pump(tester, _sample, sparkline: false);
    expect(find.byKey(LoadMeter.sparklineKey), findsNothing);

    await _pump(tester, _sample, vertical: true);
    expect(find.text('RAM'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), findsOneWidget);
  });
}
