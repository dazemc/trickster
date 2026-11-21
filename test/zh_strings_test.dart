import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));
const _zh = Locale('zh');

Widget _scope(Widget child) =>
    TricksterLocalizationScope(locale: _zh, child: withOverlayBlocs(child));

void main() {
  testWidgets('battery pill announces the Chinese state and capacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _scope(
        Center(
          child: BatteryPill(
            accent: _accent,
            status: const BatteryStatus(capacity: 87, charging: true),
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('电池, 正在充电 87%'), findsOneWidget);
  });

  testWidgets('workspace pips announce Chinese state suffixes', (tester) async {
    await tester.pumpWidget(
      _scope(
        Center(
          child: WorkspacesPill(
            accent: _accent,
            workspaces: const [
              Workspace(id: '1', name: 'web', focused: true),
              Workspace(id: '2', name: '2', urgent: true, occupied: true),
            ],
            horizontal: true,
            onPressed: (_) {},
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('工作区 web, 空闲, 活动'), findsOneWidget);
    expect(find.bySemanticsLabel('工作区 2, 占用, 紧急'), findsOneWidget);
  });

  testWidgets('tray pill announces Chinese status and fallback label', (
    tester,
  ) async {
    final bloc = TrayBloc(initial: const TrayState());
    addTearDown(bloc.close);
    await tester.pumpWidget(
      _scope(
        BlocProvider<TrayBloc>.value(
          value: bloc,
          child: Center(
            child: TrayPill(
              accent: _accent,
              items: const [
                SystemTrayItem(
                  id: 'a',
                  title: '',
                  status: SystemTrayStatus.needsAttention,
                  iconName: '',
                  iconThemePath: '',
                  iconPixmap: null,
                  menuAvailable: false,
                  primaryOpensMenu: false,
                ),
                SystemTrayItem(
                  id: 'b',
                  title: 'Named',
                  status: SystemTrayStatus.passive,
                  iconName: 'icon',
                  iconThemePath: '',
                  iconPixmap: null,
                  menuAvailable: false,
                  primaryOpensMenu: false,
                ),
              ],
              onActivate: (item, position) {},
            ),
          ),
        ),
      ),
    );
    final attention = tester.getSemantics(find.bySemanticsLabel('系统托盘'));
    expect(attention.value, '需要关注');
    final passive = tester.getSemantics(find.bySemanticsLabel('Named'));
    expect(passive.value, '被动');
  });

  testWidgets('catalog exposes the Chinese chrome strings', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      _scope(
        Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(l10n.mediaControls, '媒体控件');
    expect(l10n.mediaPrevious, '上一首');
    expect(l10n.mediaPlay, '播放');
    expect(l10n.mediaPause, '暂停');
    expect(l10n.mediaNext, '下一首');
    expect(l10n.trayMenuUntitled, '未命名项目');
    expect(l10n.workspaceUrgent, '紧急');
    expect(l10n.metricCpu, 'CPU');
    expect(l10n.metricRam, 'RAM');
    expect(l10n.moduleRam, '内存');
    expect(l10n.desktopGpuLabel, 'GPU');
    expect(l10n.desktopVramLabel, 'VRAM');
    expect(l10n.moduleVram, '显存');
    expect(l10n.metricTemperature, 'TEMP');
    expect(l10n.moduleTemperature, '温度');
    expect(l10n.temperatureCelsius('36'), '36°C');
    expect(l10n.metricDisk, 'DISK');
    expect(l10n.moduleDisk, '磁盘');
    expect(
      l10n.diskUsageDetail('620 GiB', '1 TiB', '404 GiB'),
      '620 GiB 已用 · 1 TiB 总计 · 404 GiB 可用',
    );
    expect(l10n.moduleNetwork, '网络');
    expect(l10n.networkEthernet, '以太网');
    expect(l10n.networkDisconnected, '未连接');
    expect(l10n.networkRatesCompact('1.2M/s', '80K/s'), '↓1.2M/s ↑80K/s');
    expect(l10n.networkLinkDetail('已连通'), '链路 已连通');
    expect(
      l10n.networkTotalsDetail('1 GiB', '2 GiB'),
      '累计接收 1 GiB · 累计发送 2 GiB',
    );
    expect(l10n.settingsNetworkShowRates, '显示速率');
    expect(l10n.metricKeyboardLayout, 'KB');
    expect(l10n.moduleKeyboardLayout, '键盘布局');
    expect(l10n.keyboardLayoutNames('US / RU'), '布局：US / RU');
    expect(l10n.settingsUnavailableNoHyprland, '未检测到 Hyprland 会话');
  });
}
