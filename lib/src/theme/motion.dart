import 'package:flutter/widgets.dart';

abstract final class Motion {
  static const Duration cardSettle = Duration(milliseconds: 220);
  static const Duration wallpaperReveal = Duration(milliseconds: 720);
  static const Duration pill = Duration(milliseconds: 90);
  static const Duration workspaceSwitch = Duration(milliseconds: 320);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve md3Emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
}
