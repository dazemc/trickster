import 'package:flutter/widgets.dart';

import '../services/cpu.dart';
import '../theme/accent.dart';
import 'meter.dart';
import 'pill.dart';

class CpuPill extends StatelessWidget {
  const CpuPill({required this.accent, required this.sample, super.key});

  final WallpaperAccent accent;
  final CpuSample sample;

  @override
  Widget build(BuildContext context) {
    return SystemBarCard(
      accent: accent,
      child: LoadMeter(
        accent: accent,
        label: 'CPU',
        current: sample.current,
        history: sample.history,
        capacity: CpuSample.capacity,
      ),
    );
  }
}
