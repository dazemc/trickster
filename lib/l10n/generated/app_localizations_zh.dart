// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get batteryTitle => '电池';

  @override
  String get batteryCharging => '正在充电';

  @override
  String get batteryDischarging => '正在放电';

  @override
  String batteryStateAndPercent(String state, int percent) {
    return '$state $percent%';
  }

  @override
  String get metricCpu => 'CPU';

  @override
  String get desktopGpuLabel => 'GPU';

  @override
  String get mediaControls => '媒体控件';

  @override
  String get mediaPrevious => '上一首';

  @override
  String get mediaPlay => '播放';

  @override
  String get mediaPause => '暂停';

  @override
  String get mediaNext => '下一首';

  @override
  String workspaceLabel(String workspace) {
    return '工作区 $workspace';
  }

  @override
  String get workspaceActive => '活动';

  @override
  String get workspaceOccupied => '占用';

  @override
  String get workspaceEmpty => '空闲';

  @override
  String get workspaceUrgent => '紧急';

  @override
  String get trayItemFallbackLabel => '系统托盘';

  @override
  String get trayStatusPassive => '被动';

  @override
  String get trayStatusActive => '活动';

  @override
  String get trayStatusNeedsAttention => '需要关注';

  @override
  String get trayMenuUntitled => '未命名项目';
}
