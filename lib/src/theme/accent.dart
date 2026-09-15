import 'package:flutter/widgets.dart';

import 'package:trickster/src/theme/tokens.dart';

@immutable
class WallpaperAccent {
  const WallpaperAccent(this.color, {this.isResolved = true});

  static const WallpaperAccent fallback = WallpaperAccent(
    ShellBrandColors.defaultAccent,
    isResolved: false,
  );

  final Color color;
  final bool isResolved;

  Color cardFill() => Color.lerp(const Color(0xff1c1b22), color, 0.15)!;

  Color cardFillTop() => Color.lerp(const Color(0xff1c1b22), color, 0.24)!;

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

/// Accent precedence shared by every consumer: explicit settings accent,
/// then session accent, then the brand default. Pure so widget and bloc
/// tests can pin it without a tree.
WallpaperAccent resolveAccent({Color? settings, Color? session}) =>
    WallpaperAccent(settings ?? session ?? ShellBrandColors.defaultAccent);
