import 'dart:async';
import 'dart:io';
import 'dart:ui' show FlutterView, Rect;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/blur_region.dart';
import 'package:trickster/src/bar/overlay_tooltip.dart';
import 'package:trickster/src/bar/tray_menu.dart';
import 'package:trickster/src/bootstrap.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/session.dart';
import 'package:trickster/src/config/settings.dart' show BarSettings;
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/config/watcher.dart';
import 'package:trickster/src/control/control_handler.dart';
import 'package:trickster/src/control/control_server.dart';
import 'package:trickster/src/layout/shell_keys.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/platform/power_settings.dart';
import 'package:trickster/src/services/status_notifier.dart'
    show SystemTrayAction;
import 'package:trickster/src/state/capabilities_bloc.dart';
import 'package:trickster/src/state/module_scope.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/tray_menu.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/theme/backdrop_blur.dart';

class TricksterApp extends StatefulWidget {
  const TricksterApp({required this.initial, this.layerShell, super.key});

  final RuntimeConfig initial;
  final LayerShell? layerShell;

  @override
  State<TricksterApp> createState() => _TricksterAppState();
}

class _TricksterAppState extends State<TricksterApp>
    with WidgetsBindingObserver {
  late final LayerShell _layerShell;
  late final TrayMenuBloc _menuBloc;
  late final OverlayTooltipBloc _tooltipBloc;
  late final WallpaperAccentBloc _wallpaperAccent;
  late final FileSettingsTransport _settingsTransport;
  late final OutputsDocumentTransport _outputsTransport;
  ControlServer? _control;
  BuildContext? _moduleContext;
  ConfigWatcher? _watcher;
  List<LayerOutput>? _outputs;
  final Set<int> _hiddenSurfaces = <int>{};
  Set<int> _lastBarViews = const <int>{};
  var _reconciling = false;
  var _reconcileAgain = false;
  OutputsConfig _lastOutputs = const OutputsConfig();
  SessionConfig _lastSession = const SessionConfig();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _layerShell = widget.layerShell ?? LayerShell();
    _menuBloc = TrayMenuBloc(
      layerShell: _layerShell,
      onUnavailable: (item, position) {
        final context = _moduleContext;
        if (context == null) {
          return;
        }
        unawaited(
          context.read<TrayBloc>().invoke(
            item,
            SystemTrayAction.contextMenu,
            position,
          ),
        );
      },
    );
    _tooltipBloc = OverlayTooltipBloc(layerShell: _layerShell);
    _wallpaperAccent = WallpaperAccentBloc(
      outputs: () => _outputs ?? const <LayerOutput>[],
      strip: () => (side: _lastOutputs.side, thickness: _lastOutputs.thickness),
    );
    _settingsTransport = FileSettingsTransport(
      File(widget.initial.paths.settings),
    );
    _outputsTransport = FileOutputsTransport(
      File(widget.initial.paths.outputs),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _apply(widget.initial);
      _wallpaperAccent.add(
        WallpaperAccentEnabled(
          enabled: widget.initial.settings.usesWallpaperAccent,
        ),
      );
      _watcher = ConfigWatcher(
        directory: widget.initial.paths.directory,
        onChanged: _reload,
      )..start();
      _control = ControlServer(
        handler: (request) => handleControlRequest(
          context: _moduleContext ?? context,
          settings: _settingsTransport,
          outputs: _outputsTransport,
          reload: _reload,
          request: request,
        ),
      );
      unawaited(_control!.start());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_watcher?.dispose());
    unawaited(_control?.dispose());
    unawaited(_menuBloc.close());
    unawaited(_tooltipBloc.close());
    unawaited(_wallpaperAccent.close());
    super.dispose();
  }

  // The engine adds a FlutterView per layer surface; a view change must
  // rebuild the root so the new surface gets its own strip.
  @override
  void didChangeMetrics() {
    if (!mounted) {
      return;
    }
    setState(() {});
    // Menu and tooltip surfaces add and remove views too; only bar-view
    // changes matter. Their remembered views are trimmed to the live set so
    // a reused id never keeps rendering an overlay.
    final liveViewIds = WidgetsBinding.instance.platformDispatcher.views
        .map((view) => view.viewId)
        .toSet();
    _menuBloc.add(TrayMenuViewsRetained(liveViewIds));
    _tooltipBloc.add(OverlayTooltipViewsRetained(liveViewIds));
    final barViews = liveViewIds
        .where(
          (viewId) =>
              !_menuBloc.state.isMenuView(viewId) &&
              !_tooltipBloc.state.isTooltipView(viewId),
        )
        .toSet();
    if (!setEquals(barViews, _lastBarViews)) {
      _lastBarViews = barViews;
      unawaited(_reconcileOutputs(context.read<OutputsBloc>().state));
    }
  }

  /// Re-reads every config through the watcher's path. Returns null on a
  /// clean apply, or the parse error after keeping last-good state.
  String? _reload() {
    try {
      final loaded = Bootstrap.load(
        configPath: widget.initial.paths.outputOverride,
        strict: true,
      );
      _apply(loaded);
      return null;
    } on Object catch (error) {
      stderr.writeln('trickster: keeping last-good config: $error');
      return '$error';
    }
  }

  void _apply(RuntimeConfig loaded) {
    context.read<SessionBloc>().add(SessionLoaded(loaded.session));
    context.read<SettingsBloc>().add(SettingsLoaded(loaded.settings));
    final sessionChanged =
        loaded.session.layer != _lastSession.layer ||
        loaded.session.namespace != _lastSession.namespace ||
        loaded.session.keyboard != _lastSession.keyboard;
    final disruptive =
        loaded.outputs.side != _lastOutputs.side ||
        loaded.outputs.thickness != _lastOutputs.thickness ||
        sessionChanged;
    context.read<OutputsBloc>().add(OutputsLoaded(loaded.outputs));
    _lastOutputs = loaded.outputs;
    _lastSession = loaded.session;
    if (disruptive) {
      unawaited(_recreateSurfaces(loaded));
    } else {
      unawaited(_reconcileOutputs(loaded.outputs));
    }
  }

  /// Rebuilds every strip for a disruptive change (edge, thickness, layer,
  /// keyboard). Strips are destroyed before replacements are created: the
  /// engine survives on its bootstrap view, and two mapped strips on one
  /// monitor would make GTK abort waiting for a frame of the new size.
  Future<void> _recreateSurfaces(RuntimeConfig loaded) async {
    // Destroy first: applying a new size to mapped strips makes GTK wait
    // for a frame of the new size while Flutter still renders the old one,
    // which aborts. The engine survives on its bootstrap view.
    final outputs = await _layerShell.outputs();
    for (final output in outputs) {
      if (output.viewId > 0) {
        _hiddenSurfaces.remove(output.viewId);
        await _layerShell.destroySurface(viewId: output.viewId);
      }
    }
    await _layerShell.configure(
      outputs: loaded.outputs,
      session: loaded.session,
    );
    await _reconcileOutputs(loaded.outputs);
  }

  /// Creates, hides, or destroys strip surfaces so exactly the hosted
  /// outputs carry one, following monitor hotplug and connector changes.
  Future<void> _reconcileOutputs(OutputsConfig config) async {
    if (_reconciling) {
      _reconcileAgain = true;
      return;
    }
    _reconciling = true;
    try {
      do {
        _reconcileAgain = false;
        final outputs = await _layerShell.outputs();
        if (!mounted) {
          return;
        }
        final changed = !setEquals(
          outputs.map((output) => output.name).toSet(),
          (_outputs ?? const <LayerOutput>[])
              .map((output) => output.name)
              .toSet(),
        );
        setState(() => _outputs = outputs);
        if (changed) {
          // A new display set resamples screencopy accents.
          _wallpaperAccent.add(const WallpaperAccentSampleRequested());
        }
        for (final output in outputs) {
          if (config.hosts(output.name)) {
            if (output.viewId < 0) {
              await _layerShell.createSurface(connector: output.name);
            } else if (_hiddenSurfaces.remove(output.viewId)) {
              await _layerShell.setSurfaceVisible(
                viewId: output.viewId,
                visible: true,
              );
            }
          } else if (output.viewId == 0) {
            if (_hiddenSurfaces.add(0)) {
              await _layerShell.setSurfaceVisible(viewId: 0, visible: false);
            }
          } else if (output.viewId > 0) {
            await _layerShell.destroySurface(viewId: output.viewId);
          }
        }
      } while (_reconcileAgain && mounted);
    } finally {
      _reconciling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.select((SettingsBloc bloc) => bloc.state.locale);
    return BlocListener<SettingsBloc, BarSettings>(
      listenWhen: (previous, next) =>
          previous.accentSource != next.accentSource ||
          previous.displayAppearance != next.displayAppearance,
      listener: (context, settings) => _wallpaperAccent.add(
        WallpaperAccentEnabled(enabled: settings.usesWallpaperAccent),
      ),
      child: BlocProvider.value(
        value: _wallpaperAccent,
        child: TricksterLocalizationScope(
          locale: localeFromTag(locale),
          child: BlocBuilder<OutputsBloc, OutputsConfig>(
            builder: (context, outputs) {
              final views = WidgetsBinding.instance.platformDispatcher.views;
              // One View per layer surface, all sharing this single engine and
              // the module blocs above the collection. A menu lives on its own
              // fullscreen overlay surface, so the strip surface never resizes.
              final blur =
                  context.select((CapabilitiesBloc bloc) => bloc.state.blur) &&
                  context.select(
                    (SettingsBloc bloc) => bloc.state.appearance.blur,
                  );
              // Null until the native enumeration lands: show every strip in the
              // meantime rather than flashing an empty desktop. Overlay surfaces
              // (menus, tooltips) belong to no output's strip, so they are always
              // attached once the engine adds their views.
              final hostedViewIds = _outputs == null
                  ? null
                  : <int>{
                      for (final output in hostedOutputs(_outputs!, outputs))
                        output.viewId,
                      for (final view in views)
                        if (_menuBloc.state.isMenuView(view.viewId) ||
                            _tooltipBloc.state.isTooltipView(view.viewId))
                          view.viewId,
                    };
              final viewOutputs = <int, String>{
                for (final output in _outputs ?? const <LayerOutput>[])
                  if (output.viewId >= 0) output.viewId: output.name,
              };
              return BlocProvider<TrayMenuBloc>.value(
                value: _menuBloc,
                child: BlocProvider<OverlayTooltipBloc>.value(
                  value: _tooltipBloc,
                  child: ModuleScope(
                    // The control status handler needs a context below the module
                    // providers to read their states.
                    child: Builder(
                      builder: (context) {
                        _moduleContext = context;
                        return ViewCollection(
                          views: outputs.active
                              ? <Widget>[
                                  for (final view in views)
                                    if (hostedViewIds == null ||
                                        hostedViewIds.contains(view.viewId))
                                      _ViewSurface(
                                        key: ValueKey<int>(view.viewId),
                                        view: view,
                                        layerShell: _layerShell,
                                        blur: blur,
                                        output: viewOutputs[view.viewId],
                                      ),
                                ]
                              : const <Widget>[],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One output's surface: an [Overlay] so shelf overlays can render above the
/// strip, with either the strip or a tray menu as its single entry.
class _ViewSurface extends StatefulWidget {
  const _ViewSurface({
    required this.view,
    required this.layerShell,
    required this.blur,
    required this.output,
    super.key,
  });

  final FlutterView view;
  final LayerShell layerShell;
  final bool blur;
  final String? output;

  @override
  State<_ViewSurface> createState() => _ViewSurfaceState();
}

class _ViewSurfaceState extends State<_ViewSurface> {
  BlurRegionController? _blurRegions;

  @override
  void initState() {
    super.initState();
    _syncBlur();
  }

  @override
  void didUpdateWidget(covariant _ViewSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blur != widget.blur) {
      _syncBlur();
    }
  }

  /// Whether this surface hosts an overlay instead of the strip.
  bool get _isOverlayView {
    return context.read<TrayMenuBloc>().state.isMenuView(widget.view.viewId) ||
        context.read<OverlayTooltipBloc>().state.isTooltipView(
          widget.view.viewId,
        );
  }

  void _syncBlur() {
    // Backdrop blur belongs to the strip only: overlay surfaces composite
    // their own glass and an effect on a hidden overlay black-screens it.
    if (_isOverlayView) {
      return;
    }
    if (widget.blur) {
      _blurRegions ??= BlurRegionController(
        onRegions: (regions) => unawaited(
          widget.layerShell.setBlurRegions(
            viewId: widget.view.viewId,
            regions: regions,
          ),
        ),
      );
      _blurRegions!.resend();
      _entry.markNeedsBuild();
      return;
    }
    if (_blurRegions == null) {
      return;
    }
    _blurRegions!.dispose();
    _blurRegions = null;
    _entry.markNeedsBuild();
    unawaited(
      widget.layerShell.setBlurRegions(
        viewId: widget.view.viewId,
        regions: const <Rect>[],
      ),
    );
  }

  late final OverlayEntry _entry = OverlayEntry(
    builder: (context) => BlocBuilder<TrayMenuBloc, TrayMenuState>(
      builder: (context, menuState) =>
          BlocBuilder<OverlayTooltipBloc, OverlayTooltipState>(
            builder: (context, tooltipState) {
              if (menuState.isMenuView(widget.view.viewId)) {
                final session = menuState.session;
                if (session == null || session.viewId != widget.view.viewId) {
                  return const SizedBox.shrink();
                }
                return TrayMenuSurface(session: session);
              }
              if (tooltipState.isTooltipView(widget.view.viewId)) {
                final session = tooltipState.session;
                if (session == null || session.viewId != widget.view.viewId) {
                  return const SizedBox.shrink();
                }
                return OverlayTooltipSurface(session: session);
              }
              return BlurRegionScope(
                controller: _blurRegions,
                child: _BarSurface(output: widget.output),
              );
            },
          ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The View starts the render zone; MediaQuery is required by Material
    // menus (and gives each surface its own metrics); TapRegionSurface lets
    // menu panels observe outside taps.
    // No WidgetsApp above the bar, so install the standard shell keymap by
    // hand: Tab and arrow traversal, Enter/Space activation, Escape dismissal.
    return View(
      view: widget.view,
      child: MediaQuery.fromView(
        view: widget.view,
        child: Shortcuts(
          shortcuts: shellShortcuts,
          child: Actions(
            actions: WidgetsApp.defaultActions,
            // Autofocus gives the view a key target, so Tab reaches the
            // shortcut map instead of dying on the root scope.
            child: FocusScope(
              autofocus: true,
              child: TapRegionSurface(child: Overlay(initialEntries: [_entry])),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _blurRegions?.dispose();
    _entry.dispose();
    super.dispose();
  }
}

class _BarSurface extends StatelessWidget {
  const _BarSurface({required this.output});

  final String? output;

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<OutputsBloc>().state;
    final blur =
        context.select((CapabilitiesBloc bloc) => bloc.state.blur) &&
        context.select((SettingsBloc bloc) => bloc.state.appearance.blur);
    return BackdropBlur(
      enabled: blur,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // A scrolled pill translates a cached layer instead of repainting;
          // re-query the live rects so its blur follows.
          if (notification is ScrollUpdateNotification) {
            BlurRegionScope.maybeOf(context)?.resend();
          }
          return false;
        },
        child: TricksterBarStrip(
          side: layout.side,
          thickness: layout.thickness,
          output: output,
          onOpenPowerSettings: openPowerSettings,
        ),
      ),
    );
  }
}
