import 'package:flutter/widgets.dart';

abstract final class Motion {
  static const Duration cardSettle = Duration(milliseconds: 220);
  static const Duration wallpaperReveal = Duration(milliseconds: 720);
  static const Duration pill = Duration(milliseconds: 90);
  static const Curve standard = Curves.easeOutCubic;
}
