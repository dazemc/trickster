import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/theme/accent.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

void main() {
  testWidgets('gpu meter shows the label and percentage', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
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
    );
    expect(find.text('AMD0'), findsOneWidget);
    expect(find.text('42%', findRichText: true), findsOneWidget);
    expect(find.byKey(LoadMeter.sparklineKey), paints..path());
  });
}
