import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster_bar/src/layout/system_bar.dart';

void main() {
  group('OutputsConfig.stripWithin', () {
    const output = Rect.fromLTWH(0, 0, 1920, 1080);

    test('top strip hugs the top edge', () {
      const config = OutputsConfig(side: SystemBarSide.top, thickness: 32);
      expect(config.stripWithin(output), const Rect.fromLTWH(0, 0, 1920, 32));
    });

    test('bottom strip hugs the bottom edge', () {
      const config = OutputsConfig(side: SystemBarSide.bottom, thickness: 40);
      expect(
        config.stripWithin(output),
        const Rect.fromLTWH(0, 1040, 1920, 40),
      );
    });

    test('left strip hugs the left edge', () {
      const config = OutputsConfig(side: SystemBarSide.left, thickness: 48);
      expect(config.stripWithin(output), const Rect.fromLTWH(0, 0, 48, 1080));
    });

    test('right strip hugs the right edge', () {
      const config = OutputsConfig(side: SystemBarSide.right, thickness: 48);
      expect(
        config.stripWithin(output),
        const Rect.fromLTWH(1872, 0, 48, 1080),
      );
    });

    test('thickness never swallows the output', () {
      const config = OutputsConfig(side: SystemBarSide.top, thickness: 100000);
      expect(config.stripWithin(output).height, 540);
    });

    test('hidden side yields an empty strip', () {
      const config = OutputsConfig(side: SystemBarSide.hidden, thickness: 0);
      expect(config.stripWithin(output), Rect.zero);
    });
  });
}
