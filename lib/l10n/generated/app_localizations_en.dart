// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get batteryTitle => 'Battery';

  @override
  String get batteryCharging => 'Charging';

  @override
  String get batteryDischarging => 'Discharging';

  @override
  String batteryStateAndPercent(String state, int percent) {
    return '$state $percent%';
  }

  @override
  String get batteryFull => 'Full';

  @override
  String get batteryNotCharging => 'Not charging';

  @override
  String batteryTimeRemaining(String duration) {
    return '$duration remaining';
  }

  @override
  String batteryTimeToFull(String duration) {
    return '$duration to full';
  }

  @override
  String batteryDurationHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String batteryDurationHours(int hours) {
    return '${hours}h';
  }

  @override
  String batteryDurationMinutes(int minutes) {
    return '${minutes}m';
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
    return 'Brightness $percent%';
  }

  @override
  String brightnessTooltipWithDevice(int percent, String device) {
    return 'Brightness $percent% · $device';
  }

  @override
  String keyboardLayoutNames(String layouts) {
    return 'Layouts: $layouts';
  }

  @override
  String diskUsageDetail(String used, String total, String free) {
    return '$used used · $total total · $free free';
  }

  @override
  String swapUsageDetail(int percent, String used, String total) {
    return 'Swap $percent% · $used / $total';
  }

  @override
  String cpuLoadDetail(int one, int five, int fifteen, int cores) {
    return 'Load 1m $one% · 5m $five% · 15m $fifteen% ($cores cores)';
  }

  @override
  String get networkWifi => 'Wi-Fi';

  @override
  String get networkEthernet => 'Ethernet';

  @override
  String get networkConnected => 'Connected';

  @override
  String get networkLinked => 'Linked';

  @override
  String get networkLocal => 'Local';

  @override
  String get networkLimited => 'Limited';

  @override
  String get networkDisconnected => 'Disconnected';

  @override
  String get networkDisabled => 'Off';

  @override
  String networkRatesCompact(String rx, String tx) {
    return '↓$rx ↑$tx';
  }

  @override
  String networkLinkDetail(String state) {
    return 'link $state';
  }

  @override
  String get networkLinkUp => 'up';

  @override
  String get networkLinkDown => 'down';

  @override
  String get networkLinkUnknown => 'unknown';

  @override
  String networkSignal(int percent) {
    return '$percent% signal';
  }

  @override
  String get networkBand24 => '2.4 GHz';

  @override
  String get networkBand5 => '5 GHz';

  @override
  String get networkBand6 => '6 GHz';

  @override
  String networkSpeedDetail(String speed) {
    return 'speed $speed';
  }

  @override
  String networkRateDetail(String rx, String tx) {
    return 'received $rx · sent $tx';
  }

  @override
  String networkTotalsDetail(String rx, String tx) {
    return '$rx received · $tx sent';
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
  String get mediaControls => 'Media controls';

  @override
  String get mediaPrevious => 'Previous track';

  @override
  String get mediaPlay => 'Play';

  @override
  String get mediaPause => 'Pause';

  @override
  String get mediaNext => 'Next track';

  @override
  String workspaceLabel(String workspace) {
    return 'Workspace $workspace';
  }

  @override
  String get workspaceActive => 'active';

  @override
  String get workspaceOccupied => 'occupied';

  @override
  String get workspaceEmpty => 'empty';

  @override
  String get workspaceUrgent => 'urgent';

  @override
  String get trayItemFallbackLabel => 'System tray';

  @override
  String get trayStatusPassive => 'Passive';

  @override
  String get trayStatusActive => 'Active';

  @override
  String get trayStatusNeedsAttention => 'Needs attention';

  @override
  String get trayMenuUntitled => 'Untitled item';

  @override
  String get clockTitle => 'Clock';

  @override
  String get batteryHint => 'Opens power settings';

  @override
  String get mediaHint =>
      'Left click controls playback; right click cycles the display mode';

  @override
  String get mediaVolume => 'Volume';

  @override
  String get trayItemHint => 'Activates the item';

  @override
  String get settingsTitle => 'Trickster Settings';

  @override
  String get settingsCaption =>
      'Configure the bar: appearance, modules, displays, and options.';

  @override
  String get settingsPlaceholder =>
      'Settings pages arrive in the following steps.';

  @override
  String get settingsClose => 'Close settings';

  @override
  String get settingsLoading => 'Loading configuration…';

  @override
  String get settingsAppearanceTitle => 'Appearance';

  @override
  String get settingsAppearanceCaption => 'Accent used across the bar.';

  @override
  String get settingsAppearanceBlur => 'Hosted blur';

  @override
  String get settingsAppearancePerDisplay => 'Per display';

  @override
  String get settingsAppearanceAllDisplays => 'All displays';

  @override
  String get settingsAccentPresets => 'Presets';

  @override
  String get settingsAccentColor => 'Accent color';

  @override
  String get settingsAccentReset => 'Reset';

  @override
  String get settingsColorWheelSemanticsLabel => 'Accent color';

  @override
  String get settingsColorWheelNextHue => 'Next hue';

  @override
  String get settingsColorWheelPreviousHue => 'Previous hue';

  @override
  String get settingsModulesTitle => 'Modules';

  @override
  String get settingsModulesCaption =>
      'Choose which pills the bar shows and in what order.';

  @override
  String settingsResetOption(String option) {
    return 'Reset $option';
  }

  @override
  String get settingsModulesUnavailable => 'Unavailable';

  @override
  String get settingsUnavailableNoBattery => 'No battery detected';

  @override
  String get settingsUnavailableNoVram => 'No dedicated GPU memory detected';

  @override
  String get settingsUnavailableNoTemperature =>
      'No temperature sensor detected';

  @override
  String get settingsUnavailableNoDisk => 'Configured disk path is unavailable';

  @override
  String get settingsUnavailableNoNetwork => 'No network interface detected';

  @override
  String get settingsUnavailableNoKeyboardLayoutBackend =>
      'No supported keyboard-layout backend detected';

  @override
  String get settingsUnavailableNoBacklight => 'No backlight detected';

  @override
  String settingsModuleOptions(String module) {
    return '$module options';
  }

  @override
  String get settingsOptionsClose => 'Close options';

  @override
  String get settingsWorkspacesPipStyle => 'Pip style';

  @override
  String get settingsWorkspacesPipNumber => 'Numbers';

  @override
  String get settingsWorkspacesPipDot => 'Dots';

  @override
  String get settingsWorkspacesPipRoman => 'Roman';

  @override
  String get settingsWorkspacesImage => 'Image';

  @override
  String get settingsWorkspacesImageNone => 'No image chosen';

  @override
  String get settingsWorkspacesBrowse => 'Browse…';

  @override
  String get settingsWorkspacesImageClear => 'Clear image';

  @override
  String get settingsWorkspacesTintSvg => 'Color with accent';

  @override
  String get settingsWorkspacesRemoveMapping => 'Remove';

  @override
  String get settingsWorkspacesTintSvgHint => 'Only applies to SVG files.';

  @override
  String get settingsWorkspacesCustom => 'Custom…';

  @override
  String get settingsWorkspacesChoose => 'Choose…';

  @override
  String get settingsWorkspacesAddMapping => 'Add';

  @override
  String get settingsWorkspacesNameHint => 'Workspace name';

  @override
  String get settingsWorkspacesPerWorkspace => 'Per workspace';

  @override
  String get settingsWorkspacesPipImage => 'Image';

  @override
  String get settingsModulesEmptyZone => 'Drop a module here';

  @override
  String get settingsModulesDisabled => 'Disabled';

  @override
  String get settingsResetHint => 'Revert to the default value';

  @override
  String get settingsModulePlacement => 'Position';

  @override
  String get settingsPlacementLeading => 'Leading';

  @override
  String get settingsPlacementCenter => 'Center';

  @override
  String get settingsPlacementTrailing => 'Trailing';

  @override
  String get settingsModuleDrag => 'Drag to reorder';

  @override
  String get settingsModuleDragHint =>
      'Drag to reorder, or press Control and the arrow keys. Add Shift to move between zones.';

  @override
  String get settingsModuleDragZoneHint =>
      'Drag to move, or press Control and Shift with the arrow keys to choose a zone.';

  @override
  String get settingsModuleToggleHint => 'Toggles the module';

  @override
  String get settingsModuleMoveUp => 'Move earlier';

  @override
  String get settingsModuleMoveDown => 'Move later';

  @override
  String get moduleWorkspaces => 'Workspaces';

  @override
  String get moduleTray => 'System tray';

  @override
  String get moduleMedia => 'Media';

  @override
  String get moduleCpu => 'CPU';

  @override
  String get moduleRam => 'Memory';

  @override
  String get moduleTemperature => 'Temperature';

  @override
  String get moduleDisk => 'Disk';

  @override
  String get moduleKeyboardLayout => 'Keyboard layout';

  @override
  String get moduleBrightness => 'Brightness';

  @override
  String get moduleGpu => 'GPU';

  @override
  String get moduleVram => 'Video memory';

  @override
  String get moduleBattery => 'Battery';

  @override
  String get moduleNetwork => 'Network';

  @override
  String get moduleClock => 'Clock';

  @override
  String get settingsDisplaysTitle => 'Displays';

  @override
  String get settingsDisplaysCaption =>
      'Where the bar sits and how thick it is.';

  @override
  String get settingsSideLabel => 'Edge';

  @override
  String get settingsSideTop => 'Top';

  @override
  String get settingsSideBottom => 'Bottom';

  @override
  String get settingsSideLeft => 'Left';

  @override
  String get settingsSideRight => 'Right';

  @override
  String get settingsSideHidden => 'Hidden';

  @override
  String get settingsThicknessLabel => 'Thickness';

  @override
  String get settingsOutputsLabel => 'Outputs';

  @override
  String get settingsOutputAll => 'All outputs';

  @override
  String get settingsOutputToggleHint => 'Shows the bar on this output';

  @override
  String get settingsOutputsUnavailable => 'No outputs reported by the host.';

  @override
  String get settingsOptionsTitle => 'Module options';

  @override
  String get settingsOptionsCaption => 'Tune the values each pill uses.';

  @override
  String get calendarPreviousMonth => 'Previous month';

  @override
  String get calendarNextMonth => 'Next month';

  @override
  String get settingsClockSection => 'Clock';

  @override
  String get settingsClockFormat => 'Format';

  @override
  String get settingsClockFormatLocale => 'Locale default';

  @override
  String get settingsClockFormat24 => '24-hour';

  @override
  String get settingsClockFormat12 => '12-hour';

  @override
  String get settingsClockShowDate => 'Date';

  @override
  String get settingsClockDateWeekday => 'Weekday';

  @override
  String get settingsClockDateLong => 'Long';

  @override
  String get settingsClockDateShort => 'Short';

  @override
  String get settingsClockDateStyle => 'Date style';

  @override
  String get settingsClockShowSeconds => 'Seconds';

  @override
  String get settingsCpuSection => 'CPU thresholds';

  @override
  String get settingsCpuLoadAverage => 'Load average';

  @override
  String get settingsBatterySection => 'Battery thresholds';

  @override
  String get settingsWarnLabel => 'Warn';

  @override
  String get settingsCriticalLabel => 'Critical';

  @override
  String get settingsDiskPath => 'Mount path';

  @override
  String get settingsDiskPathInvalid => 'Use an absolute mount path';

  @override
  String get settingsNetworkInterface => 'Interface';

  @override
  String get settingsNetworkInterfaceInvalid =>
      'Use a valid Linux interface name';

  @override
  String get settingsNetworkInterfaceHint => 'auto';

  @override
  String get settingsNetworkShowRates => 'Show rates';

  @override
  String get settingsMeterSection => 'Meter captions';

  @override
  String get settingsMeterCaption => 'Caption source';

  @override
  String get settingsMeterSparkline => 'Sparkline';

  @override
  String get settingsMediaModeCompact => 'Compact';

  @override
  String get settingsMediaModeSemi => 'Semi';

  @override
  String get settingsMediaModeFull => 'Full';

  @override
  String get settingsMediaMode => 'Display mode';

  @override
  String get settingsMediaBars => 'Equalizer bars';

  @override
  String get settingsVolumeStep => 'Volume step';

  @override
  String get settingsMeterPrefixHint => 'e.g. CPU';

  @override
  String get settingsThresholdColorReset => 'Reset color';

  @override
  String get settingsCriticalColor => 'Critical color';

  @override
  String get settingsWarnColor => 'Warning color';

  @override
  String get settingsMeterPrefix => 'Prefix';

  @override
  String get settingsMeterCaptionCustom => 'Custom';

  @override
  String get settingsMeterCaptionGeneric => 'Generic';

  @override
  String get settingsMeterCaptionDevice => 'Device name';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageCaption => 'Language for the bar and this window.';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageChinese => '中文';

  @override
  String get settingsAboutTitle => 'About';

  @override
  String get settingsAboutCaption => 'Versions and project links.';

  @override
  String get settingsAboutVersion => 'Trickster';

  @override
  String get settingsAboutProtocol => 'Control protocol';

  @override
  String get settingsAboutBar => 'Running bar';

  @override
  String get settingsAboutNotRunning => 'Not running';

  @override
  String get settingsAboutRepository => 'Repository';

  @override
  String get settingsAccentSource => 'Accent source';

  @override
  String get settingsAccentSourceCustom => 'Configured';

  @override
  String get settingsAccentSourceWallpaper => 'Wallpaper';

  @override
  String get settingsAccentWallpaperTitle => 'Sampled accents';

  @override
  String get settingsAccentWallpaperEmpty =>
      'Waiting for the wallpaper sample…';

  @override
  String get settingsAccentWallpaperGrim =>
      'With grim installed, Trickster can sample the actual backdrop.';

  @override
  String settingsCopyHex(Object hex) {
    return 'Copy $hex';
  }

  @override
  String get settingsCopied => 'Copied';

  @override
  String get moduleOpencode => 'OpenCode';

  @override
  String opencodePill(String window, int remaining) {
    return 'OpenCode, $window $remaining% left';
  }

  @override
  String get opencodeHint => 'Opens the usage window';

  @override
  String get opencodeWindowRolling => 'Rolling';

  @override
  String get opencodeWindowWeekly => 'Weekly';

  @override
  String get opencodeWindowMonthly => 'Monthly';

  @override
  String opencodeMeter(String window, int used, int remaining) {
    return '$window $used% used, $remaining% left';
  }

  @override
  String opencodeShortMeter(String window, int used) {
    return '$window $used%';
  }

  @override
  String opencodeResets(String time) {
    return 'resets $time';
  }

  @override
  String get opencodeLimited => 'limit reached';

  @override
  String opencodeSession(String tokens, String cost) {
    return '$tokens tokens, $cost';
  }

  @override
  String opencodeCost(String cost) {
    return '$cost USD';
  }

  @override
  String get settingsOpencodeMeter => 'Headline window';

  @override
  String get settingsOpencodeShowCost => 'Session cost';
}
