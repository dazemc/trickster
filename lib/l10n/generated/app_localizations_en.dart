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
}
