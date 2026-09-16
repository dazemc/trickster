import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

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
