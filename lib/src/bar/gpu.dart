import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/theme/accent.dart';

class GpuPill extends StatelessWidget {
  const GpuPill({
    required this.accent,
    required this.load,
    this.captionSource = MeterCaptionSource.generic,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final GpuLoad load;
  final MeterCaptionSource captionSource;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final name = load.name;
    // Vertical pills keep the short identity label (`GPU`, `AMD0`, ...):
    // a queried device name would not fit a side strip.
    final label =
        !vertical &&
            captionSource == MeterCaptionSource.device &&
            name != null &&
            name.isNotEmpty
        ? name
        : load.label == GpuLoad.genericLabel
        ? context.l10n.desktopGpuLabel
        : load.label;
    return PillTooltip(
      accent: accent,
      label: '$label ${((load.usage ?? 0.0) * 100).round()}%',
      child: SystemBarCard(
        accent: accent,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 6 : 12),
        child: LoadMeter(
          accent: accent,
          label: label,
          current: load.usage,
          history: load.history,
          capacity: GpuLoad.capacity,
          vertical: vertical,
        ),
      ),
    );
  }
}
