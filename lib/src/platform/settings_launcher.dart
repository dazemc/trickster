import 'dart:io';

/// Starts one process and reports whether it ran. Injected by tests so no
/// real settings window ever opens from a widget test.
typedef DetachedProcessStarter =
    Future<bool> Function(String executable, List<String> arguments);

/// The arguments the settings application is launched with.
///
/// The bar's effective outputs override (`--config PATH` or the session's
/// `output_config`) is forwarded so settings edits the same outputs document
/// the running bar read. Without one, settings resolves its own default.
List<String> settingsLaunchArguments({String? configPath}) {
  final override = configPath;
  return <String>[
    '--settings',
    if (override != null && override.isNotEmpty) ...<String>[
      '--config',
      override,
    ],
  ];
}

/// Launches the bar's settings application: this same executable with
/// `--settings`, detached so the bar's frame loop keeps running.
///
/// [executable] defaults to [Platform.resolvedExecutable], which is the
/// installed `trickster` binary in a packaged release and the build's runner
/// during development. Returns false when the process could not start.
Future<bool> launchTricksterSettings({
  String? executable,
  String? configPath,
  DetachedProcessStarter? start,
}) {
  final binary = executable ?? Platform.resolvedExecutable;
  if (binary.isEmpty) {
    return Future<bool>.value(false);
  }
  return (start ?? _startDetached)(
    binary,
    settingsLaunchArguments(configPath: configPath),
  );
}

Future<bool> _startDetached(String executable, List<String> arguments) async {
  try {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
    return true;
  } on Object {
    // A missing executable or a session without a display leaves the menu
    // dismissed; there is no second candidate to try.
    return false;
  }
}
