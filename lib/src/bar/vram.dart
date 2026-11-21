import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/theme/accent.dart';

/// One per-GPU dedicated-VRAM meter. The pill disappears when the device
/// publishes no memory, so it never paints a synthetic zero.
class VramPill extends StatelessWidget {
  const VramPill({
    required this.accent,
    required this.load,
    this.index = 0,
    this.count = 1,
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
  final GpuLoad load;

  /// Position among the visible VRAM pills, used to disambiguate duplicate
  /// generic captions on multi-GPU systems.
  final int index;
  final int count;
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
    final current = load.memoryFraction;
    if (current == null) {
      return const SizedBox.shrink();
    }
    final name = load.name;
    final generic = count > 1
        ? '${context.l10n.desktopVramLabel}$index'
        : context.l10n.desktopVramLabel;
    final label = switch (captionSource) {
      MeterCaptionSource.device
          when !vertical && name != null && name.isNotEmpty =>
        name,
      MeterCaptionSource.custom when captionPrefix?.isNotEmpty ?? false =>
        captionPrefix!,
      _ => generic,
    };
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
          history: load.memoryHistory,
          capacity: GpuLoad.capacity,
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
