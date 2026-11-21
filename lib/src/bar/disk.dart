import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/format.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/disk.dart';
import 'package:trickster/src/theme/accent.dart';

/// One configured mount's used fraction. The pill disappears when no statvfs
/// reading is available, so it never paints a synthetic zero.
class DiskPill extends StatelessWidget {
  const DiskPill({
    required this.accent,
    required this.sample,
    this.warn = 0.80,
    this.critical = 0.95,
    this.captionSource = MeterCaptionSource.generic,
    this.captionPrefix,
    this.warnColor,
    this.criticalColor,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final DiskSample sample;
  final double warn;
  final double critical;
  final MeterCaptionSource captionSource;

  /// Caption text when [captionSource] is custom.
  final String? captionPrefix;

  /// Threshold tints; null keeps the shell defaults.
  final Color? warnColor;
  final Color? criticalColor;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final fraction = sample.fraction;
    final used = sample.usedBytes;
    final total = sample.totalBytes;
    final free = sample.freeBytes;
    if (fraction == null || used == null || total == null || free == null) {
      return const SizedBox.shrink();
    }
    final label =
        captionSource == MeterCaptionSource.custom &&
            (captionPrefix?.isNotEmpty ?? false)
        ? captionPrefix!
        : context.l10n.metricDisk;
    final percent = (fraction * 100).round();
    final detail = context.l10n.diskUsageDetail(
      formatIecBytes(used),
      formatIecBytes(total),
      formatIecBytes(free),
    );
    return PillTooltip(
      accent: accent,
      label: '$label $percent% · $detail',
      child: SystemBarCard(
        accent: accent,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 6 : 12),
        child: LoadMeter(
          accent: accent,
          label: label,
          current: fraction,
          history: const [],
          capacity: 1,
          sparkline: false,
          vertical: vertical,
          stacked: vertical,
          valueColor: meterValueColor(
            current: fraction,
            warn: warn,
            critical: critical,
            warnColor: warnColor,
            criticalColor: criticalColor,
          ),
        ),
      ),
    );
  }
}
