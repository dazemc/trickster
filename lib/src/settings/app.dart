import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/settings/availability.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/modules_bloc.dart';
import 'package:trickster/src/settings/pages/about.dart';
import 'package:trickster/src/settings/pages/appearance.dart';
import 'package:trickster/src/settings/pages/displays.dart';
import 'package:trickster/src/settings/pages/language.dart';
import 'package:trickster/src/settings/pages/modules.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';

/// Root of the settings application: the same binary in settings mode, its
/// own process and engine, one plain window, no strip surfaces, no bar blocs.
///
/// The engine hosts one non-implicit view, so like the bar it must build a
/// [View] per reported view; a bare widget tree would render nothing.
class TricksterSettingsApp extends StatefulWidget {
  const TricksterSettingsApp({super.key});

  @override
  State<TricksterSettingsApp> createState() => _TricksterSettingsAppState();
}

class _TricksterSettingsAppState extends State<TricksterSettingsApp> {
  late final SettingsAppBloc _bloc;
  late final WallpaperAccentBloc _wallpaperAccent;

  @override
  void initState() {
    super.initState();
    _bloc = SettingsAppBloc()..add(const SettingsAppLoadRequested());
    _wallpaperAccent = WallpaperAccentBloc();
  }

  @override
  void dispose() {
    unawaited(_bloc.close());
    unawaited(_wallpaperAccent.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return BlocProvider.value(
      value: _bloc,
      child: BlocListener<SettingsAppBloc, SettingsAppState>(
        // The settings process samples the wallpaper itself, so the
        // appearance page can list the accents the bar is choosing from.
        listenWhen: (previous, next) =>
            previous.settings.usesWallpaperAccent !=
            next.settings.usesWallpaperAccent,
        listener: (context, state) => _wallpaperAccent.add(
          WallpaperAccentEnabled(enabled: state.settings.usesWallpaperAccent),
        ),
        child: BlocProvider.value(
          value: _wallpaperAccent,
          child: ViewCollection(
            views: [
              for (final view in views)
                View(
                  view: view,
                  child: Builder(
                    builder: (context) {
                      // Depend on the bloc so a language change rebuilds the
                      // scope with the new catalog.
                      final locale = context
                          .watch<SettingsAppBloc>()
                          .state
                          .settings
                          .locale;
                      return TricksterLocalizationScope(
                        locale: localeFromTag(locale),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                SettingsColors.backgroundTop,
                                SettingsColors.background,
                              ],
                            ),
                          ),
                          child: Overlay(
                            initialEntries: [
                              OverlayEntry(
                                builder: (context) => const SettingsHome(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The settings shell: header plus the page area. Pages arrive in the
/// following steps; this step proves the mode, window, and design language.
class SettingsHome extends StatefulWidget {
  const SettingsHome({
    this.onClose,
    this.availabilityProbe = probeModuleAvailability,
    super.key,
  });

  /// Test seam; production closes the native settings window.
  final VoidCallback? onClose;

  /// Hardware probe for the modules page; tests substitute their own answer.
  final List<ModuleAvailability> Function() availabilityProbe;

  @override
  State<SettingsHome> createState() => _SettingsHomeState();
}

enum SettingsSection { appearance, modules, displays, language, about }

class _SettingsHomeState extends State<SettingsHome> {
  var _section = SettingsSection.appearance;

  void _select(SettingsSection section) => setState(() => _section = section);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.watch<SettingsAppBloc>();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsTitle,
                      style: ShellText.systemBarValue.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.settingsCaption,
                      style: ShellText.systemBarCaption.copyWith(
                        color: ShellMediaColors.lightForegroundSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SettingsCloseButton(
                onPressed:
                    widget.onClose ??
                    () => unawaited(LayerShell().closeSettingsWindow()),
              ),
            ],
          ),
          if (controller.error != null) ...[
            const SizedBox(height: 16),
            SettingsCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                controller.error!,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellTelemetryColors.danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: !controller.loaded
                ? Center(
                    child: Text(
                      l10n.settingsLoading,
                      style: ShellText.systemBarCaption.copyWith(
                        color: ShellMediaColors.lightForegroundSecondary,
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsNav(section: _section, onSelect: _select),
                      const SizedBox(width: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: switch (_section) {
                            SettingsSection.appearance =>
                              const AppearancePage(),
                            SettingsSection.modules =>
                              BlocProvider<ModulesBloc>(
                                create: (context) => ModulesBloc(
                                  settings: context.read<SettingsAppBloc>(),
                                  availabilityProbe: widget.availabilityProbe,
                                ),
                                child: const ModulesPage(),
                              ),
                            SettingsSection.displays => const DisplaysPage(),
                            SettingsSection.language => const LanguagePage(),
                            SettingsSection.about => const AboutPage(),
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The settings window's section list.
class SettingsNav extends StatelessWidget {
  const SettingsNav({required this.section, required this.onSelect, super.key});

  final SettingsSection section;
  final ValueChanged<SettingsSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: 190,
      child: SettingsCard(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          children: [
            _NavEntry(
              label: l10n.settingsAppearanceTitle,
              selected: section == SettingsSection.appearance,
              onPressed: () => onSelect(SettingsSection.appearance),
            ),
            _NavEntry(
              label: l10n.settingsModulesTitle,
              selected: section == SettingsSection.modules,
              onPressed: () => onSelect(SettingsSection.modules),
            ),
            _NavEntry(
              label: l10n.settingsDisplaysTitle,
              selected: section == SettingsSection.displays,
              onPressed: () => onSelect(SettingsSection.displays),
            ),
            _NavEntry(
              label: l10n.settingsLanguageTitle,
              selected: section == SettingsSection.language,
              onPressed: () => onSelect(SettingsSection.language),
            ),
            _NavEntry(
              label: l10n.settingsAboutTitle,
              selected: section == SettingsSection.about,
              onPressed: () => onSelect(SettingsSection.about),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavEntry extends StatelessWidget {
  const _NavEntry({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Motion.standard,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                color: selected
                    ? SettingsColors.surfaceHigh
                    : SettingsColors.surface,
              ),
              child: Text(
                label,
                style: ShellText.systemBarValue.copyWith(
                  color: selected
                      ? ShellMediaColors.lightForeground
                      : ShellMediaColors.lightForegroundSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
