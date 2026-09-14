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
  String get metricCpu => 'CPU';

  @override
  String get desktopGpuLabel => 'GPU';

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
  String get mediaHint => 'Shows playback controls';

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
  String get settingsAccentPresets => 'Presets';

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
  String get settingsModulePlacement => 'Position';

  @override
  String get settingsPlacementLeading => 'Leading';

  @override
  String get settingsPlacementCenter => 'Center';

  @override
  String get settingsPlacementTrailing => 'Trailing';

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
  String get moduleGpu => 'GPU';

  @override
  String get moduleBattery => 'Battery';

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
  String get settingsWorkspacesSection => 'Workspaces';

  @override
  String get settingsWorkspacesCount => 'Workspace count';

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
  String get settingsCpuSection => 'CPU thresholds';

  @override
  String get settingsBatterySection => 'Battery thresholds';

  @override
  String get settingsWarnLabel => 'Warn';

  @override
  String get settingsCriticalLabel => 'Critical';

  @override
  String get settingsMeterSection => 'Meter captions';

  @override
  String get settingsMeterCaption => 'Caption source';

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
  String settingsCopyHex(Object hex) {
    return 'Copy $hex';
  }

  @override
  String get settingsCopied => 'Copied';
}
