import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/app.dart';
import 'package:trickster/src/settings/settings_theme.dart';

Future<void> _pump(WidgetTester tester, {VoidCallback? onClose}) {
  return tester.pumpWidget(
    TricksterLocalizationScope(
      child: MediaQuery(
        data: const MediaQueryData(size: Size(980, 720)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SettingsHome(onClose: onClose),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('settings shell paints the design language', (tester) async {
    await _pump(tester);

    expect(find.text('Trickster Settings'), findsOneWidget);
    expect(find.byType(SettingsCard), findsOneWidget);
    expect(
      find.text('Settings pages arrive in the following steps.'),
      findsOneWidget,
    );
  });

  testWidgets('the close control announces and fires', (tester) async {
    var closed = 0;
    await _pump(tester, onClose: () => closed++);

    expect(find.bySemanticsLabel('Close settings'), findsOneWidget);
    await tester.tap(find.byType(SettingsCloseButton));
    await tester.pump();
    expect(closed, 1);
  });
}
