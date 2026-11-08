import 'dart:io';

/// Starts one detached process; true when the executable ran.
typedef OpencodeAppStarter =
    Future<bool> Function(String executable, List<String> arguments);

/// Where the companion usage window may live, in launch order. The explicit
/// paths win over PATH so a dev build in the user's bin directory is not
/// shadowed by a system copy.
List<String> opencodeUsageCandidates({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final candidates = <String>[];
  void add(String? path) {
    if (path != null && path.isNotEmpty && !candidates.contains(path)) {
      candidates.add(path);
    }
  }

  final xdgBinHome = env['XDG_BIN_HOME'];
  if (xdgBinHome != null && xdgBinHome.isNotEmpty) {
    add('$xdgBinHome/opencode-usage');
  }
  final home = env['HOME'];
  if (home != null && home.isNotEmpty) {
    add('$home/.local/bin/opencode-usage');
  }
  add('/usr/local/bin/opencode-usage');
  add('/usr/bin/opencode-usage');
  add('opencode-usage');
  return candidates;
}

/// Launches the OpenCode usage window. When no candidate starts, falls back
/// to the workspace console URL in the browser so the click still leads
/// somewhere useful. Returns false when neither path worked.
Future<bool> launchOpencodeUsage({
  String? usageUrl,
  Map<String, String>? environment,
  OpencodeAppStarter? start,
}) async {
  final launcher = start ?? _startDetached;
  for (final candidate in opencodeUsageCandidates(environment: environment)) {
    if (await launcher(candidate, const <String>[])) {
      return true;
    }
  }
  if (usageUrl != null && usageUrl.isNotEmpty) {
    return launcher('xdg-open', <String>[usageUrl]);
  }
  return false;
}

Future<bool> _startDetached(String executable, List<String> arguments) async {
  try {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
    return true;
  } on Object {
    // Missing binary or no display: try the next candidate.
    return false;
  }
}
