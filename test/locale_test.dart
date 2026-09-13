import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/locale.dart';

Future<void> _pumpScope(WidgetTester tester, {Locale? locale}) async {
  await tester.pumpWidget(
    TricksterLocalizationScope(
      locale: locale,
      child: Builder(
        builder: (context) => Text(context.l10n.batteryTitle),
      ),
    ),
  );
}

void main() {
  testWidgets('explicit locale resolves and exposes localized strings', (
    tester,
  ) async {
    Locale? resolved;
    await tester.pumpWidget(
      TricksterLocalizationScope(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            resolved = Localizations.localeOf(context);
            return Text(context.l10n.batteryTitle);
          },
        ),
      ),
    );
    expect(resolved, const Locale('en'));
    expect(find.text('Battery'), findsOneWidget);
  });

  testWidgets('directionality follows the resolved locale', (tester) async {
    TextDirection? direction;
    await tester.pumpWidget(
      TricksterLocalizationScope(
        locale: const Locale('en'),
        child: Builder(
          builder: (context) {
            direction = Directionality.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(direction, TextDirection.ltr);
  });

  testWidgets('unsupported device locales fall back to English', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('xx')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await _pumpScope(tester);
    expect(find.text('Battery'), findsOneWidget);
  });

  testWidgets('explicit locale wins over the device locale list', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [
      Locale('de', 'DE'),
      Locale('xx'),
    ];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await _pumpScope(tester, locale: const Locale('en'));
    expect(find.text('Battery'), findsOneWidget);
  });
}
