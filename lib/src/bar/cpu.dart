import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/theme/accent.dart';

class CpuPill extends StatelessWidget {
  const CpuPill({
    required this.accent,
    required this.sample,
    this.warn = 0.85,
    this.critical = 0.95,
    this.captionSource = MeterCaptionSource.generic,
    this.captionPrefix,
    this.warnColor,
    this.criticalColor,
    this.sparkline = true,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final CpuSample sample;
  final double warn;
  final double critical;
  final MeterCaptionSource captionSource;

  /// Caption text when [captionSource] is custom.
  final String? captionPrefix;

  /// Threshold tints; null keeps the shell defaults.
  final Color? warnColor;
  final Color? criticalColor;

  /// Whether the recent-history sparkline renders.
  final bool sparkline;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final current = sample.current;
    final name = sample.name;
    final valueColor = meterValueColor(
      current: current,
      warn: warn,
      critical: critical,
      warnColor: warnColor,
      criticalColor: criticalColor,
    );
    final label = switch (captionSource) {
      MeterCaptionSource.device when name != null && name.isNotEmpty => name,
      MeterCaptionSource.custom when captionPrefix?.isNotEmpty ?? false =>
        captionPrefix!,
      _ => context.l10n.metricCpu,
    };
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
          sparkline: sparkline,
          vertical: vertical,
        ),
      ),
    );
  }
}
