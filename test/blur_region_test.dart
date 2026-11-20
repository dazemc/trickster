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

  testWidgets('unchanged bounds reuse cached scanlines and send once', (
    tester,
  ) async {
    final sent = <List<Rect>>[];
    final controller = BlurRegionController(onRegions: sent.add);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BlurRegionScope(
          controller: controller,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              BlurRegion(child: SizedBox(width: 40, height: 10)),
              BlurRegion(child: SizedBox(width: 40, height: 10)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(sent, hasLength(1));
    final builds = controller.debugRegionBuilds;
    expect(builds, 2);

    for (var i = 0; i < 30; i++) {
      if (i.isEven) {
        controller.refresh();
      } else {
        controller.resend();
      }
      await tester.pump();
    }
    expect(sent, hasLength(1));
    expect(controller.debugRegionBuilds, builds);
  });

  testWidgets('moving one pill rebuilds one provider and sends one list', (
    tester,
  ) async {
    final sent = <List<Rect>>[];
    final controller = BlurRegionController(onRegions: sent.add);
    addTearDown(controller.dispose);

    Widget tree({required double secondLeft}) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: BlurRegionScope(
          controller: controller,
          child: Stack(
            children: [
              const Positioned(
                left: 0,
                top: 0,
                child: BlurRegion(child: SizedBox(width: 40, height: 10)),
              ),
              Positioned(
                left: secondLeft,
                top: 20,
                child: const BlurRegion(child: SizedBox(width: 40, height: 10)),
              ),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(tree(secondLeft: 0));
    await tester.pump();
    expect(sent, hasLength(1));
    final builds = controller.debugRegionBuilds;
    expect(builds, 2);

    await tester.pumpWidget(tree(secondLeft: 20));
    await tester.pump();
    expect(sent, hasLength(2));
    expect(controller.debugRegionBuilds, builds + 1);
    expect(sent.last, hasLength(20));
  });

  testWidgets('dispose before the scheduled flush is safe', (tester) async {
    final sent = <List<Rect>>[];
    final controller = BlurRegionController(onRegions: sent.add);
    controller.register('card', () => const Rect.fromLTWH(0, 0, 40, 10));
    controller.dispose();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('degenerate bounds produce one rect or none', (tester) async {
    final sent = <List<Rect>>[];
    final controller = BlurRegionController(onRegions: sent.add);
    addTearDown(controller.dispose);

    controller.register('tiny', () => const Rect.fromLTWH(0, 0, 1, 1));
    controller.register('flat', () => const Rect.fromLTWH(0, 20, 40, 1));
    controller.register('missing', () => null);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(sent, hasLength(1));
    expect(sent.last, hasLength(2));
    expect(sent.last.every((rect) => rect.height == 1), isTrue);

    controller.unregister('missing');
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(sent, hasLength(1));
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
