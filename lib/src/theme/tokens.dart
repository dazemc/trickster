import 'package:flutter/widgets.dart';

abstract final class ShellBrandColors {
  static const Color defaultAccent = Color(0xffd0bcff);
}

abstract final class ShellMediaColors {
  static const Color lightForeground = Color(0xfff7f7f8);
  static const Color lightForegroundSecondary = Color(0xffc7c9d1);
  static const Color glassSurface = Color(0x28070910);
  static const Color transparentDark = Color(0x00000000);
}

abstract final class ShellTelemetryColors {
  static const Color charging = Color(0xff78dce8);
  static const Color warning = Color(0xffffd166);
  static const Color danger = Color(0xffff6b6b);
  static const Color nominal = Color(0xff8ee6c1);
}

abstract final class ShellText {
  static const String systemBarFontFamily = 'monospace';
  static const List<String> fallbackFontFamilies = <String>[
    'JetBrains Mono',
    'Source Han Sans CN',
    'Noto Sans CJK SC',
  ];

  static const TextStyle systemBarValue = TextStyle(
    fontFamily: systemBarFontFamily,
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 13,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    decoration: TextDecoration.none,
    color: ShellMediaColors.lightForeground,
  );

  static const TextStyle systemBarCaption = TextStyle(
    fontFamily: systemBarFontFamily,
    fontFamilyFallback: fallbackFontFamilies,
    fontSize: 11,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    decoration: TextDecoration.none,
  );
}
