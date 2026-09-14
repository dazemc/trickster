import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

class CpuPill extends StatelessWidget {
  const CpuPill({
    required this.accent,
    required this.sample,
    this.warn = 0.85,
    this.critical = 0.95,
    this.captionSource = MeterCaptionSource.generic,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final CpuSample sample;
  final double warn;
  final double critical;
  final MeterCaptionSource captionSource;
  final bool vertical;

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
    return PillTooltip(
      accent: accent,
      label: '$label ${((current ?? 0.0) * 100).round()}%',
      child: SystemBarCard(
        accent: accent,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 6 : 12),
        child: LoadMeter(
          accent: accent,
          label: label,
          current: current,
          history: sample.history,
          capacity: CpuSample.capacity,
          valueColor: valueColor,
          vertical: vertical,
        ),
      ),
    );
  }
}
