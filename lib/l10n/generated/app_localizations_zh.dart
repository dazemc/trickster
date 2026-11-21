// ignore_for_file: deprecated_member_use

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
  String get batteryFull => '已充满';

  @override
  String get batteryNotCharging => '未充电';

  @override
  String batteryTimeRemaining(String duration) {
    return '剩余 $duration';
  }

  @override
  String batteryTimeToFull(String duration) {
    return '距充满 $duration';
  }

  @override
  String batteryDurationHoursMinutes(int hours, int minutes) {
    return '$hours小时$minutes分';
  }

  @override
  String batteryDurationHours(int hours) {
    return '$hours小时';
  }

  @override
  String batteryDurationMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String get metricCpu => 'CPU';

  @override
  String get metricRam => 'RAM';

  @override
  String get metricTemperature => 'TEMP';

  @override
  String get metricDisk => 'DISK';

  @override
  String get metricKeyboardLayout => 'KB';

  @override
  String get metricBrightness => 'BRI';

  @override
  String brightnessTooltip(int percent) {
    return '亮度 $percent%';
  }

  @override
  String brightnessTooltipWithDevice(int percent, String device) {
    return '亮度 $percent% · $device';
  }

  @override
  String keyboardLayoutNames(String layouts) {
    return '布局：$layouts';
  }

  @override
  String diskUsageDetail(String used, String total, String free) {
    return '$used 已用 · $total 总计 · $free 可用';
  }

  @override
  String swapUsageDetail(int percent, String used, String total) {
    return '交换 $percent% · $used / $total';
  }

  @override
  String cpuLoadDetail(int one, int five, int fifteen, int cores) {
    return '负载 1分钟 $one% · 5分钟 $five% · 15分钟 $fifteen%（$cores 核）';
  }

  @override
  String get networkWifi => 'Wi-Fi';

  @override
  String get networkEthernet => '以太网';

  @override
  String get networkConnected => '已连接';

  @override
  String get networkLinked => '已连线';

  @override
  String get networkLocal => '本地';

  @override
  String get networkLimited => '受限';

  @override
  String get networkDisconnected => '未连接';

  @override
  String get networkDisabled => '已关闭';

  @override
  String networkRatesCompact(String rx, String tx) {
    return '↓$rx ↑$tx';
  }

  @override
  String networkLinkDetail(String state) {
    return '链路 $state';
  }

  @override
  String get networkLinkUp => '已连通';

  @override
  String get networkLinkDown => '未连通';

  @override
  String get networkLinkUnknown => '未知';

  @override
  String networkSignal(int percent) {
    return '信号 $percent%';
  }

  @override
  String get networkBand24 => '2.4 GHz';

  @override
  String get networkBand5 => '5 GHz';

  @override
  String get networkBand6 => '6 GHz';

  @override
  String networkSpeedDetail(String speed) {
    return '速率 $speed';
  }

  @override
  String networkRateDetail(String rx, String tx) {
    return '接收 $rx · 发送 $tx';
  }

  @override
  String networkTotalsDetail(String rx, String tx) {
    return '累计接收 $rx · 累计发送 $tx';
  }

  @override
  String temperatureCelsius(String value) {
    return '$value°C';
  }

  @override
  String get desktopGpuLabel => 'GPU';

  @override
  String get desktopVramLabel => 'VRAM';

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
  String get mediaHint => '左键控制播放；右键切换显示模式';

  @override
  String get mediaVolume => '音量';

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
  String get settingsAppearanceBlur => '毛玻璃';

  @override
  String get settingsAppearancePerDisplay => '每个显示器';

  @override
  String get settingsAppearanceAllDisplays => '所有显示器';

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
  String get settingsUnavailableNoVram => '未检测到独立显存';

  @override
  String get settingsUnavailableNoTemperature => '未检测到温度传感器';

  @override
  String get settingsUnavailableNoDisk => '配置的磁盘路径不可用';

  @override
  String get settingsUnavailableNoNetwork => '未检测到网络接口';

  @override
  String get settingsUnavailableNoKeyboardLayoutBackend => '未检测到支持的键盘后端';

  @override
  String get settingsUnavailableNoBacklight => '未检测到背光设备';

  @override
  String settingsModuleOptions(String module) {
    return '$module 选项';
  }

  @override
  String get settingsOptionsClose => '关闭选项';

  @override
  String get settingsWorkspacesPipStyle => '工作区样式';

  @override
  String get settingsWorkspacesPipNumber => '数字';

  @override
  String get settingsWorkspacesPipDot => '圆点';

  @override
  String get settingsWorkspacesPipRoman => '罗马数字';

  @override
  String get settingsWorkspacesImage => '图片';

  @override
  String get settingsWorkspacesImageNone => '未选择图片';

  @override
  String get settingsWorkspacesBrowse => '浏览…';

  @override
  String get settingsWorkspacesImageClear => '清除图片';

  @override
  String get settingsWorkspacesTintSvg => '使用强调色';

  @override
  String get settingsWorkspacesRemoveMapping => '移除';

  @override
  String get settingsWorkspacesTintSvgHint => '仅适用于 SVG 文件。';

  @override
  String get settingsWorkspacesCustom => '自定义…';

  @override
  String get settingsWorkspacesChoose => '选择…';

  @override
  String get settingsWorkspacesAddMapping => '添加';

  @override
  String get settingsWorkspacesNameHint => '工作区名称';

  @override
  String get settingsWorkspacesPerWorkspace => '按工作区';

  @override
  String get settingsWorkspacesPipImage => '图片';

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
  String get settingsModuleDragHint =>
      '拖动以重新排序，或按住 Control 加方向键。加上 Shift 可在区域间移动。';

  @override
  String get settingsModuleDragZoneHint =>
      '拖动以移动，或按住 Control 和 Shift 加方向键选择区域。';

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
  String get moduleRam => '内存';

  @override
  String get moduleTemperature => '温度';

  @override
  String get moduleDisk => '磁盘';

  @override
  String get moduleKeyboardLayout => '键盘布局';

  @override
  String get moduleBrightness => '亮度';

  @override
  String get moduleGpu => 'GPU';

  @override
  String get moduleVram => '显存';

  @override
  String get moduleBattery => '电池';

  @override
  String get moduleNetwork => '网络';

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
  String get settingsOutputsSaveError => '无法保存显示设置；状态栏仍使用原有位置。';

  @override
  String get settingsHiddenNote => '隐藏后不显示状态栏；边缘、厚度与输出选择均被忽略。';

  @override
  String get settingsOptionsTitle => '模块选项';

  @override
  String get settingsOptionsCaption => '调整各组件的具体数值。';

  @override
  String get calendarPreviousMonth => '上个月';

  @override
  String get calendarNextMonth => '下个月';

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
  String get settingsClockShowDate => '日期';

  @override
  String get settingsClockDateWeekday => '星期';

  @override
  String get settingsClockDateLong => '完整';

  @override
  String get settingsClockDateShort => '简短';

  @override
  String get settingsClockDateStyle => '日期样式';

  @override
  String get settingsClockShowSeconds => '秒';

  @override
  String get settingsCpuSection => 'CPU 阈值';

  @override
  String get settingsCpuLoadAverage => '平均负载';

  @override
  String get settingsBatterySection => '电池阈值';

  @override
  String get settingsWarnLabel => '警告';

  @override
  String get settingsCriticalLabel => '严重';

  @override
  String get settingsDiskPath => '挂载路径';

  @override
  String get settingsDiskPathInvalid => '请使用绝对挂载路径';

  @override
  String get settingsNetworkInterface => '网络接口';

  @override
  String get settingsNetworkInterfaceInvalid => '请使用有效的 Linux 接口名';

  @override
  String get settingsNetworkInterfaceHint => '自动';

  @override
  String get settingsNetworkShowRates => '显示速率';

  @override
  String get settingsMeterSection => '仪表标签';

  @override
  String get settingsMeterCaption => '标签来源';

  @override
  String get settingsMeterSparkline => '迷你曲线';

  @override
  String get settingsMediaModeCompact => '紧凑';

  @override
  String get settingsMediaModeSemi => '半幅';

  @override
  String get settingsMediaModeFull => '完整';

  @override
  String get settingsMediaMode => '显示模式';

  @override
  String get settingsMediaBars => '均衡器柱数';

  @override
  String get settingsVolumeStep => '音量步进';

  @override
  String get settingsMeterPrefixHint => '例如 CPU';

  @override
  String get settingsThresholdColorReset => '重置颜色';

  @override
  String get settingsCriticalColor => '严重颜色';

  @override
  String get settingsWarnColor => '警告颜色';

  @override
  String get settingsMeterPrefix => '前缀';

  @override
  String get settingsMeterCaptionCustom => '自定义';

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
  String get settingsAccentWallpaperGrim =>
      '安装 grim 后，Trickster 可以采样此显示器的实际背景色。';

  @override
  String settingsCopyHex(Object hex) {
    return '复制 $hex';
  }

  @override
  String get settingsCopied => '已复制';

  @override
  String get moduleOpencode => 'OpenCode';

  @override
  String opencodePill(String window, int remaining) {
    return 'OpenCode，$window剩余 $remaining%';
  }

  @override
  String get opencodeHint => '打开用量窗口';

  @override
  String get opencodeWindowRolling => '滚动窗口';

  @override
  String get opencodeWindowWeekly => '每周窗口';

  @override
  String get opencodeWindowMonthly => '每月窗口';

  @override
  String opencodeMeter(String window, int used, int remaining) {
    return '$window已用 $used%，剩余 $remaining%';
  }

  @override
  String opencodeShortMeter(String window, int used) {
    return '$window $used%';
  }

  @override
  String opencodeResets(String time) {
    return '$time 重置';
  }

  @override
  String get opencodeLimited => '已达上限';

  @override
  String opencodeSession(String tokens, String cost) {
    return '$tokens tokens，$cost';
  }

  @override
  String opencodeCost(String cost) {
    return '$cost 美元';
  }

  @override
  String get settingsOpencodeMeter => '主要窗口';

  @override
  String get settingsOpencodeShowCost => '会话费用';

  @override
  String get barMenuSettings => 'Trickster 设置';
}
