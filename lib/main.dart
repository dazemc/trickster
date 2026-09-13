import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/bootstrap.dart';
import 'src/cli.dart';
import 'src/platform/layer_shell.dart';
import 'src/state/observer.dart';

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
  runApp(ProviderScope(child: TricksterApp(initial: runtime)));
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
