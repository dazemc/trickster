import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/platform/layer_shell.dart';

void main() {
  test('the mode label multiplies the logical size by the scale', () {
    const scaled = LayerOutput(
      name: 'HDMI-A-1',
      width: 1920,
      height: 1080,
      scale: 2,
    );
    expect(scaled.modeLabel, '3840×2160');

    const unscaled = LayerOutput(name: 'eDP-1', width: 2560, height: 1440);
    expect(unscaled.modeLabel, '2560×1440');
  });

  test('global output position defaults to zero and is preserved', () {
    const unscaled = LayerOutput(name: 'eDP-1', width: 2560, height: 1440);
    expect(unscaled.x, 0);
    expect(unscaled.y, 0);

    const offset = LayerOutput(
      name: 'HDMI-A-1',
      x: 2560,
      y: -32,
      width: 1920,
      height: 1080,
    );
    expect(offset.x, 2560);
    expect(offset.y, -32);
  });
}
