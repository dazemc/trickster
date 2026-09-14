import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/backdrop_blur.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

double _topAlpha(WidgetTester tester) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.gradient is LinearGradient) {
      return (decoration.gradient! as LinearGradient).colors.first.a;
    }
  }
  fail('no gradient card found');
}

Future<void> _pump(WidgetTester tester, {bool? blur}) {
  const card = SystemBarCard(
    accent: _accent,
    child: Text('x', textDirection: TextDirection.ltr),
  );
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: blur == null ? card : BackdropBlur(enabled: blur, child: card),
      ),
    ),
  );
}

void main() {
  testWidgets('opaque fill when the host cannot blur', (tester) async {
    await _pump(tester);
    expect(_topAlpha(tester), closeTo(0.92, 0.001));
    await _pump(tester, blur: false);
    expect(_topAlpha(tester), closeTo(0.92, 0.001));
  });

  testWidgets('dark glass fill when the backdrop is blurred', (tester) async {
    await _pump(tester, blur: true);
    expect(_topAlpha(tester), closeTo(0.3, 0.001));
  });

  testWidgets('painted sheen rides the blurred fill only', (tester) async {
    await _pump(tester, blur: true);
    expect(find.byKey(SystemBarCard.sheenKey), findsOneWidget);
    await _pump(tester, blur: false);
    expect(find.byKey(SystemBarCard.sheenKey), findsNothing);
  });
}
