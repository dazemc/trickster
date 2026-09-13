import 'package:flutter/widgets.dart';

import '../locale.dart';
import '../services/gpu.dart';
import '../theme/accent.dart';
import 'meter.dart';
import 'pill.dart';

class GpuPill extends StatelessWidget {
  const GpuPill({required this.accent, required this.load, super.key});

  final WallpaperAccent accent;
  final GpuLoad load;

  @override
  Widget build(BuildContext context) {
    final label = load.label == GpuLoad.genericLabel
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
