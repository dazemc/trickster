import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/settings/bloc.dart';

/// Applies settings changes as live previews and saves after a short quiet
/// period, so dragging a control or reordering several modules writes the
/// document once. Previews coalesce to at most one per frame: a pointer that
/// reports faster than the display never queues more rebuilds than frames.
class DebouncedSaver {
  DebouncedSaver(this.bloc, {this.delay = const Duration(milliseconds: 300)});

  final SettingsAppBloc bloc;
  final Duration delay;

  Timer? _timer;
  BarSettings? _pending;
  var _previewScheduled = false;

  /// [change] receives the current settings and returns the next ones.
  void apply(BarSettings Function(BarSettings) change) {
    final next = change(bloc.settings);
    _pending = next;
    _timer?.cancel();
    _timer = Timer(delay, () => bloc.add(SettingsAppSaveRequested(next)));
    if (_previewScheduled) {
      return;
    }
    _previewScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _previewScheduled = false;
      final pending = _pending;
      if (pending != null) {
        bloc.add(SettingsAppPreviewed(pending));
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
