import 'dart:async';
import 'dart:io';
import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'bar/bar.dart';
import 'bar/tray_menu.dart';
import 'bootstrap.dart';
import 'config/session.dart';
import 'config/watcher.dart';
import 'layout/system_bar.dart';
import 'locale.dart';
import 'platform/layer_shell.dart';
import 'platform/power_settings.dart';
import 'state/module_scope.dart';
import 'state/outputs_bloc.dart';
import 'state/session_bloc.dart';
import 'state/settings_bloc.dart';
import 'state/tray_menu.dart';

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
  late final TrayMenuController _menuController;
  ConfigWatcher? _watcher;
  OutputsConfig _lastOutputs = const OutputsConfig();
  SessionConfig _lastSession = const SessionConfig();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _layerShell = widget.layerShell ?? LayerShell();
    _menuController = TrayMenuController(layerShell: _layerShell);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _apply(widget.initial);
      _watcher = ConfigWatcher(
        directory: widget.initial.paths.directory,
        onChanged: _reload,
      )..start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_watcher?.dispose());
    _menuController.dispose();
    super.dispose();
  }

  // The engine adds a FlutterView per layer surface; a view change must
  // rebuild the root so the new surface gets its own strip.
  @override
  void didChangeMetrics() {
    if (mounted) {
      setState(() {});
    }
  }

  void _reload() {
    try {
      final loaded = Bootstrap.load(
        configPath: widget.initial.paths.outputOverride,
      );
      _apply(loaded);
    } on Object catch (error) {
      stderr.writeln('trickster: keeping last-good config: $error');
    }
  }

  void _apply(RuntimeConfig loaded) {
    context.read<SessionBloc>().add(SessionLoaded(loaded.session));
    context.read<OutputsBloc>().add(OutputsLoaded(loaded.outputs));
    context.read<SettingsBloc>().add(SettingsLoaded(loaded.settings));
    final disruptive =
        loaded.outputs.side != _lastOutputs.side ||
        loaded.outputs.thickness != _lastOutputs.thickness ||
        loaded.session.layer != _lastSession.layer ||
        loaded.session.namespace != _lastSession.namespace ||
        loaded.session.keyboard != _lastSession.keyboard;
    if (disruptive) {
      unawaited(
        _layerShell.configure(outputs: loaded.outputs, session: loaded.session),
      );
    }
    _lastOutputs = loaded.outputs;
    _lastSession = loaded.session;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OutputsBloc, OutputsConfig>(
      builder: (context, outputs) {
        // Bare widgets need explicit directionality and locale; there is no
        // MaterialApp above the strip. The device locale is reduced to one the
        // widgets delegate supports (headless LANG=C environments crash
        // resource resolution otherwise).
        final locale = resolveAppLocale(
          WidgetsBinding.instance.platformDispatcher.locale,
        );
        final views = WidgetsBinding.instance.platformDispatcher.views;
        _menuController.retainViews(views.map((view) => view.viewId).toSet());
        // One View per layer surface, all sharing this single engine and the
        // module blocs above the collection. A menu lives on its own
        // fullscreen overlay surface, so the strip surface never resizes.
        return Localizations(
          locale: locale,
          delegates: const [GlobalWidgetsLocalizations.delegate],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TrayMenuScope(
              notifier: _menuController,
              child: ModuleScope(
                child: ViewCollection(
                  views: outputs.active
                      ? <Widget>[
                          for (final view in views)
                            _ViewSurface(
                              key: ValueKey<int>(view.viewId),
                              view: view,
                              menu: _menuController,
                            ),
                        ]
                      : const <Widget>[],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One output's surface: an [Overlay] so shelf overlays can render above the
/// strip, with either the strip or a tray menu as its single entry.
class _ViewSurface extends StatefulWidget {
  const _ViewSurface({required this.view, required this.menu, super.key});

  final FlutterView view;
  final TrayMenuController menu;

  @override
  State<_ViewSurface> createState() => _ViewSurfaceState();
}

class _ViewSurfaceState extends State<_ViewSurface> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (context) => ListenableBuilder(
      listenable: widget.menu,
      builder: (context, _) {
        final session = widget.menu.session;
        if (widget.menu.isMenuView(widget.view.viewId)) {
          if (session == null || session.viewId != widget.view.viewId) {
            return const SizedBox.shrink();
          }
          return TrayMenuSurface(session: session, controller: widget.menu);
        }
        return const _BarSurface();
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The View starts the render zone; MediaQuery is required by Material
    // menus (and gives each surface its own metrics); TapRegionSurface lets
    // menu panels observe outside taps.
    return View(
      view: widget.view,
      child: MediaQuery.fromView(
        view: widget.view,
        child: TapRegionSurface(child: Overlay(initialEntries: [_entry])),
      ),
    );
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }
}

class _BarSurface extends StatelessWidget {
  const _BarSurface();

  @override
  Widget build(BuildContext context) {
    final outputs = context.watch<OutputsBloc>().state;
    return TricksterBarStrip(
      side: outputs.side,
      thickness: outputs.thickness,
      onOpenPowerSettings: openPowerSettings,
    );
  }
}
