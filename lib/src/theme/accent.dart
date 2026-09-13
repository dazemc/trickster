import 'package:flutter/widgets.dart';

import 'tokens.dart';

@immutable
class WallpaperAccent {
  const WallpaperAccent(this.color, {this.isResolved = true});

  static const WallpaperAccent fallback = WallpaperAccent(
    ShellBrandColors.defaultAccent,
    isResolved: false,
  );

  final Color color;
  final bool isResolved;

  Color cardFill() =>
      Color.lerp(const Color(0xff1c1b22), color, 0.15)!;

  Color cardFillTop() =>
      Color.lerp(const Color(0xff1c1b22), color, 0.24)!;

  Color captionColor() =>
      Color.lerp(ShellMediaColors.lightForegroundSecondary, color, 0.35)!;

  @override
  bool operator ==(Object other) =>
      other is WallpaperAccent &&
      other.color == color &&
      other.isResolved == isResolved;

  @override
  int get hashCode => Object.hash(color, isResolved);
}
