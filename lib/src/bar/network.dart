import 'package:flutter/widgets.dart';

import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/bar/format.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/network.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

/// Compact throughput for the pill and tooltip: `0 B/s`, `840 B/s`,
/// `1.5K/s`, `12.3M/s`. KiB-style steps, no space before the short unit.
String formatNetworkRate(int bytesPerSecond) {
  final bytes = bytesPerSecond < 0 ? 0 : bytesPerSecond;
  if (bytes < 1024) {
    return '$bytes B/s';
  }
  const units = ['K/s', 'M/s', 'G/s', 'T/s', 'P/s'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final digits = value >= 100 || value == value.roundToDouble() ? 0 : 1;
  return '${value.toStringAsFixed(digits)}${units[unit]}';
}

/// Ethernet link speed: `100 Mb/s`, `1 Gb/s`, `2.5 Gb/s`.
String formatLinkSpeed(int mbps) {
  if (mbps < 1000) {
    return '$mbps Mb/s';
  }
  final gbps = mbps / 1000;
  final digits = gbps == gbps.roundToDouble() ? 0 : 1;
  return '${gbps.toStringAsFixed(digits)} Gb/s';
}

String networkStateLabel(AppLocalizations l10n, NetworkPillState state) {
  return switch (state) {
    NetworkPillState.wifi => l10n.networkWifi,
    NetworkPillState.ethernet => l10n.networkEthernet,
    NetworkPillState.connected => l10n.networkConnected,
    NetworkPillState.linked => l10n.networkLinked,
    NetworkPillState.local => l10n.networkLocal,
    NetworkPillState.limited => l10n.networkLimited,
    NetworkPillState.disconnected => l10n.networkDisconnected,
    NetworkPillState.disabled => l10n.networkDisabled,
  };
}

String networkLinkLabel(AppLocalizations l10n, NetworkLink link) {
  return switch (link) {
    NetworkLink.up => l10n.networkLinkUp,
    NetworkLink.down => l10n.networkLinkDown,
    NetworkLink.unknown => l10n.networkLinkUnknown,
  };
}

String? networkBandLabel(AppLocalizations l10n, WifiBand band) {
  return switch (band) {
    WifiBand.band24 => l10n.networkBand24,
    WifiBand.band5 => l10n.networkBand5,
    WifiBand.band6 => l10n.networkBand6,
    WifiBand.unknown => null,
  };
}

/// The number the pill paints: an associated SSID when the link is healthy,
/// otherwise the state text (Local, Limited, Disconnected, and so on).
String networkIdentityLabel(AppLocalizations l10n, NetworkSample sample) {
  final ssid = sample.ssid;
  if (sample.pillState == NetworkPillState.wifi &&
      ssid != null &&
      ssid.isNotEmpty) {
    return ssid;
  }
  return networkStateLabel(l10n, sample.pillState);
}

/// The hover label carries the identity, signal, band, link, speed, current
/// rates, and lifetime totals. Unknown metadata is omitted, never fabricated.
String networkTooltipLabel(AppLocalizations l10n, NetworkSample sample) {
  final band = networkBandLabel(l10n, sample.band);
  final parts = <String>[
    ?sample.interface,
    networkStateLabel(l10n, sample.pillState),
    if (sample.ssid case final ssid? when ssid.isNotEmpty) ssid,
    if (sample.signalPercent != null) l10n.networkSignal(sample.signalPercent!),
    ?band,
    l10n.networkLinkDetail(networkLinkLabel(l10n, sample.link)),
    if (sample.ethernetSpeedMbps != null)
      l10n.networkSpeedDetail(formatLinkSpeed(sample.ethernetSpeedMbps!)),
    if (sample.rxBytesPerSecond != null && sample.txBytesPerSecond != null)
      l10n.networkRateDetail(
        formatNetworkRate(sample.rxBytesPerSecond!),
        formatNetworkRate(sample.txBytesPerSecond!),
      ),
    if (sample.rxBytesTotal != null && sample.txBytesTotal != null)
      l10n.networkTotalsDetail(
        formatIecBytes(sample.rxBytesTotal!),
        formatIecBytes(sample.txBytesTotal!),
      ),
  ];
  return parts.join(' · ');
}

/// One interface's state label plus compact rates. The pill disappears only
/// when no interface is selected; disconnected and disabled states stay
/// visible so the bar never pretends the link is absent.
class NetworkPill extends StatelessWidget {
  const NetworkPill({
    required this.accent,
    required this.sample,
    this.showRates = true,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final NetworkSample sample;
  final bool showRates;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    if (!sample.visible) {
      return const SizedBox.shrink();
    }
    final l10n = context.l10n;
    final stateText = networkIdentityLabel(l10n, sample);
    final rx = sample.rxBytesPerSecond;
    final tx = sample.txBytesPerSecond;
    final ratesText =
        showRates &&
            sample.adminUp &&
            sample.link == NetworkLink.up &&
            rx != null &&
            tx != null
        ? l10n.networkRatesCompact(formatNetworkRate(rx), formatNetworkRate(tx))
        : null;
    final stateStyle = ShellText.systemBarValue;
    final ratesStyle = ShellText.systemBarCaption.copyWith(
      color: accent.captionColor(),
    );
    final label = Semantics(
      label: stateText,
      value: ratesText ?? networkLinkLabel(l10n, sample.link),
      child: ExcludeSemantics(
        child: vertical
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 72),
                    child: Text(
                      stateText,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: stateStyle,
                    ),
                  ),
                  if (ratesText != null)
                    Text(
                      ratesText,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: ratesStyle,
                    ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(
                      stateText,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: stateStyle,
                    ),
                  ),
                  if (ratesText != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      ratesText,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: ratesStyle,
                    ),
                  ],
                ],
              ),
      ),
    );
    return PillTooltip(
      accent: accent,
      label: networkTooltipLabel(l10n, sample),
      child: SystemBarCard(
        accent: accent,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 6 : 12),
        child: label,
      ),
    );
  }
}
