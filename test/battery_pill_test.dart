import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/theme/accent.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

Future<void> _pump(WidgetTester tester, BatteryStatus status) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: BatteryPill(accent: _accent, status: status)),
    ),
  );
}

void main() {
  testWidgets('charging draws the bolt inside the gauge cell', (tester) async {
    await _pump(tester, const BatteryStatus(capacity: 87, charging: true));
    expect(find.byKey(BatteryPill.gaugeKey), paints..path());
  });

  testWidgets('discharging leaves the gauge cell without a bolt', (
    tester,
  ) async {
    await _pump(tester, const BatteryStatus(capacity: 87));
    expect(find.byKey(BatteryPill.gaugeKey), isNot(paints..path()));
  });
}
