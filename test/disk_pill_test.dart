import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/disk.dart';
import 'package:trickster/src/bar/format.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/disk.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));
const _sample = DiskSample(
  path: '/',
  usedBytes: 620 * 1024 * 1024 * 1024,
  totalBytes: 1024 * 1024 * 1024 * 1024,
  freeBytes: 404 * 1024 * 1024 * 1024,
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
  DiskSample sample, {
  MeterCaptionSource captionSource = MeterCaptionSource.generic,
  String? captionPrefix,
  bool vertical = false,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        child: Center(
          child: DiskPill(
            accent: _accent,
            sample: sample,
            captionSource: captionSource,
            captionPrefix: captionPrefix,
            vertical: vertical,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('IEC byte formatting uses binary units', () {
    expect(formatIecBytes(0), '0 B');
    expect(formatIecBytes(1024), '1 KiB');
    expect(formatIecBytes(1536 * 1024), '1.5 MiB');
    expect(formatIecBytes(620 * 1024 * 1024 * 1024), '620 GiB');
  });

  testWidgets('disk pill shows DISK and the used percentage', (tester) async {
    await _pump(tester, _sample);
    expect(find.text('DISK'), findsOneWidget);
    expect(find.text('61%', findRichText: true), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), findsNothing);

    final tooltip = tester.widget<PillTooltip>(find.byType(PillTooltip));
    expect(tooltip.label, contains('620 GiB'));
    expect(tooltip.label, contains('1 TiB'));
    expect(tooltip.label, contains('404 GiB'));
  });

  testWidgets('a missing reading renders nothing', (tester) async {
    await _pump(tester, const DiskSample());
    expect(find.byType(LoadMeter), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('custom caption replaces DISK', (tester) async {
    await _pump(
      tester,
      _sample,
      captionSource: MeterCaptionSource.custom,
      captionPrefix: 'ROOT',
    );
    expect(find.text('ROOT'), findsOneWidget);
    expect(find.text('DISK'), findsNothing);
  });

  testWidgets('used-fraction thresholds tint the value', (tester) async {
    Future<void> pump(int used, {Color? warnColor, Color? criticalColor}) {
      return tester.pumpWidget(
        withOverlayBlocs(
          TricksterLocalizationScope(
            child: Center(
              child: DiskPill(
                accent: _accent,
                sample: DiskSample(
                  path: '/',
                  usedBytes: used,
                  totalBytes: 100,
                  freeBytes: 100 - used,
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
    expect(_valueColor(tester, '96%'), ShellTelemetryColors.danger);

    await pump(85);
    expect(_valueColor(tester, '85%'), ShellTelemetryColors.warning);

    await pump(36);
    expect(_valueColor(tester, '36%'), isNot(ShellTelemetryColors.warning));

    await pump(
      96,
      warnColor: _accent.color,
      criticalColor: const Color(0xff00ff00),
    );
    expect(_valueColor(tester, '96%'), const Color(0xff00ff00));

    await pump(85, warnColor: _accent.color);
    expect(_valueColor(tester, '85%'), _accent.color);
  });

  testWidgets('vertical layout stacks DISK over the reading', (tester) async {
    await _pump(tester, _sample, vertical: true);
    expect(find.text('DISK'), findsOneWidget);
    expect(find.text('61%'), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), findsNothing);
  });
}
