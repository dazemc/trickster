import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

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
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
