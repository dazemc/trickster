import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/l10n/generated/app_localizations_en.dart';
import 'package:trickster/src/bar/network.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/network.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

const _ethernet = NetworkSample(
  interface: 'enp42s0',
  medium: NetworkMedium.ethernet,
  link: NetworkLink.up,
  adminUp: true,
  defaultRoute: true,
  ethernetSpeedMbps: 1000,
  rxBytesPerSecond: 1250000,
  txBytesPerSecond: 80000,
  rxBytesTotal: 12400000000,
  txBytesTotal: 1100000000,
);

const _wifi = NetworkSample(
  interface: 'wlan0',
  medium: NetworkMedium.wifi,
  link: NetworkLink.up,
  adminUp: true,
  defaultRoute: true,
  rxBytesPerSecond: 1024,
  txBytesPerSecond: 0,
  rxBytesTotal: 2048,
  txBytesTotal: 1024,
);

Future<void> _pump(
  WidgetTester tester,
  NetworkSample sample, {
  bool showRates = true,
  bool vertical = false,
}) {
  return tester.pumpWidget(
    withOverlayBlocs(
      TricksterLocalizationScope(
        child: Center(
          child: NetworkPill(
            accent: _accent,
            sample: sample,
            showRates: showRates,
            vertical: vertical,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('compact rates use binary steps and short units', () {
    expect(formatNetworkRate(0), '0 B/s');
    expect(formatNetworkRate(512), '512 B/s');
    expect(formatNetworkRate(1024), '1K/s');
    expect(formatNetworkRate(1536), '1.5K/s');
    expect(formatNetworkRate(1250000), '1.2M/s');
    expect(formatNetworkRate(-10), '0 B/s');
  });

  test('link speed formats Mb/s and Gb/s', () {
    expect(formatLinkSpeed(100), '100 Mb/s');
    expect(formatLinkSpeed(1000), '1 Gb/s');
    expect(formatLinkSpeed(2500), '2.5 Gb/s');
    expect(formatLinkSpeed(10000), '10 Gb/s');
  });

  test('local and limited labels exist for the metadata slice', () {
    final l10n = AppLocalizationsEn();
    expect(networkStateLabel(l10n, NetworkPillState.local), 'Local');
    expect(networkStateLabel(l10n, NetworkPillState.limited), 'Limited');
  });

  testWidgets('Ethernet shows its state and compact rates', (tester) async {
    await _pump(tester, _ethernet);
    expect(find.text('Ethernet'), findsOneWidget);
    expect(find.text('↓1.2M/s ↑78.1K/s'), findsOneWidget);
    final tooltip = tester.widget<PillTooltip>(find.byType(PillTooltip));
    expect(tooltip.label, contains('enp42s0'));
    expect(tooltip.label, contains('Ethernet'));
    expect(tooltip.label, contains('link up'));
    expect(tooltip.label, contains('speed 1 Gb/s'));
    expect(tooltip.label, contains('received 1.2M/s · sent 78.1K/s'));
    expect(tooltip.label, contains('11.5 GiB received'));
    expect(tooltip.label, contains('1.0 GiB sent'));
  });

  testWidgets('Wi-Fi shows Wi-Fi without fabricating an SSID', (tester) async {
    await _pump(tester, _wifi);
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('↓1K/s ↑0 B/s'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('an associated SSID replaces Wi-Fi and details the tooltip', (
    tester,
  ) async {
    const sample = NetworkSample(
      interface: 'wlan0',
      medium: NetworkMedium.wifi,
      link: NetworkLink.up,
      adminUp: true,
      defaultRoute: true,
      status: NetworkStatus.online,
      source: NetworkSource.networkManager,
      ssid: 'home',
      signalPercent: 72,
      frequencyMhz: 5180,
      band: WifiBand.band5,
      rxBytesPerSecond: 1024,
      txBytesPerSecond: 512,
      rxBytesTotal: 2048,
      txBytesTotal: 1024,
    );
    await _pump(tester, sample);
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Wi-Fi'), findsNothing);
    final tooltip = tester.widget<PillTooltip>(find.byType(PillTooltip));
    expect(tooltip.label, contains('wlan0'));
    expect(tooltip.label, contains('home'));
    expect(tooltip.label, contains('Wi-Fi'));
    expect(tooltip.label, contains('72% signal'));
    expect(tooltip.label, contains('5 GHz'));
    expect(tooltip.label, contains('link up'));
    expect(tooltip.label, contains('received 1K/s · sent 512 B/s'));
    expect(tooltip.label, contains('2 KiB received'));
  });

  testWidgets('local, limited, and captive classify the pill text', (
    tester,
  ) async {
    Future<void> pumpStatus(NetworkStatus status) {
      return _pump(
        tester,
        NetworkSample(
          interface: 'wlan0',
          medium: NetworkMedium.wifi,
          link: NetworkLink.up,
          adminUp: true,
          defaultRoute: true,
          status: status,
          ssid: 'home',
        ),
      );
    }

    await pumpStatus(NetworkStatus.local);
    expect(find.text('Local'), findsOneWidget);
    await pumpStatus(NetworkStatus.limited);
    expect(find.text('Limited'), findsOneWidget);
    await pumpStatus(NetworkStatus.captive);
    expect(find.text('Limited'), findsOneWidget);
    await pumpStatus(NetworkStatus.disabled);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('linked, disconnected, off, and connected are distinct', (
    tester,
  ) async {
    await _pump(
      tester,
      const NetworkSample(
        interface: 'enp42s0',
        medium: NetworkMedium.ethernet,
        link: NetworkLink.up,
        adminUp: true,
      ),
    );
    expect(find.text('Linked'), findsOneWidget);

    await _pump(
      tester,
      const NetworkSample(
        interface: 'enp42s0',
        medium: NetworkMedium.ethernet,
        link: NetworkLink.down,
        adminUp: true,
        rxBytesPerSecond: 100,
        txBytesPerSecond: 100,
      ),
    );
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.textContaining('↓'), findsNothing);

    await _pump(
      tester,
      const NetworkSample(
        interface: 'enp42s0',
        medium: NetworkMedium.ethernet,
        link: NetworkLink.down,
        adminUp: false,
      ),
    );
    expect(find.text('Off'), findsOneWidget);

    await _pump(
      tester,
      const NetworkSample(
        interface: 'wwan0',
        medium: NetworkMedium.unknown,
        link: NetworkLink.up,
        adminUp: true,
        defaultRoute: true,
      ),
    );
    expect(find.text('Connected'), findsOneWidget);
  });

  testWidgets('showRates false keeps detail in the tooltip only', (
    tester,
  ) async {
    await _pump(tester, _ethernet, showRates: false);
    expect(find.text('Ethernet'), findsOneWidget);
    expect(find.textContaining('↓'), findsNothing);
    final tooltip = tester.widget<PillTooltip>(find.byType(PillTooltip));
    expect(tooltip.label, contains('received 1.2M/s'));
  });

  testWidgets('no interface renders nothing', (tester) async {
    await _pump(tester, const NetworkSample.none());
    expect(find.text('Ethernet'), findsNothing);
    expect(find.byType(PillTooltip), findsNothing);
  });

  testWidgets('vertical stacks the state over the rates', (tester) async {
    await _pump(tester, _ethernet, vertical: true);
    expect(find.text('Ethernet'), findsOneWidget);
    expect(find.text('↓1.2M/s ↑78.1K/s'), findsOneWidget);
  });

  testWidgets('semantics announce the state and rates', (tester) async {
    await _pump(tester, _ethernet);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Ethernet'), findsOneWidget);
    final node = tester.getSemantics(find.bySemanticsLabel('Ethernet'));
    expect(node.value, '↓1.2M/s ↑78.1K/s');
    handle.dispose();
  });
}
