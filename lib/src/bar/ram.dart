import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/ram.dart';
import 'package:trickster/src/theme/accent.dart';

class RamPill extends StatelessWidget {
  const RamPill({
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
  final RamSample sample;
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
    if (current == null) {
      return const SizedBox.shrink();
    }
    final label =
        captionSource == MeterCaptionSource.custom &&
            (captionPrefix?.isNotEmpty ?? false)
        ? captionPrefix!
        : context.l10n.metricRam;
    return PillTooltip(
      accent: accent,
      label: '$label ${(current * 100).round()}%',
      child: SystemBarCard(
        accent: accent,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 6 : 12),
        child: LoadMeter(
          accent: accent,
          label: label,
          current: current,
          history: sample.history,
          capacity: RamSample.capacity,
          valueColor: meterValueColor(
            current: current,
            warn: warn,
            critical: critical,
            warnColor: warnColor,
            criticalColor: criticalColor,
          ),
          sparkline: sparkline,
          vertical: vertical,
        ),
      ),
    );
  }
}
