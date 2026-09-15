import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/settings/settings_theme.dart';

Future<Color> _cardColor(WidgetTester tester, {required bool glass}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SettingsGlass(
        enabled: glass,
        child: const SettingsCard(child: Text('panel')),
      ),
    ),
  );
  final box =
      tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
          as BoxDecoration;
  return box.color!;
}

void main() {
  testWidgets('glass panels are translucent and fall back opaque', (
    tester,
  ) async {
    expect((await _cardColor(tester, glass: false)).a, 1.0);
    expect((await _cardColor(tester, glass: true)).a, lessThan(1.0));
  });
}
