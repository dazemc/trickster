import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

Color? _percentColor(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(
    find.byWidgetPredicate(
      (candidate) =>
          candidate is Text && candidate.textSpan?.toPlainText() == text,
    ),
  );
  return widget.textSpan?.style?.color;
}

void main() {
  testWidgets('gpu meter shows the label and percentage', (tester) async {
    await tester.pumpWidget(
      withOverlayBlocs(
        const TricksterLocalizationScope(
          child: Center(
            child: GpuPill(
              accent: _accent,
              load: GpuLoad(
                id: 'card0',
                label: 'AMD0',
                usage: 0.42,
                history: [0.1, 0.42],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('AMD0'), findsOneWidget);
    expect(find.text('42%', findRichText: true), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), paints..path());
  });

  testWidgets('thresholds and their colors tint the reading', (tester) async {
    Future<void> pump({
      required double usage,
      double warn = 0.85,
      double critical = 0.95,
      Color? warnColor,
      Color? criticalColor,
    }) {
      return tester.pumpWidget(
        withOverlayBlocs(
          TricksterLocalizationScope(
            child: Center(
              child: GpuPill(
                accent: _accent,
                load: GpuLoad(
                  id: 'card0',
                  label: 'AMD0',
                  usage: usage,
                  history: [usage],
                ),
                warn: warn,
                critical: critical,
                warnColor: warnColor,
                criticalColor: criticalColor,
              ),
            ),
          ),
        ),
      );
    }

    await pump(usage: 0.97);
    expect(_percentColor(tester, '97%'), ShellTelemetryColors.danger);

    await pump(usage: 0.88);
    expect(_percentColor(tester, '88%'), ShellTelemetryColors.warning);

    await pump(usage: 0.42);
    expect(_percentColor(tester, '42%'), isNot(ShellTelemetryColors.warning));

    // Configured colors win over the defaults.
    await pump(
      usage: 0.97,
      warnColor: _accent.color,
      criticalColor: const Color(0xff00ff00),
    );
    expect(_percentColor(tester, '97%'), const Color(0xff00ff00));
    await pump(usage: 0.88, warnColor: _accent.color);
    expect(_percentColor(tester, '88%'), _accent.color);
  });

  testWidgets('a custom prefix replaces the caption', (tester) async {
    await tester.pumpWidget(
      withOverlayBlocs(
        const TricksterLocalizationScope(
          child: Center(
            child: GpuPill(
              accent: _accent,
              load: GpuLoad(
                id: 'card0',
                label: 'AMD0',
                usage: 0.42,
                history: [0.42],
              ),
              captionSource: MeterCaptionSource.custom,
              captionPrefix: 'GPU0',
            ),
          ),
        ),
      ),
    );
    expect(find.text('GPU0'), findsOneWidget);
    expect(find.text('AMD0'), findsNothing);
  });

  testWidgets('device caption source prefers the queried name', (tester) async {
    await tester.pumpWidget(
      withOverlayBlocs(
        const TricksterLocalizationScope(
          child: Center(
            child: GpuPill(
              accent: _accent,
              load: GpuLoad(
                id: 'card0',
                label: 'AMD0',
                name: 'NVIDIA GeForce RTX 4070 Ti',
                usage: 0.42,
                history: [0.42],
              ),
              captionSource: MeterCaptionSource.device,
            ),
          ),
        ),
      ),
    );
    expect(find.text('NVIDIA GeForce RTX 4070 Ti'), findsOneWidget);
    expect(find.text('AMD0'), findsNothing);
  });
}
