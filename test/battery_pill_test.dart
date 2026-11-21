import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

Future<void> _pump(
  WidgetTester tester,
  BatteryStatus status, {
  VoidCallback? onPressed,
  int warn = 20,
  int critical = 10,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
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

  testWidgets('tooltip and semantics show time to empty', (tester) async {
    await _pump(
      tester,
      const BatteryStatus(
        capacity: 87,
        state: BatteryState.discharging,
        timeToEmpty: Duration(hours: 2, minutes: 14),
      ),
    );
    const label = 'Battery, Discharging 87%, 2h 14m remaining';
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(tester.widget<PillTooltip>(find.byType(PillTooltip)).label, label);
  });

  testWidgets('charging shows time to full and full hides it', (tester) async {
    await _pump(
      tester,
      const BatteryStatus(
        capacity: 40,
        charging: true,
        state: BatteryState.charging,
        timeToFull: Duration(hours: 2, minutes: 14),
      ),
    );
    expect(
      find.bySemanticsLabel('Battery, Charging 40%, 2h 14m to full'),
      findsOneWidget,
    );

    await _pump(
      tester,
      const BatteryStatus(
        capacity: 100,
        charging: true,
        state: BatteryState.full,
      ),
    );
    expect(find.bySemanticsLabel('Battery, Full 100%'), findsOneWidget);
  });

  testWidgets('duration formatting drops zero units', (tester) async {
    await _pump(
      tester,
      const BatteryStatus(
        capacity: 87,
        state: BatteryState.discharging,
        timeToEmpty: Duration(hours: 2),
      ),
    );
    expect(
      find.bySemanticsLabel('Battery, Discharging 87%, 2h remaining'),
      findsOneWidget,
    );

    await _pump(
      tester,
      const BatteryStatus(
        capacity: 87,
        state: BatteryState.discharging,
        timeToEmpty: Duration(minutes: 14),
      ),
    );
    expect(
      find.bySemanticsLabel('Battery, Discharging 87%, 14m remaining'),
      findsOneWidget,
    );
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
