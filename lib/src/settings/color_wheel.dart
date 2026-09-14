import 'dart:math' as math;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../locale.dart';
import '../theme/motion.dart';
import 'color_format.dart';
import 'settings_theme.dart';

/// Ported from Denial's `hsv_color_wheel.dart`: a hue/saturation disc for
/// the accent color, with pointer, keyboard, and screen-reader paths.
class HsvColorWheel extends StatefulWidget {
  const HsvColorWheel({
    required this.color,
    required this.onChanged,
    this.semanticsLabel,
    super.key,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final String? semanticsLabel;

  @override
  State<HsvColorWheel> createState() => _HsvColorWheelState();
}

class _HsvColorWheelState extends State<HsvColorWheel> {
  static const double _hueStep = 3.0;
  static const double _saturationStep = 0.04;

  final FocusNode _focusNode = FocusNode(debugLabel: 'hsv-color-wheel');
  var _focused = false;

  HSVColor get _hsv => HSVColor.fromColor(widget.color);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _select(Offset position, Size size) {
    final center = size.center(Offset.zero);
    final vector = position - center;
    final radius = size.shortestSide / 2.0;
    if (radius <= 0.0 || vector.distance > radius) {
      return;
    }
    final hue =
        (math.atan2(vector.dy, vector.dx) * 180.0 / math.pi + 360.0) % 360.0;
    final saturation = (vector.distance / radius).clamp(0.0, 1.0);
    widget.onChanged(
      HSVColor.fromAHSV(1.0, hue, saturation, _hsv.value).toColor(),
    );
  }

  void _adjust({double hue = 0.0, double saturation = 0.0}) {
    final current = _hsv;
    widget.onChanged(
      current
          .withHue((current.hue + hue + 360.0) % 360.0)
          .withSaturation((current.saturation + saturation).clamp(0.0, 1.0))
          .toColor(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hex = formatOpaqueColorHex(widget.color);
    final l10n = context.l10n;
    return Semantics(
      excludeSemantics: true,
      slider: true,
      label: widget.semanticsLabel ?? l10n.settingsColorWheelSemanticsLabel,
      value: hex,
      increasedValue: l10n.settingsColorWheelNextHue,
      decreasedValue: l10n.settingsColorWheelPreviousHue,
      onIncrease: () => _adjust(hue: _hueStep),
      onDecrease: () => _adjust(hue: -_hueStep),
      child: FocusableActionDetector(
        focusNode: _focusNode,
        mouseCursor: SystemMouseCursors.precise,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft):
              _ColorWheelAdjustmentIntent(hue: -_hueStep),
          SingleActivator(LogicalKeyboardKey.arrowRight):
              _ColorWheelAdjustmentIntent(hue: _hueStep),
          SingleActivator(LogicalKeyboardKey.arrowDown):
              _ColorWheelAdjustmentIntent(saturation: -_saturationStep),
          SingleActivator(LogicalKeyboardKey.arrowUp):
              _ColorWheelAdjustmentIntent(saturation: _saturationStep),
        },
        actions: <Type, Action<Intent>>{
          _ColorWheelAdjustmentIntent:
              CallbackAction<_ColorWheelAdjustmentIntent>(
                onInvoke: (intent) {
                  _adjust(hue: intent.hue, saturation: intent.saturation);
                  return null;
                },
              ),
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size.square(constraints.biggest.shortestSide);
            return Center(
              child: RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    _focusNode.requestFocus();
                    _select(details.localPosition, size);
                  },
                  onPanStart: (details) {
                    _focusNode.requestFocus();
                    _select(details.localPosition, size);
                  },
                  onPanUpdate: (details) =>
                      _select(details.localPosition, size),
                  child: AnimatedContainer(
                    duration: Motion.pill,
                    curve: Motion.standard,
                    width: size.width,
                    height: size.height,
                    padding: EdgeInsets.all(_focused ? 3.0 : 4.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _focused ? widget.color : SettingsColors.outline,
                        width: _focused ? 2.0 : 1.0,
                      ),
                    ),
                    child: CustomPaint(
                      painter: HsvColorWheelPainter(
                        color: widget.color,
                        shadowColor: const Color(0x66000000),
                        indicatorColor: SettingsColors.background,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class HsvColorWheelPainter extends CustomPainter {
  const HsvColorWheelPainter({
    required this.color,
    required this.shadowColor,
    required this.indicatorColor,
  });

  final Color color;
  final Color shadowColor;
  final Color indicatorColor;

  static const List<Color> _hues = <Color>[
    // The mathematical RGB gamut stops, not interface tokens.
    Color(0xffff0000),
    Color(0xffffff00),
    Color(0xff00ff00),
    Color(0xff00ffff),
    Color(0xff0000ff),
    Color(0xffff00ff),
    Color(0xffff0000),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final hsv = HSVColor.fromColor(color);

    canvas
      ..save()
      ..clipPath(Path()..addOval(rect))
      ..drawCircle(
        center,
        radius,
        Paint()..shader = const SweepGradient(colors: _hues).createShader(rect),
      )
      ..drawCircle(
        center,
        radius,
        Paint()
          ..shader = const RadialGradient(
            colors: <Color>[Color(0xffffffff), Color(0x00ffffff)],
          ).createShader(rect),
      );
    if (hsv.value < 1.0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Color.fromARGB(((1.0 - hsv.value) * 255).round(), 0, 0, 0),
      );
    }
    canvas.restore();

    final angle = hsv.hue * math.pi / 180.0;
    final selectionRadius = math.max(0.0, radius - 8.0);
    final indicator =
        center +
        Offset(math.cos(angle), math.sin(angle)) *
            (hsv.saturation * selectionRadius);
    canvas
      ..drawCircle(indicator, 7.0, Paint()..color = shadowColor)
      ..drawCircle(indicator, 6.0, Paint()..color = indicatorColor)
      ..drawCircle(indicator, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant HsvColorWheelPainter oldDelegate) {
    return color != oldDelegate.color ||
        shadowColor != oldDelegate.shadowColor ||
        indicatorColor != oldDelegate.indicatorColor;
  }
}

class _ColorWheelAdjustmentIntent extends Intent {
  const _ColorWheelAdjustmentIntent({this.hue = 0.0, this.saturation = 0.0});

  final double hue;
  final double saturation;
}
