import 'package:flutter/widgets.dart';

import '../config/settings.dart';
import '../locale.dart';
import '../services/cpu.dart';
import '../theme/tokens.dart';
import '../theme/accent.dart';
import 'meter.dart';
import 'pill.dart';

class CpuPill extends StatelessWidget {
  const CpuPill({
    required this.accent,
    required this.sample,
    this.warn = 0.85,
    this.critical = 0.95,
    this.captionSource = MeterCaptionSource.generic,
    super.key,
  });

  final WallpaperAccent accent;
  final CpuSample sample;
  final double warn;
  final double critical;
  final MeterCaptionSource captionSource;

  @override
  Widget build(BuildContext context) {
    final current = sample.current;
    final name = sample.name;
    final valueColor = current == null
        ? null
        : current >= critical
        ? ShellTelemetryColors.danger
        : current >= warn
        ? ShellTelemetryColors.warning
        : null;
    final label =
        captionSource == MeterCaptionSource.device &&
            name != null &&
            name.isNotEmpty
        ? name
        : context.l10n.metricCpu;
    return SystemBarCard(
      accent: accent,
      child: LoadMeter(
        accent: accent,
        label: label,
        current: current,
        history: sample.history,
        capacity: CpuSample.capacity,
        valueColor: valueColor,
      ),
    );
  }
}
