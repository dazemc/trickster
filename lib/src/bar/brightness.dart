import 'package:flutter/widgets.dart';

import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/brightness.dart';
import 'package:trickster/src/theme/accent.dart';

/// One read-only backlight meter. The pill disappears when no usable device
/// is readable, so it never paints a synthetic zero.
class BrightnessPill extends StatelessWidget {
  const BrightnessPill({
    required this.accent,
    required this.sample,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final BrightnessSample sample;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final percent = sample.percent;
    if (percent == null) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final device = sample.device;
    final tooltip = device == null || device.isEmpty
        ? l10n.brightnessTooltip(percent)
        : l10n.brightnessTooltipWithDevice(percent, device);
    final label = l10n.metricBrightness;
    return PillTooltip(
      accent: accent,
      label: tooltip,
      child: SystemBarCard(
        accent: accent,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 6 : 12),
        child: LoadMeter(
          accent: accent,
          label: label,
          current: sample.fraction,
          history: const [],
          capacity: 1,
          sparkline: false,
          vertical: vertical,
          stacked: vertical,
          readingText: '$percent',
          readingUnit: '%',
        ),
      ),
    );
  }
}
