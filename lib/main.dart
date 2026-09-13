import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'src/app.dart';
import 'src/bootstrap.dart';
import 'src/cli.dart';
import 'src/platform/layer_shell.dart';
import 'src/state/observer.dart';
import 'src/state/outputs_bloc.dart';
import 'src/state/session_bloc.dart';
import 'src/state/settings_bloc.dart';

Future<void> main(List<String> args) async {
  final cli = Cli.parse(args);
  if (cli.version) {
    stdout.writeln(Cli.versionText);
    return;
  }
  if (cli.check) {
    await _check(cli);
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  installObserver();
  final runtime = Bootstrap.load(
    configPath: cli.configPath,
    edge: cli.edge,
  );
  // Config blocs live above the app; ModuleScope (inside TricksterApp)
  // builds one provider per enabled module below SettingsBloc so live
  // reloads can add and remove module blocs with the module list.
  //
  // runWidget, not runApp: the native runner creates one FlutterView per
  // layer surface and TricksterApp builds a View for each.
  runWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SettingsBloc(runtime.settings)),
        BlocProvider(create: (_) => SessionBloc(runtime.session)),
        BlocProvider(create: (_) => OutputsBloc(runtime.outputs)),
      ],
      child: TricksterApp(initial: runtime),
    ),
  );
}

Future<void> _check(Cli cli) async {
  var failed = false;
  void ok(String name, String detail) => stdout.writeln('ok    $name: $detail');
  void bad(String name, String detail) {
    failed = true;
    stderr.writeln('fail  $name: $detail');
  }

  final display = Platform.environment['WAYLAND_DISPLAY'];
  if (display == null || display.isEmpty) {
    bad('wayland', 'WAYLAND_DISPLAY is unset');
  } else {
    ok('wayland', display);
  }

  try {
    final runtime = Bootstrap.load(configPath: cli.configPath, edge: cli.edge);
    ok(
      'outputs.conf',
      '${runtime.outputs.side.name},${runtime.outputs.thickness.round()}',
    );
    ok('settings.json', 'revision ${runtime.settings.revision}');
  } on Object catch (error) {
    bad('config', '$error');
  }

  try {
    WidgetsFlutterBinding.ensureInitialized();
    final layer = LayerShell();
    final supported = await layer.isSupported();
    if (supported) {
      ok('layer-shell', 'zwlr_layer_shell_v1 advertised');
    } else {
      bad('layer-shell', 'compositor does not advertise zwlr_layer_shell_v1');
    }
    final outputs = await layer.outputs();
    if (outputs.isEmpty) {
      bad('outputs', 'no monitors reported');
    } else {
      ok('outputs', outputs.map((output) => output.name).join(', '));
    }
  } on Object catch (error) {
    bad('layer-shell', '$error');
  }

  if (failed) {
    exitCode = 1;
  }
}
