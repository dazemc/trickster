class Cli {
  const Cli({
    this.version = false,
    this.check = false,
    this.help = false,
    this.settings = false,
    this.configPath,
    this.edge,
  });

  final bool version;
  final bool check;
  final bool help;
  final bool settings;
  final String? configPath;
  final String? edge;

  static const appVersion = '0.2.0';
  static const versionText = 'trickster $appVersion';

  /// The `--help` text. Man pages are checked against it so the two cannot
  /// drift.
  static const usage = '''
Usage: trickster [OPTIONS]

A Flutter-native Wayland status bar: one layer-shell strip per output.

Options:
  --check          Preflight wayland, configs, layer-shell, blur, and outputs, then exit
  --version        Print the version and exit
  --config PATH    Use PATH as the outputs.conf override for this run
  --edge SIDE      One-shot edge override: top, bottom, left, or right
  --settings       Run the settings application instead of the bar
  -h, --help       Print this help and exit
''';

  /// The `tricksterctl --help` text (see [usage] for the drift check).
  static const ctlUsage = '''
Usage: tricksterctl [COMMAND]

Control client for a running trickster bar over its control socket.

Commands:
  status           Print the running state, outputs, and module states
  version          Print the bar and protocol versions
  reload           Re-read configs now, same path as the file watcher
  -h, --help       Print this help and exit
''';

  static Cli parse(List<String> args) {
    var version = false;
    var check = false;
    var help = false;
    var settings = false;
    String? configPath;
    String? edge;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--version':
          version = true;
        case '--check':
          check = true;
        case '--help':
        case '-h':
          help = true;
        case '--settings':
          settings = true;
        case '--config':
          if (i + 1 >= args.length) {
            throw const FormatException('--config requires a path');
          }
          configPath = args[++i];
        case '--edge':
          if (i + 1 >= args.length) {
            throw const FormatException('--edge requires a side');
          }
          edge = args[++i];
        default:
          if (arg.startsWith('--config=')) {
            configPath = arg.substring('--config='.length);
          } else if (arg.startsWith('--edge=')) {
            edge = arg.substring('--edge='.length);
          } else {
            throw FormatException('unknown argument: $arg');
          }
      }
    }
    return Cli(
      version: version,
      check: check,
      help: help,
      settings: settings,
      configPath: configPath,
      edge: edge,
    );
  }
}
