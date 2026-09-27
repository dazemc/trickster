import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The glyph beside the media pill's volume readout, reflecting the level:
/// a muted sink crosses the speaker out, otherwise the waves grow with the
/// level.
IconData volumeGlyphFor(double volume, {bool muted = false}) {
  if (muted) {
    return LucideIcons.volumeX;
  }
  if (volume < 0.34) {
    return LucideIcons.volume;
  }
  if (volume < 0.67) {
    return LucideIcons.volume1;
  }
  return LucideIcons.volume2;
}
