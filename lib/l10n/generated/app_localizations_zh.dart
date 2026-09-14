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

  @override
  String get clockTitle => '时钟';

  @override
  String get batteryHint => '打开电源设置';

  @override
  String get mediaHint => '显示播放控制';

  @override
  String get trayItemHint => '激活该项目';

  @override
  String get settingsTitle => 'Trickster 设置';

  @override
  String get settingsCaption => '配置状态栏：外观、模块、显示器与选项。';

  @override
  String get settingsPlaceholder => '设置页面将在后续步骤中加入。';

  @override
  String get settingsClose => '关闭设置';

  @override
  String get settingsLoading => '正在加载配置…';

  @override
  String get settingsAppearanceTitle => '外观';

  @override
  String get settingsAppearanceCaption => '状态栏使用的强调色。';

  @override
  String get settingsAccentPresets => '预设';

  @override
  String get settingsAccentColor => '强调色';

  @override
  String get settingsAccentReset => '重置';

  @override
  String get settingsColorWheelSemanticsLabel => '强调色';

  @override
  String get settingsColorWheelNextHue => '下一个色相';

  @override
  String get settingsColorWheelPreviousHue => '上一个色相';

  @override
  String get settingsModulesTitle => '模块';

  @override
  String get settingsModulesCaption => '选择状态栏显示的组件及其顺序。';

  @override
  String settingsResetOption(String option) {
    return '重置$option';
  }

  @override
  String get settingsModulesUnavailable => '不可用';

  @override
  String get settingsUnavailableNoBattery => '未检测到电池';

  @override
  String settingsModuleOptions(String module) {
    return '$module 选项';
  }

  @override
  String get settingsModulesEmptyZone => '将模块拖到这里';

  @override
  String get settingsModulesDisabled => '已禁用';

  @override
  String get settingsResetHint => '恢复默认值';

  @override
  String get settingsModulePlacement => '位置';

  @override
  String get settingsPlacementLeading => '起始';

  @override
  String get settingsPlacementCenter => '居中';

  @override
  String get settingsPlacementTrailing => '末尾';

  @override
  String get settingsModuleDrag => '拖动排序';

  @override
  String get settingsModuleToggleHint => '切换该模块';

  @override
  String get settingsModuleMoveUp => '前移';

  @override
  String get settingsModuleMoveDown => '后移';

  @override
  String get moduleWorkspaces => '工作区';

  @override
  String get moduleTray => '系统托盘';

  @override
  String get moduleMedia => '媒体';

  @override
  String get moduleCpu => 'CPU';

  @override
  String get moduleGpu => 'GPU';

  @override
  String get moduleBattery => '电池';

  @override
  String get moduleClock => '时钟';

  @override
  String get settingsDisplaysTitle => '显示器';

  @override
  String get settingsDisplaysCaption => '状态栏所在边缘与厚度。';

  @override
  String get settingsSideLabel => '边缘';

  @override
  String get settingsSideTop => '顶部';

  @override
  String get settingsSideBottom => '底部';

  @override
  String get settingsSideLeft => '左侧';

  @override
  String get settingsSideRight => '右侧';

  @override
  String get settingsSideHidden => '隐藏';

  @override
  String get settingsThicknessLabel => '厚度';

  @override
  String get settingsOutputsLabel => '输出';

  @override
  String get settingsOutputAll => '所有输出';

  @override
  String get settingsOutputToggleHint => '在此输出上显示状态栏';

  @override
  String get settingsOutputsUnavailable => '宿主未报告任何输出。';

  @override
  String get settingsOptionsTitle => '模块选项';

  @override
  String get settingsOptionsCaption => '调整各组件的具体数值。';

  @override
  String get settingsWorkspacesSection => '工作区';

  @override
  String get settingsWorkspacesPerDisplay => '每个显示器';

  @override
  String get settingsClockSection => '时钟';

  @override
  String get settingsClockFormat => '格式';

  @override
  String get settingsClockFormatLocale => '跟随区域设置';

  @override
  String get settingsClockFormat24 => '24 小时制';

  @override
  String get settingsClockFormat12 => '12 小时制';

  @override
  String get settingsCpuSection => 'CPU 阈值';

  @override
  String get settingsBatterySection => '电池阈值';

  @override
  String get settingsWarnLabel => '警告';

  @override
  String get settingsCriticalLabel => '严重';

  @override
  String get settingsMeterSection => '仪表标签';

  @override
  String get settingsMeterCaption => '标签来源';

  @override
  String get settingsMeterCaptionGeneric => '通用';

  @override
  String get settingsMeterCaptionDevice => '设备名称';

  @override
  String get settingsLanguageTitle => '语言';

  @override
  String get settingsLanguageCaption => '状态栏与设置窗口使用的语言。';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsAboutTitle => '关于';

  @override
  String get settingsAboutCaption => '版本与项目链接。';

  @override
  String get settingsAboutVersion => 'Trickster';

  @override
  String get settingsAboutProtocol => '控制协议';

  @override
  String get settingsAboutBar => '运行中的状态栏';

  @override
  String get settingsAboutNotRunning => '未运行';

  @override
  String get settingsAboutRepository => '代码仓库';

  @override
  String get settingsAccentSource => '强调色来源';

  @override
  String get settingsAccentSourceCustom => '自定义';

  @override
  String get settingsAccentSourceWallpaper => '壁纸';

  @override
  String get settingsAccentWallpaperTitle => '采样得到的强调色';

  @override
  String get settingsAccentWallpaperEmpty => '正在等待壁纸采样…';

  @override
  String settingsCopyHex(Object hex) {
    return '复制 $hex';
  }

  @override
  String get settingsCopied => '已复制';
}
