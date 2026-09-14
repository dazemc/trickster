import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/blur_region.dart';

void main() {
  testWidgets('reports pill rects and clears them on unmount', (tester) async {
    final sent = <List<Rect>>[];
    final controller = BlurRegionController(onRegions: sent.add);
    addTearDown(controller.dispose);

    Widget tree({required int cards, Alignment alignment = Alignment.topLeft}) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: alignment,
          child: BlurRegionScope(
            controller: controller,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < cards; i++)
                  BlurRegion(
                    key: ValueKey<int>(i),
                    child: const SizedBox(width: 40, height: 10),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(tree(cards: 2));
    await tester.pump();
    expect(sent, isNotEmpty);
    // Each 40x10 card becomes ten one-pixel strips; the rounded ends are
    // narrower than the straight middle.
    expect(sent.last, hasLength(20));
    expect(sent.last.every((rect) => rect.height == 1), isTrue);
    final widths = sent.last.map((rect) => rect.width).toList();
    expect(widths.reduce((a, b) => a > b ? a : b), closeTo(40, 0.1));
    expect(widths.any((width) => width < 35), isTrue);

    await tester.pumpWidget(tree(cards: 2, alignment: Alignment.center));
    await tester.pump();
    expect(sent.last, hasLength(20));
    expect(sent.last.first.left, greaterThan(0));

    await tester.pumpWidget(tree(cards: 1, alignment: Alignment.center));
    await tester.pump();
    expect(sent.last, hasLength(10));

    await tester.pumpWidget(tree(cards: 0));
    await tester.pump();
    expect(sent.last, isEmpty);
  });

  testWidgets('without a scope pills keep rendering', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: BlurRegion(child: SizedBox(width: 10, height: 10)),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
