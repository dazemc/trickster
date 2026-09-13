import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'bar/bar.dart';
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

class TricksterApp extends StatefulWidget {
  const TricksterApp({
    required this.initial,
    this.layerShell,
    super.key,
  });

  final RuntimeConfig initial;
  final LayerShell? layerShell;

  @override
  State<TricksterApp> createState() => _TricksterAppState();
}

class _TricksterAppState extends State<TricksterApp>
    with WidgetsBindingObserver {
  late final LayerShell _layerShell;
  ConfigWatcher? _watcher;
  OutputsConfig _lastOutputs = const OutputsConfig();
  SessionConfig _lastSession = const SessionConfig();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _layerShell = widget.layerShell ?? LayerShell();
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
        // One View per layer surface, all sharing this single engine and the
        // module blocs above the collection. RenderObject widgets may not sit
        // between the collection and its views, so the per-surface background
        // lives inside each View.
        return Localizations(
          locale: locale,
          delegates: const [GlobalWidgetsLocalizations.delegate],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ModuleScope(
              child: ViewCollection(
                views: outputs.active
                    ? <Widget>[
                        for (final view
                            in WidgetsBinding
                                .instance
                                .platformDispatcher
                                .views)
                          View(
                            key: ValueKey<int>(view.viewId),
                            view: view,
                            child: ColoredBox(
                              color: const Color(0x00000000),
                              child: TricksterBarStrip(
                                side: outputs.side,
                                onOpenPowerSettings: openPowerSettings,
                              ),
                            ),
                          ),
                      ]
                    : const <Widget>[],
              ),
            ),
          ),
        );
      },
    );
  }
}
