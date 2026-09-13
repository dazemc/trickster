class Cli {
  const Cli({
    this.version = false,
    this.check = false,
    this.configPath,
    this.edge,
  });

  final bool version;
  final bool check;
  final String? configPath;
  final String? edge;

  static const appVersion = '0.1.0';
  static const versionText = 'trickster $appVersion';

  static Cli parse(List<String> args) {
    var version = false;
    var check = false;
    String? configPath;
    String? edge;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--version':
          version = true;
        case '--check':
          check = true;
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
      configPath: configPath,
      edge: edge,
    );
  }
}
