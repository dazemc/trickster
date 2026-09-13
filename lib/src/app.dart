import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bar/bar.dart';
import 'bootstrap.dart';
import 'config/session.dart';
import 'config/watcher.dart';
import 'layout/system_bar.dart';
import 'platform/layer_shell.dart';
import 'state/providers.dart';

class TricksterApp extends ConsumerStatefulWidget {
  const TricksterApp({
    required this.initial,
    this.layerShell,
    super.key,
  });

  final RuntimeConfig initial;
  final LayerShell? layerShell;

  @override
  ConsumerState<TricksterApp> createState() => _TricksterAppState();
}

class _TricksterAppState extends ConsumerState<TricksterApp> {
  late final LayerShell _layerShell;
  ConfigWatcher? _watcher;
  OutputsConfig _lastOutputs = const OutputsConfig();
  SessionConfig _lastSession = const SessionConfig();

  @override
  void initState() {
    super.initState();
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
    unawaited(_watcher?.dispose());
    super.dispose();
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
    ref.read(sessionProvider.notifier).state = loaded.session;
    ref.read(outputsProvider.notifier).state = loaded.outputs;
    ref.read(settingsProvider.notifier).state = loaded.settings;
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
    final outputs = ref.watch(outputsProvider);
    if (!outputs.active) {
      return const ColoredBox(color: Color(0x00000000));
    }
    // Bare widgets need explicit directionality and locale; there is no
    // MaterialApp above the strip.
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    return Localizations(
      locale: locale,
      delegates: const [GlobalWidgetsLocalizations.delegate],
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0x00000000),
          child: TricksterBarStrip(side: outputs.side),
        ),
      ),
    );
  }
}
