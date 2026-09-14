import 'package:flutter/widgets.dart';

abstract final class Motion {
  static const Duration cardSettle = Duration(milliseconds: 220);
  static const Duration wallpaperReveal = Duration(milliseconds: 720);
  static const Duration pill = Duration(milliseconds: 90);
  static const Duration workspaceSwitch = Duration(milliseconds: 320);
  static const Duration workspaceIndicatorTakeoff = Duration(milliseconds: 72);
  static const Duration workspaceIndicatorTravel = Duration(milliseconds: 168);
  static const Duration workspaceIndicatorSettle = Duration(milliseconds: 80);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve md3Emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve md3EmphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Curve md3EmphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
}
