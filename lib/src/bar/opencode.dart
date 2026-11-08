import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/opencode.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

/// The OpenCode usage pill: the selected Go allowance window's remaining
/// percent, the newest session's cost, and a hover label carrying all three
/// windows, reset times, and token totals.
class OpencodePill extends StatelessWidget {
  const OpencodePill({
    required this.accent,
    required this.usage,
    required this.onPressed,
    this.meter = OpencodeMeter.rolling,
    this.showCost = true,
    this.vertical = false,
    super.key,
  });

  static const Key terminalIconKey = ValueKey<String>('opencode-terminal');

  final WallpaperAccent accent;
  final OpencodeUsage usage;
  final VoidCallback onPressed;
  final OpencodeMeter meter;
  final bool showCost;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final primary = switch (meter) {
      OpencodeMeter.rolling => usage.rolling,
      OpencodeMeter.weekly => usage.weekly,
      OpencodeMeter.monthly => usage.monthly,
    };
    if (!usage.available || primary == null) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final window = windowLabel(l10n, meter);
    final remaining = primary.remaining.round();
    final valueColor = primary.limited ? ShellTelemetryColors.danger : null;
    final captionColor = accent.captionColor();
    final percent = Text.rich(
      TextSpan(
        text: '$remaining',
        style: ShellText.systemBarValue.copyWith(color: valueColor),
        children: [
          TextSpan(
            text: '%',
            style: ShellText.systemBarCaption.copyWith(color: captionColor),
          ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
    final cost = showCost ? _costText(context, captionColor) : null;
    final content = vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.squareTerminal,
                key: terminalIconKey,
                size: 14,
                color: captionColor,
              ),
              const SizedBox(height: 2),
              percent,
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.squareTerminal,
                key: terminalIconKey,
                size: 14,
                color: captionColor,
              ),
              const SizedBox(width: 6),
              percent,
              if (cost != null) ...[const SizedBox(width: 6), cost],
            ],
          );
    return PillTooltip(
      accent: accent,
      label: _tooltipLabel(context, l10n, primary),
      child: TricksterActionCard(
        accent: accent,
        label: l10n.opencodePill(window, remaining),
        hint: l10n.opencodeHint,
        onPressed: onPressed,
        child: content,
      ),
    );
  }

  Widget? _costText(BuildContext context, Color captionColor) {
    final session = usage.session;
    if (session == null || session.cost <= 0) {
      return null;
    }
    return Text(
      l10nCost(context, session.cost),
      style: ShellText.systemBarCaption.copyWith(color: captionColor),
    );
  }

  String _tooltipLabel(
    BuildContext context,
    AppLocalizations l10n,
    OpencodeMeterUsage primary,
  ) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final parts = <String>[
      l10n.moduleOpencode,
      meterSummary(l10n, locale, windowLabel(l10n, meter), primary),
    ];
    for (final (window, reading) in [
      (l10n.opencodeWindowWeekly, usage.weekly),
      (l10n.opencodeWindowMonthly, usage.monthly),
    ]) {
      if (reading != null && !identical(reading, primary)) {
        parts.add(l10n.opencodeShortMeter(window, reading.percent.round()));
      }
    }
    final session = usage.session;
    if (session != null && (session.totalTokens > 0 || session.cost > 0)) {
      parts.add(
        l10n.opencodeSession(
          formatOpencodeTokens(session.totalTokens),
          l10nCost(context, session.cost),
        ),
      );
    }
    return parts.join(' · ');
  }
}

/// The localized name of one Go allowance window.
String windowLabel(AppLocalizations l10n, OpencodeMeter meter) {
  return switch (meter) {
    OpencodeMeter.rolling => l10n.opencodeWindowRolling,
    OpencodeMeter.weekly => l10n.opencodeWindowWeekly,
    OpencodeMeter.monthly => l10n.opencodeWindowMonthly,
  };
}

/// One meter's full tooltip sentence: used, left, and reset (or the limit
/// notice).
String meterSummary(
  AppLocalizations l10n,
  String locale,
  String window,
  OpencodeMeterUsage meter,
) {
  final summary = l10n.opencodeMeter(
    window,
    meter.percent.round(),
    meter.remaining.round(),
  );
  if (meter.limited) {
    return '$summary · ${l10n.opencodeLimited}';
  }
  final reset = meter.resetsAt;
  if (reset == null) {
    return summary;
  }
  final time = DateFormat.Hm(locale).format(reset.toLocal());
  return '$summary · ${l10n.opencodeResets(time)}';
}

/// Compact token counts for the tooltip: `999`, `1.2k`, `3.4M`.
String formatOpencodeTokens(int tokens) {
  if (tokens < 1000) {
    return '$tokens';
  }
  if (tokens < 1000000) {
    final thousands = tokens / 1000;
    return '${thousands >= 100 ? thousands.round() : thousands.toStringAsFixed(1)}k';
  }
  return '${(tokens / 1000000).toStringAsFixed(1)}M';
}

/// USD costs keep enough decimals to show sub-cent turns.
String formatOpencodeCost(double cost) {
  if (cost >= 0.1) {
    return cost.toStringAsFixed(2);
  }
  if (cost >= 0.01) {
    return cost.toStringAsFixed(3);
  }
  return cost.toStringAsFixed(4);
}

String l10nCost(BuildContext context, double cost) {
  return context.l10n.opencodeCost(formatOpencodeCost(cost));
}
