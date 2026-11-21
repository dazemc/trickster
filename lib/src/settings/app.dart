import 'dart:async';
import 'dart:io' show FileSystemEvent, FileSystemMoveEvent, Platform;
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' show Scrollbar;
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/watcher.dart';
import 'package:trickster/src/layout/shell_keys.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/settings/availability.dart';
import 'package:trickster/src/settings/availability_loader.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/modules_bloc.dart';
import 'package:trickster/src/settings/pages/about.dart';
import 'package:trickster/src/settings/pages/appearance.dart';
import 'package:trickster/src/settings/pages/displays.dart';
import 'package:trickster/src/settings/pages/language.dart';
import 'package:trickster/src/settings/pages/modules.dart';
import 'package:trickster/src/settings/saver.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/settings/wallpaper_loader.dart';
import 'package:trickster/src/state/capabilities_bloc.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';

/// Whether a config-directory event names a document both processes edit.
/// Atomic writes also create `.tmp` and `.prev` neighbours; those must not
/// schedule a reload.
bool isEditedDocumentEvent(FileSystemEvent event) {
  bool edited(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name == 'settings.json' || name == 'outputs.conf';
  }

  if (edited(event.path)) {
    return true;
  }
  // Atomic replace reports the temporary source path with the live document
  // as the destination.
  return event is FileSystemMoveEvent &&
      event.destination != null &&
      edited(event.destination!);
}

/// The wallpaper event a settings state transition needs, if any.
///
/// A source transition enables or disables the sampler. A revision change
/// while the wallpaper is active means a save (or an external write) landed;
/// the bar may only now be reloading the document that enables its sampler, so
/// refresh rather than waiting for a reopen. Busy/preview emissions keep the
/// revision and do no work.
WallpaperAccentEvent? wallpaperAccentEventFor(
  SettingsAppState previous,
  SettingsAppState next,
) {
  final wasWallpaper = previous.settings.usesWallpaperAccent;
  final isWallpaper = next.settings.usesWallpaperAccent;
  if (wasWallpaper != isWallpaper) {
    return WallpaperAccentEnabled(enabled: isWallpaper);
  }
  if (isWallpaper && previous.settings.revision != next.settings.revision) {
    return const WallpaperAccentRefreshRequested();
  }
  return null;
}

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

class _TricksterSettingsAppState extends State<TricksterSettingsApp>
    with WidgetsBindingObserver {
  late final SettingsAppBloc _bloc;
  late final WallpaperAccentBloc _wallpaperAccent;
  late SettingsAppState _lastAppState;
  ConfigWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    _bloc = SettingsAppBloc()..add(const SettingsAppLoadRequested());
    _lastAppState = _bloc.state;
    // The bar may write the document while this window is open (the media
    // pill's mode cycle); reload so the pages show what the bar shows.
    _watcher = ConfigWatcher(
      directory: ConfigPaths().directory,
      include: isEditedDocumentEvent,
      onChanged: () {
        // The watcher reports the directory, not the file. Refresh both
        // documents; each handler preserves an unsaved local draft.
        _bloc
          ..add(const SettingsAppDocumentChanged())
          ..add(const SettingsAppOutputsChanged());
      },
    )..start();
    _wallpaperAccent = WallpaperAccentBloc(
      remoteProbe: loadBarWallpaperAccentProbe,
      outputs: () => _bloc.availableOutputs,
      strip: () =>
          (side: _bloc.outputs.side, thickness: _bloc.outputs.thickness),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  /// Re-reads the bar's candidates when the window regains platform focus or
  /// the app resumes. No timer and no poll: the event only runs while the
  /// wallpaper source is enabled.
  void _refreshWallpaper() {
    if (!mounted || _wallpaperAccent.isClosed) {
      return;
    }
    _wallpaperAccent.add(const WallpaperAccentRefreshRequested());
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.focused) {
      _refreshWallpaper();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshWallpaper();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_watcher?.dispose());
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
        // Prefer the bar's already-sampled wallpaper state; the local
        // sampler remains the fallback when no bar answers. A save revision
        // refresh lets the bar catch up after this process wrote the source.
        listener: (context, state) {
          final event = wallpaperAccentEventFor(_lastAppState, state);
          _lastAppState = state;
          if (event != null) {
            _wallpaperAccent.add(event);
          }
        },
        child: BlocProvider.value(
          value: _wallpaperAccent,
          child: BlocProvider<CapabilitiesBloc>(
            create: (_) =>
                CapabilitiesBloc()..add(const CapabilitiesProbeRequested()),
            child: ViewCollection(
              views: [
                for (final view in views)
                  View(
                    view: view,
                    child: MediaQuery.fromView(
                      view: view,
                      child: Shortcuts(
                        shortcuts: shellShortcuts,
                        child: Actions(
                          actions: WidgetsApp.defaultActions,
                          // Text fields in this window need the platform's
                          // editing keys (backspace, select all, clipboard)
                          // that a WidgetsApp would normally install.
                          child: DefaultTextEditingShortcuts(
                            child: FocusScope(
                              autofocus: true,
                              child: Builder(
                                builder: (context) {
                                  // Depend on the bloc so a language change
                                  // rebuilds the scope with the new catalog.
                                  final locale = context.select(
                                    (SettingsAppBloc bloc) =>
                                        bloc.state.settings.locale,
                                  );
                                  // With the compositor blurring behind the
                                  // toplevel, the shell veils it with
                                  // translucent fills; without the protocol, or
                                  // with the document's blur key off, the
                                  // window stays opaque.
                                  final glass = settingsGlassEnabled(
                                    hostBlur: context
                                        .watch<CapabilitiesBloc>()
                                        .state
                                        .blur,
                                    documentBlur: context.select(
                                      (SettingsAppBloc bloc) =>
                                          bloc.state.settings.appearance.blur,
                                    ),
                                  );
                                  return TricksterLocalizationScope(
                                    locale: localeFromTag(locale),
                                    child: SettingsGlass(
                                      enabled: glass,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              glass
                                                  ? SettingsColors.backgroundTop
                                                        .withValues(alpha: 0.55)
                                                  : SettingsColors
                                                        .backgroundTop,
                                              glass
                                                  ? SettingsColors.background
                                                        .withValues(alpha: 0.62)
                                                  : SettingsColors.background,
                                            ],
                                          ),
                                        ),
                                        child: Overlay(
                                          initialEntries: [
                                            OverlayEntry(
                                              builder: (context) =>
                                                  const SettingsHome(),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
    this.availabilityProbe,
    this.availabilityLoader,
    this.workspaceNames,
    super.key,
  });

  /// Test seam; production closes the native settings window.
  final VoidCallback? onClose;

  /// Synchronous hardware probe for the modules page. Null uses the
  /// production probe; tests substitute their own answer.
  final List<ModuleAvailability> Function()? availabilityProbe;

  /// Asynchronous availability refresh, normally the running bar's control
  /// status. Tests may inject one; when [availabilityProbe] is supplied
  /// without this, the page stays on the synchronous probe.
  final Future<List<ModuleAvailability>> Function(BarSettings settings)?
  availabilityLoader;

  /// Source of live workspace names for the pip mapping editor; null asks
  /// the running bar over the control socket.
  final Future<List<String>> Function()? workspaceNames;

  /// The widest the page column grows on a wide window; controls keep their
  /// labels close on a 1920px display.
  static const double maxContentWidth = 1120;

  @override
  State<SettingsHome> createState() => _SettingsHomeState();
}

enum SettingsSection { appearance, modules, displays, language, about }

class _SettingsHomeState extends State<SettingsHome> {
  var _section = SettingsSection.appearance;
  final ScrollController _pageScroll = ScrollController();
  StreamSubscription<void>? _closeRequests;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _closeRequests = LayerShell.settingsCloseRequests.listen(
      (_) => unawaited(_close()),
    );
  }

  Future<void> _flushDocuments() async {
    final bloc = context.read<SettingsAppBloc>();
    await DebouncedSaver.flushFor(bloc);
    await bloc.settled;
    await bloc.flushOutputs();
    await bloc.settled;
  }

  Future<void> _select(SettingsSection section) async {
    // A debounced edit belongs to the document, not to the page that happens
    // to be mounted when the user navigates away.
    await _flushDocuments();
    if (!mounted) {
      return;
    }
    setState(() => _section = section);
  }

  Future<void> _close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    try {
      while (mounted) {
        await _flushDocuments();
        if (!mounted) {
          return;
        }
        final bloc = context.read<SettingsAppBloc>();
        if (!DebouncedSaver.hasPendingFor(bloc) && !bloc.hasPendingOutputs) {
          break;
        }
        if (DateTime.now().isAfter(deadline)) {
          break;
        }
        // A control touched while the gated save was in flight has a stale
        // draft base. Rebase its change closures onto the newest document
        // before the next flush; then let the new debounce settle.
        try {
          DebouncedSaver.rebaseFor(bloc, await bloc.readLatest());
        } on Object {
          // Fall through to the normal flush/error path.
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } on Object {
      // A failed flush must not leave the window unclosable; the native
      // titlebar fallback is the final backstop either way.
    }
    if (!mounted) {
      return;
    }
    _closing = false;
    if (widget.onClose != null) {
      widget.onClose!();
      return;
    }
    await LayerShell().closeSettingsWindow();
  }

  @override
  void dispose() {
    unawaited(_closeRequests?.cancel());
    _pageScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The shell itself reads only the load state and the error; a settings
    // preview never rebuilds the header and nav.
    final (loaded, error) = context.select(
      (SettingsAppBloc bloc) => (bloc.state.loaded, bloc.state.error),
    );
    final availabilityProbe =
        widget.availabilityProbe ?? probeModuleAvailability;
    final availabilityLoader =
        widget.availabilityLoader ??
        (widget.availabilityProbe == null
            ? (settings) => loadModuleAvailability(settings: settings)
            : null);
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
              SettingsCloseButton(onPressed: () => unawaited(_close())),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            SettingsCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                error,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellTelemetryColors.danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: !loaded
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
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final width =
                                constraints.maxWidth <
                                    SettingsHome.maxContentWidth
                                ? constraints.maxWidth
                                : SettingsHome.maxContentWidth;
                            return Align(
                              alignment: Alignment.topLeft,
                              child: SizedBox(
                                width: width,
                                child: Scrollbar(
                                  controller: _pageScroll,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _pageScroll,
                                    child: SizedBox(
                                      width: width,
                                      child: switch (_section) {
                                        SettingsSection.appearance =>
                                          const AppearancePage(),
                                        SettingsSection.modules =>
                                          BlocProvider<ModulesBloc>(
                                            create: (context) => ModulesBloc(
                                              settings: context
                                                  .read<SettingsAppBloc>(),
                                              availabilityProbe:
                                                  availabilityProbe,
                                              availabilityLoader:
                                                  availabilityLoader,
                                            ),
                                            child: ModulesPage(
                                              workspaceNames:
                                                  widget.workspaceNames,
                                            ),
                                          ),
                                        SettingsSection.displays =>
                                          const DisplaysPage(),
                                        SettingsSection.language =>
                                          const LanguagePage(),
                                        SettingsSection.about =>
                                          const AboutPage(),
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
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
              duration: Motion.duration(context, Motion.pill),
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
