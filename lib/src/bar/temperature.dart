import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/temperature.dart';
import 'package:trickster/src/theme/accent.dart';

/// One hwmon temperature meter. The pill disappears when no sensor is
/// readable, so it never paints a synthetic zero.
class TemperaturePill extends StatelessWidget {
  const TemperaturePill({
    required this.accent,
    required this.sample,
    this.warn = 80,
    this.critical = 95,
    this.captionSource = MeterCaptionSource.generic,
    this.captionPrefix,
    this.warnColor,
    this.criticalColor,
    this.sparkline = true,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final TemperatureSample sample;
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
    final celsius = sample.celsius;
    if (celsius == null) {
      return const SizedBox.shrink();
    }
    final label =
        captionSource == MeterCaptionSource.custom &&
            (captionPrefix?.isNotEmpty ?? false)
        ? captionPrefix!
        : sample.isCpu
        ? context.l10n.metricCpu
        : context.l10n.metricTemperature;
    final reading = celsius.round();
    return PillTooltip(
      accent: accent,
      label: '$label ${context.l10n.temperatureCelsius('$reading')}',
      child: SystemBarCard(
        accent: accent,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 6 : 12),
        child: LoadMeter(
          accent: accent,
          label: label,
          current: (celsius / 100).clamp(0.0, 1.0),
          history: sample.meterHistory,
          capacity: TemperatureSample.capacity,
          readingText: '$reading',
          readingUnit: '°C',
          valueColor: meterValueColor(
            current: celsius,
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
