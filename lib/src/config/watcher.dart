import 'dart:async';
import 'dart:io';

class ConfigWatcher {
  ConfigWatcher({
    required this.directory,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 200),
  });

  final Directory directory;
  final void Function() onChanged;
  final Duration debounce;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _timer;

  void start() {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    _subscription = directory.watch().listen((_) {
      _timer?.cancel();
      _timer = Timer(debounce, onChanged);
    });
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
  }
}
