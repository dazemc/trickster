import 'dart:async';

import '../config/settings.dart';
import 'controller.dart';

/// Applies a settings change to the controller immediately (live preview)
/// and saves it after a short quiet period, so dragging a control or
/// reordering several modules writes the document once.
class DebouncedSaver {
  DebouncedSaver(
    this.controller, {
    this.delay = const Duration(milliseconds: 300),
  });

  final SettingsAppController controller;
  final Duration delay;

  Timer? _timer;

  /// [change] receives the current settings and returns the next ones.
  void apply(BarSettings Function(BarSettings) change) {
    final next = change(controller.settings);
    controller.preview(next);
    _timer?.cancel();
    _timer = Timer(delay, () {
      unawaited(controller.save(next));
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
