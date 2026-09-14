import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Accessible title for the battery pill.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get batteryTitle;

  /// Battery state while connected to power.
  ///
  /// In en, this message translates to:
  /// **'Charging'**
  String get batteryCharging;

  /// Battery state while running on battery.
  ///
  /// In en, this message translates to:
  /// **'Discharging'**
  String get batteryDischarging;

  /// Battery state followed by the charge level.
  ///
  /// In en, this message translates to:
  /// **'{state} {percent}%'**
  String batteryStateAndPercent(String state, int percent);

  /// Caption for the CPU meter.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get metricCpu;

  /// Caption for a GPU meter when no device name is known.
  ///
  /// In en, this message translates to:
  /// **'GPU'**
  String get desktopGpuLabel;

  /// Accessible label for the media pill.
  ///
  /// In en, this message translates to:
  /// **'Media controls'**
  String get mediaControls;

  /// Accessible label for the previous-track control.
  ///
  /// In en, this message translates to:
  /// **'Previous track'**
  String get mediaPrevious;

  /// Accessible label for the play control.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get mediaPlay;

  /// Accessible label for the pause control.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get mediaPause;

  /// Accessible label for the next-track control.
  ///
  /// In en, this message translates to:
  /// **'Next track'**
  String get mediaNext;

  /// Accessible label for one workspace pip.
  ///
  /// In en, this message translates to:
  /// **'Workspace {workspace}'**
  String workspaceLabel(String workspace);

  /// Workspace state suffix when the workspace is focused.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get workspaceActive;

  /// Workspace state suffix when windows are open on it.
  ///
  /// In en, this message translates to:
  /// **'occupied'**
  String get workspaceOccupied;

  /// Workspace state suffix when no windows are open on it.
  ///
  /// In en, this message translates to:
  /// **'empty'**
  String get workspaceEmpty;

  /// Workspace state suffix when a window needs attention.
  ///
  /// In en, this message translates to:
  /// **'urgent'**
  String get workspaceUrgent;

  /// Accessible label for a tray item with no title or icon name.
  ///
  /// In en, this message translates to:
  /// **'System tray'**
  String get trayItemFallbackLabel;

  /// Tray item status when the item is passive.
  ///
  /// In en, this message translates to:
  /// **'Passive'**
  String get trayStatusPassive;

  /// Tray item status when the item is active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get trayStatusActive;

  /// Tray item status when the item asks for attention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get trayStatusNeedsAttention;

  /// Tray menu entry label when the item publishes none.
  ///
  /// In en, this message translates to:
  /// **'Untitled item'**
  String get trayMenuUntitled;

  /// Accessible label for the clock pill.
  ///
  /// In en, this message translates to:
  /// **'Clock'**
  String get clockTitle;

  /// Accessible hint for the battery pill.
  ///
  /// In en, this message translates to:
  /// **'Opens power settings'**
  String get batteryHint;

  /// Accessible hint for the media pill.
  ///
  /// In en, this message translates to:
  /// **'Shows playback controls'**
  String get mediaHint;

  /// Accessible hint for a tray item button.
  ///
  /// In en, this message translates to:
  /// **'Activates the item'**
  String get trayItemHint;

  /// Window title and heading of the settings application.
  ///
  /// In en, this message translates to:
  /// **'Trickster Settings'**
  String get settingsTitle;

  /// Subtitle under the settings heading.
  ///
  /// In en, this message translates to:
  /// **'Configure the bar: appearance, modules, displays, and options.'**
  String get settingsCaption;

  /// Placeholder body while the settings pages are being built.
  ///
  /// In en, this message translates to:
  /// **'Settings pages arrive in the following steps.'**
  String get settingsPlaceholder;

  /// Accessible label for the settings close button.
  ///
  /// In en, this message translates to:
  /// **'Close settings'**
  String get settingsClose;

  /// Shown while the settings document loads.
  ///
  /// In en, this message translates to:
  /// **'Loading configuration…'**
  String get settingsLoading;

  /// Title of the appearance settings page.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceTitle;

  /// Caption under the appearance page title.
  ///
  /// In en, this message translates to:
  /// **'Accent used across the bar.'**
  String get settingsAppearanceCaption;

  /// Accessible label for the accent preset swatches.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get settingsAccentPresets;

  /// Name of the custom accent color option.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get settingsAccentColor;

  /// Button that clears the custom accent.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsAccentReset;

  /// Accessible label for the accent color wheel.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get settingsColorWheelSemanticsLabel;

  /// Screen-reader value after increasing hue on the color wheel.
  ///
  /// In en, this message translates to:
  /// **'Next hue'**
  String get settingsColorWheelNextHue;

  /// Screen-reader value after decreasing hue on the color wheel.
  ///
  /// In en, this message translates to:
  /// **'Previous hue'**
  String get settingsColorWheelPreviousHue;

  /// Title of the modules settings page.
  ///
  /// In en, this message translates to:
  /// **'Modules'**
  String get settingsModulesTitle;

  /// Caption under the modules page title.
  ///
  /// In en, this message translates to:
  /// **'Choose which pills the bar shows and in what order.'**
  String get settingsModulesCaption;

  /// Accessible label for a control that reverts one option.
  ///
  /// In en, this message translates to:
  /// **'Reset {option}'**
  String settingsResetOption(String option);

  /// Heading for modules this machine cannot run.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get settingsModulesUnavailable;

  /// Reason shown when no battery is detected.
  ///
  /// In en, this message translates to:
  /// **'No battery detected'**
  String get settingsUnavailableNoBattery;

  /// Gear label revealing one module's options.
  ///
  /// In en, this message translates to:
  /// **'{module} options'**
  String settingsModuleOptions(String module);

  /// Hint shown inside an empty placement segment.
  ///
  /// In en, this message translates to:
  /// **'Drop a module here'**
  String get settingsModulesEmptyZone;

  /// Heading for modules that are turned off.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get settingsModulesDisabled;

  /// Hint for a control that reverts one option to its default.
  ///
  /// In en, this message translates to:
  /// **'Revert to the default value'**
  String get settingsResetHint;

  /// Caption above the per-module placement chips.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get settingsModulePlacement;

  /// Placement chip for the strip's leading edge.
  ///
  /// In en, this message translates to:
  /// **'Leading'**
  String get settingsPlacementLeading;

  /// Placement chip for the strip's center.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get settingsPlacementCenter;

  /// Placement chip for the strip's trailing edge.
  ///
  /// In en, this message translates to:
  /// **'Trailing'**
  String get settingsPlacementTrailing;

  /// Handle label for dragging a module row.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get settingsModuleDrag;

  /// Accessible hint for a module toggle.
  ///
  /// In en, this message translates to:
  /// **'Toggles the module'**
  String get settingsModuleToggleHint;

  /// Accessible label for moving a module earlier in the strip.
  ///
  /// In en, this message translates to:
  /// **'Move earlier'**
  String get settingsModuleMoveUp;

  /// Accessible label for moving a module later in the strip.
  ///
  /// In en, this message translates to:
  /// **'Move later'**
  String get settingsModuleMoveDown;

  /// Display name of the workspaces module.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get moduleWorkspaces;

  /// Display name of the tray module.
  ///
  /// In en, this message translates to:
  /// **'System tray'**
  String get moduleTray;

  /// Display name of the media module.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get moduleMedia;

  /// Display name of the CPU module.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get moduleCpu;

  /// Display name of the GPU module.
  ///
  /// In en, this message translates to:
  /// **'GPU'**
  String get moduleGpu;

  /// Display name of the battery module.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get moduleBattery;

  /// Display name of the clock module.
  ///
  /// In en, this message translates to:
  /// **'Clock'**
  String get moduleClock;

  /// Title of the displays settings page.
  ///
  /// In en, this message translates to:
  /// **'Displays'**
  String get settingsDisplaysTitle;

  /// Caption under the displays page title.
  ///
  /// In en, this message translates to:
  /// **'Where the bar sits and how thick it is.'**
  String get settingsDisplaysCaption;

  /// Label above the bar edge choices.
  ///
  /// In en, this message translates to:
  /// **'Edge'**
  String get settingsSideLabel;

  /// Bar edge choice: top.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get settingsSideTop;

  /// Bar edge choice: bottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get settingsSideBottom;

  /// Bar edge choice: left.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get settingsSideLeft;

  /// Bar edge choice: right.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get settingsSideRight;

  /// Bar edge choice: hidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get settingsSideHidden;

  /// Label for the bar thickness slider.
  ///
  /// In en, this message translates to:
  /// **'Thickness'**
  String get settingsThicknessLabel;

  /// Label above the output selection list.
  ///
  /// In en, this message translates to:
  /// **'Outputs'**
  String get settingsOutputsLabel;

  /// Shown when the bar renders on every output.
  ///
  /// In en, this message translates to:
  /// **'All outputs'**
  String get settingsOutputAll;

  /// Accessible hint for an output toggle.
  ///
  /// In en, this message translates to:
  /// **'Shows the bar on this output'**
  String get settingsOutputToggleHint;

  /// Shown when the host lists no outputs.
  ///
  /// In en, this message translates to:
  /// **'No outputs reported by the host.'**
  String get settingsOutputsUnavailable;

  /// Title of the module options settings page.
  ///
  /// In en, this message translates to:
  /// **'Module options'**
  String get settingsOptionsTitle;

  /// Caption under the module options page title.
  ///
  /// In en, this message translates to:
  /// **'Tune the values each pill uses.'**
  String get settingsOptionsCaption;

  /// Section heading for clock options.
  ///
  /// In en, this message translates to:
  /// **'Clock'**
  String get settingsClockSection;

  /// Label above the clock format choices.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get settingsClockFormat;

  /// Clock format choice: follow the locale.
  ///
  /// In en, this message translates to:
  /// **'Locale default'**
  String get settingsClockFormatLocale;

  /// Clock format choice: 24-hour.
  ///
  /// In en, this message translates to:
  /// **'24-hour'**
  String get settingsClockFormat24;

  /// Clock format choice: 12-hour.
  ///
  /// In en, this message translates to:
  /// **'12-hour'**
  String get settingsClockFormat12;

  /// Section heading for CPU threshold options.
  ///
  /// In en, this message translates to:
  /// **'CPU thresholds'**
  String get settingsCpuSection;

  /// Section heading for battery threshold options.
  ///
  /// In en, this message translates to:
  /// **'Battery thresholds'**
  String get settingsBatterySection;

  /// Label for the warning threshold slider.
  ///
  /// In en, this message translates to:
  /// **'Warn'**
  String get settingsWarnLabel;

  /// Label for the critical threshold slider.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get settingsCriticalLabel;

  /// Section heading for meter caption options.
  ///
  /// In en, this message translates to:
  /// **'Meter captions'**
  String get settingsMeterSection;

  /// Label above the meter caption choices.
  ///
  /// In en, this message translates to:
  /// **'Caption source'**
  String get settingsMeterCaption;

  /// Meter caption choice: generic CPU/GPU tags.
  ///
  /// In en, this message translates to:
  /// **'Generic'**
  String get settingsMeterCaptionGeneric;

  /// Meter caption choice: queried device names.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get settingsMeterCaptionDevice;

  /// Title of the language settings page.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// Caption under the language page title.
  ///
  /// In en, this message translates to:
  /// **'Language for the bar and this window.'**
  String get settingsLanguageCaption;

  /// Language choice: follow the system locale.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// Language choice: English.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Language choice: Chinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get settingsLanguageChinese;

  /// Title of the about settings page.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutTitle;

  /// Caption under the about page title.
  ///
  /// In en, this message translates to:
  /// **'Versions and project links.'**
  String get settingsAboutCaption;

  /// Label for the running binary version.
  ///
  /// In en, this message translates to:
  /// **'Trickster'**
  String get settingsAboutVersion;

  /// Label for the control protocol version.
  ///
  /// In en, this message translates to:
  /// **'Control protocol'**
  String get settingsAboutProtocol;

  /// Label for the running bar version.
  ///
  /// In en, this message translates to:
  /// **'Running bar'**
  String get settingsAboutBar;

  /// Shown when no bar answers the version query.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get settingsAboutNotRunning;

  /// Label for the project repository link.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get settingsAboutRepository;

  /// Label above the accent source choices.
  ///
  /// In en, this message translates to:
  /// **'Accent source'**
  String get settingsAccentSource;

  /// Accent source: the configured color.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get settingsAccentSourceCustom;

  /// Accent source: sampled from the host wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper'**
  String get settingsAccentSourceWallpaper;

  /// Heading for the per-output wallpaper accent list.
  ///
  /// In en, this message translates to:
  /// **'Sampled accents'**
  String get settingsAccentWallpaperTitle;

  /// Shown when the wallpaper sampler has produced no accent yet.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the wallpaper sample…'**
  String get settingsAccentWallpaperEmpty;

  /// Accessible label for copying an accent hex value.
  ///
  /// In en, this message translates to:
  /// **'Copy {hex}'**
  String settingsCopyHex(Object hex);

  /// Shown briefly after copying a hex value.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get settingsCopied;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
