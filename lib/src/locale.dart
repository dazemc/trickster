import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Device locale reduced to one the widgets localization delegate actually
/// supports. Headless environments (notably `LANG=C.UTF-8`) report locales
/// like `C` that no delegate claims; handing those to `Localizations`
/// crashes resource resolution on first build. English is the fallback
/// because the bar's source strings are English until the arb pipeline
/// (TODO C1) exists.
Locale resolveAppLocale(Locale device) {
  const fallback = Locale('en', 'US');
  for (final candidate in [
    device,
    Locale(device.languageCode),
    fallback,
  ]) {
    if (GlobalWidgetsLocalizations.delegate.isSupported(candidate)) {
      return candidate;
    }
  }
  return fallback;
}
