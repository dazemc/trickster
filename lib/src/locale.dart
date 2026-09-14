import 'package:flutter/widgets.dart';

import '../l10n/generated/app_localizations.dart';

/// Installs the generated localizations without introducing a MaterialApp
/// or [WidgetsApp] above the strip, and derives [Directionality] from the
/// resolved locale instead of hardcoding LTR.
///
/// The platform locale list is resolved against the generated catalog and
/// observed for changes. Unsupported locales fall back through Flutter's
/// standard resolution, which selects English.
class TricksterLocalizationScope extends StatefulWidget {
  const TricksterLocalizationScope({
    required this.child,
    this.locale,
    super.key,
  });

  final Widget child;

  /// An explicit locale for tests or a persisted user preference. When
  /// omitted, the scope follows the platform's ordered locale list.
  final Locale? locale;

  @override
  State<TricksterLocalizationScope> createState() =>
      _TricksterLocalizationScopeState();
}

class _TricksterLocalizationScopeState extends State<TricksterLocalizationScope>
    with WidgetsBindingObserver {
  late Locale _effectiveLocale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _effectiveLocale = _resolveLocale();
  }

  @override
  void didUpdateWidget(covariant TricksterLocalizationScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locale != widget.locale) {
      _updateLocale();
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (widget.locale == null) {
      _updateLocale(locales);
    }
  }

  Locale _resolveLocale([List<Locale>? platformLocales]) {
    final explicit = widget.locale;
    return basicLocaleListResolution(
      explicit != null
          ? <Locale>[explicit]
          : platformLocales ??
                WidgetsBinding.instance.platformDispatcher.locales,
      AppLocalizations.supportedLocales,
    );
  }

  void _updateLocale([List<Locale>? platformLocales]) {
    final next = _resolveLocale(platformLocales);
    if (next != _effectiveLocale) {
      setState(() => _effectiveLocale = next);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Localizations(
      locale: _effectiveLocale,
      delegates: AppLocalizations.localizationsDelegates,
      child: Builder(
        builder: (context) => Directionality(
          textDirection: WidgetsLocalizations.of(context).textDirection,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Maps a settings.json language tag to a [Locale]; null follows the
/// platform.
Locale? localeFromTag(String? tag) {
  if (tag == null || tag.isEmpty) {
    return null;
  }
  return Locale(tag);
}

extension TricksterLocalizationsBuildContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
