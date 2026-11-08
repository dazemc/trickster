import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:trickster/src/bar/opencode.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/opencode.dart';
import 'package:trickster/src/state/opencode_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

OpencodeUsage _usage({
  double rolling = 26,
  double weekly = 40,
  double monthly = 20,
  bool limited = false,
  DateTime? resetsAt,
  OpencodeSessionUsage? session,
}) {
  return OpencodeUsage(
    available: true,
    workspaceName: 'Default',
    rolling: OpencodeMeterUsage(
      percent: rolling,
      limited: limited,
      resetsAt: resetsAt,
    ),
    weekly: OpencodeMeterUsage(percent: weekly),
    monthly: OpencodeMeterUsage(percent: monthly),
    session: session,
  );
}

void main() {
  testWidgets('the headline window shows its remaining percent', (
    tester,
  ) async {
    await _pump(tester, _usage());
    expect(find.text('74%'), findsOneWidget);

    await _pump(tester, _usage(), meter: OpencodeMeter.weekly);
    expect(find.text('60%'), findsOneWidget);

    await _pump(tester, _usage(), meter: OpencodeMeter.monthly);
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('the session cost joins the headline when enabled', (
    tester,
  ) async {
    const session = OpencodeSessionUsage(id: 'ses_1', cost: 0.25);
    await _pump(tester, _usage(session: session));
    expect(find.text('0.25 USD'), findsOneWidget);

    await _pump(tester, _usage(session: session), showCost: false);
    expect(find.text('0.25 USD'), findsNothing);
  });

  testWidgets('a zero-cost session adds no cost text', (tester) async {
    await _pump(
      tester,
      _usage(session: const OpencodeSessionUsage(id: 'ses_1')),
    );
    expect(find.textContaining('USD'), findsNothing);
  });

  testWidgets('a limited window tints the remaining percent', (tester) async {
    await _pump(tester, _usage(rolling: 100, limited: true));
    final text = tester.widget<Text>(
      find.byWidgetPredicate(
        (candidate) =>
            candidate is Text && candidate.textSpan?.toPlainText() == '0%',
      ),
    );
    expect(text.textSpan?.style?.color, ShellTelemetryColors.danger);
  });

  testWidgets('unavailable and missing readings render nothing', (
    tester,
  ) async {
    await _pump(tester, const OpencodeUsage());
    expect(find.byType(OpencodePill), findsOneWidget);
    expect(find.byKey(OpencodePill.terminalIconKey), findsNothing);

    await _pump(
      tester,
      const OpencodeUsage(available: true, weekly: OpencodeMeterUsage(percent: 1)),
    );
    expect(find.byKey(OpencodePill.terminalIconKey), findsNothing);
  });

  testWidgets('vertical strips stack the mark over the percent', (tester) async {
    await _pump(tester, _usage(), vertical: true);
    expect(find.byKey(OpencodePill.terminalIconKey), findsOneWidget);
    expect(find.text('74%'), findsOneWidget);
  });

  testWidgets('the hover label carries every window and the session', (
    tester,
  ) async {
    final resetsAt = DateTime.fromMillisecondsSinceEpoch(1794121576000);
    await _pump(
      tester,
      _usage(
        resetsAt: resetsAt,
        session: const OpencodeSessionUsage(
          id: 'ses_1',
          cost: 0.25,
          input: 100,
          output: 20,
          reasoning: 5,
          cacheRead: 900,
          cacheWrite: 10,
        ),
      ),
    );
    final label = tester.widget<PillTooltip>(find.byType(PillTooltip)).label;
    final time = DateFormat.Hm('en').format(resetsAt.toLocal());
    expect(label, startsWith('OpenCode · Rolling 26% used, 74% left'));
    expect(label, contains('resets $time'));
    expect(label, contains('Weekly 40%'));
    expect(label, contains('Monthly 20%'));
    expect(label, contains('1.0k tokens'));
    expect(label, contains('0.25 USD'));
  });

  testWidgets('a disabled module builds no pill and no bloc', (tester) async {
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock']),
      settle: const Duration(milliseconds: 500),
    );
    expect(find.byType(OpencodePill), findsNothing);
  });

  testWidgets('an enabled module renders the pill in the strip', (
    tester,
  ) async {
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'opencode']),
      settle: const Duration(milliseconds: 500),
    );
    expect(find.byType(OpencodePill), findsOneWidget);
    expect(find.text('74%'), findsOneWidget);
  });

  testWidgets('the strip hides the pill without a live server', (tester) async {
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'opencode']),
      opencodeBuilder: OpencodeBloc.new,
      settle: const Duration(milliseconds: 500),
    );
    expect(find.byType(OpencodePill), findsNothing);
  });

  test('token counts compact only past a thousand', () {
    expect(formatOpencodeTokens(999), '999');
    expect(formatOpencodeTokens(1000), '1.0k');
    expect(formatOpencodeTokens(12345), '12.3k');
    expect(formatOpencodeTokens(123456), '123k');
    expect(formatOpencodeTokens(1234567), '1.2M');
  });

  test('costs keep sub-cent precision', () {
    expect(formatOpencodeCost(0.25), '0.25');
    expect(formatOpencodeCost(0.1234), '0.12');
    expect(formatOpencodeCost(0.0123), '0.012');
    expect(formatOpencodeCost(0.002686), '0.0027');
    expect(formatOpencodeCost(12.5), '12.50');
  });
}

Future<void> _pump(
  WidgetTester tester,
  OpencodeUsage usage, {
  OpencodeMeter meter = OpencodeMeter.rolling,
  bool showCost = true,
  bool vertical = false,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        locale: const Locale('en', 'US'),
        child: Center(
          child: OpencodePill(
            accent: _accent,
            usage: usage,
            meter: meter,
            showCost: showCost,
            vertical: vertical,
            onPressed: () {},
          ),
        ),
      ),
    ),
  );
}
