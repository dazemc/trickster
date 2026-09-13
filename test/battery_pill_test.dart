import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

Future<void> _pump(
  WidgetTester tester,
  BatteryStatus status, {
  VoidCallback? onPressed,
  int warn = 20,
  int critical = 10,
}) {
  return tester.pumpWidget(
    TricksterLocalizationScope(
      child: Center(
        child: BatteryPill(
          accent: _accent,
          status: status,
          onPressed: onPressed ?? () {},
          warn: warn,
          critical: critical,
        ),
      ),
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

  testWidgets('card announces charge state and capacity', (tester) async {
    await _pump(tester, const BatteryStatus(capacity: 87, charging: true));
    expect(find.bySemanticsLabel('Battery, Charging 87%'), findsOneWidget);
    await _pump(tester, const BatteryStatus(capacity: 87));
    expect(find.bySemanticsLabel('Battery, Discharging 87%'), findsOneWidget);
  });

  testWidgets('low capacity tints the gauge and percent', (tester) async {
    await _pump(
      tester,
      const BatteryStatus(capacity: 8),
      warn: 20,
      critical: 10,
    );
    final text = tester.widget<Text>(find.text('8%'));
    expect(text.style?.color, ShellTelemetryColors.danger);

    await _pump(tester, const BatteryStatus(capacity: 15));
    final warned = tester.widget<Text>(find.text('15%'));
    expect(warned.style?.color, ShellTelemetryColors.warning);

    await _pump(tester, const BatteryStatus(capacity: 15, charging: true));
    final charging = tester.widget<Text>(find.text('15%'));
    expect(charging.style?.color, ShellText.systemBarValue.color);
  });

  testWidgets('tapping the card fires the action', (tester) async {
    var pressed = 0;
    await _pump(
      tester,
      const BatteryStatus(capacity: 87),
      onPressed: () => pressed++,
    );
    await tester.tap(find.bySemanticsLabel('Battery, Discharging 87%'));
    await tester.pump();
    expect(pressed, 1);
  });
}
