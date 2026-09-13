import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';

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

  group('output selection', () {
    const outputs = <LayerOutput>[
      LayerOutput(name: 'eDP-1', viewId: 0, width: 1920, height: 1080),
      LayerOutput(name: 'HDMI-A-1', viewId: 1, width: 2560, height: 1440),
    ];

    test('every output hosts a strip when no connectors are named', () {
      expect(hostedOutputs(outputs, const OutputsConfig()), outputs);
    });

    test('named connectors select exactly those outputs', () {
      final hosted = hostedOutputs(
        outputs,
        const OutputsConfig(connectors: ['HDMI-A-1']),
      );
      expect(hosted.map((output) => output.name), ['HDMI-A-1']);
      expect(hosted.single.viewId, 1);
    });

    test('unknown connectors select nothing', () {
      expect(
        hostedOutputs(outputs, const OutputsConfig(connectors: ['DP-1'])),
        isEmpty,
      );
    });
  });
}
