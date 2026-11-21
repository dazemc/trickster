import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/settings/bloc.dart';

/// Applies settings changes as live previews and saves after a short quiet
/// period, so dragging a control or reordering several modules writes the
/// document once. Previews coalesce to at most one per frame: a pointer that
/// reports faster than the display never queues more rebuilds than frames.
///
/// Every page over one settings document leases the same saver, so a module
/// reorder and an options change cannot race two whole-document snapshots.
/// Disposing the last lease flushes the pending edit instead of dropping it.
class DebouncedSaver {
  DebouncedSaver._(this.bloc, this.delay);

  factory DebouncedSaver(
    SettingsAppBloc bloc, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    final existing = _savers[bloc];
    if (existing != null) {
      existing._leases += 1;
      return existing;
    }
    final saver = DebouncedSaver._(bloc, delay).._leases = 1;
    _savers[bloc] = saver;
    return saver;
  }

  static final Expando<DebouncedSaver> _savers = Expando<DebouncedSaver>(
    'settings document saver',
  );

  final SettingsAppBloc bloc;
  final Duration delay;

  Timer? _timer;
  BarSettings? _pending;
  var _previewScheduled = false;
  var _leases = 0;

  /// [change] receives the current settings and returns the next ones.
  void apply(BarSettings Function(BarSettings) change) {
    final next = change(bloc.settings);
    _pending = next;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      final pending = _pending;
      _pending = null;
      if (pending != null && !bloc.isClosed) {
        bloc.add(SettingsAppSaveRequested(pending));
      }
    });
    if (_previewScheduled) {
      return;
    }
    _previewScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _previewScheduled = false;
      final pending = _pending;
      if (pending != null && !bloc.isClosed) {
        bloc.add(SettingsAppPreviewed(pending));
      }
    });
  }

  /// Writes the pending edit now. [wait] waits for the bloc to finish the
  /// write so a close handler can keep the process alive for it.
  Future<void> flush({bool wait = false}) async {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (pending == null || bloc.isClosed) {
      return;
    }
    if (wait) {
      await bloc.saveNow(pending);
    } else {
      bloc.add(SettingsAppSaveRequested(pending));
    }
  }

  /// Flushes the document saver currently leased for [bloc], if any.
  static Future<void> flushFor(SettingsAppBloc bloc, {bool wait = true}) async {
    final saver = _savers[bloc];
    if (saver != null) {
      await saver.flush(wait: wait);
    }
  }

  void dispose({bool flush = true}) {
    if (_leases > 0) {
      _leases -= 1;
    }
    if (_leases > 0) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    _savers[bloc] = null;
    if (flush && pending != null && !bloc.isClosed) {
      bloc.add(SettingsAppSaveRequested(pending));
    }
  }
}
