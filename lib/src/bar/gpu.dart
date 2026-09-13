import 'package:flutter/widgets.dart';

import '../config/settings.dart';
import '../locale.dart';
import '../services/gpu.dart';
import '../theme/accent.dart';
import 'meter.dart';
import 'pill.dart';

class GpuPill extends StatelessWidget {
  const GpuPill({
    required this.accent,
    required this.load,
    this.captionSource = MeterCaptionSource.generic,
    super.key,
  });

  final WallpaperAccent accent;
  final GpuLoad load;
  final MeterCaptionSource captionSource;

  @override
  Widget build(BuildContext context) {
    final name = load.name;
    final label =
        captionSource == MeterCaptionSource.device &&
            name != null &&
            name.isNotEmpty
        ? name
        : load.label == GpuLoad.genericLabel
        ? context.l10n.desktopGpuLabel
        : load.label;
    return SystemBarCard(
      accent: accent,
      child: LoadMeter(
        accent: accent,
        label: label,
        current: load.usage,
        history: load.history,
        capacity: GpuLoad.capacity,
      ),
    );
  }
}
