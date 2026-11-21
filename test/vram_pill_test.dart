import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/vram.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));
const _load = GpuLoad(
  id: 'card0',
  label: 'AMD0',
  name: 'AMD Radeon RX 7900',
  usage: 0.4,
  history: [0.4],
  memoryUsedBytes: 500,
  memoryTotalBytes: 1000,
  memoryHistory: [0.25, 0.5],
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
  GpuLoad load, {
  int index = 0,
  int count = 1,
  MeterCaptionSource captionSource = MeterCaptionSource.generic,
  String? captionPrefix,
  bool sparkline = true,
  bool vertical = false,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        child: Center(
          child: VramPill(
            accent: _accent,
            load: load,
            index: index,
            count: count,
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
  testWidgets('vram pill shows VRAM and the memory percentage', (tester) async {
    await _pump(tester, _load);
    expect(find.text('VRAM'), findsOneWidget);
    expect(find.text('50%', findRichText: true), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), paints..path());
  });

  testWidgets('a GPU without memory renders nothing', (tester) async {
    await _pump(tester, const GpuLoad(id: 'card0', label: 'AMD0', usage: 0.4));
    expect(find.byType(LoadMeter), findsNothing);
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets('multiple GPUs suffix the generic caption', (tester) async {
    await _pump(tester, _load, index: 1, count: 2);
    expect(find.text('VRAM1'), findsOneWidget);
    expect(find.text('VRAM'), findsNothing);
  });

  testWidgets('device and custom captions replace the generic tag', (
    tester,
  ) async {
    await _pump(tester, _load, captionSource: MeterCaptionSource.device);
    expect(find.text('AMD Radeon RX 7900'), findsOneWidget);
    expect(find.text('VRAM'), findsNothing);

    await _pump(
      tester,
      _load,
      captionSource: MeterCaptionSource.custom,
      captionPrefix: 'GVRAM',
    );
    expect(find.text('GVRAM'), findsOneWidget);
    expect(find.text('VRAM'), findsNothing);
  });

  testWidgets('thresholds and their colors tint the memory reading', (
    tester,
  ) async {
    Future<void> pump({required int used, Color? warnColor}) {
      return tester.pumpWidget(
        withOverlayBlocs(
          TricksterLocalizationScope(
            child: Center(
              child: VramPill(
                accent: _accent,
                load: GpuLoad(
                  id: 'card0',
                  label: 'AMD0',
                  memoryUsedBytes: used,
                  memoryTotalBytes: 100,
                  memoryHistory: [used / 100],
                ),
                warnColor: warnColor,
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

    await pump(used: 88, warnColor: _accent.color);
    expect(_percentColor(tester, '88%'), _accent.color);
  });

  testWidgets('sparkline and vertical layout follow the options', (
    tester,
  ) async {
    await _pump(tester, _load, sparkline: false);
    expect(find.byKey(LoadMeter.sparklineKey), findsNothing);

    await _pump(tester, _load, vertical: true);
    expect(find.text('VRAM'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), findsOneWidget);
  });
}
