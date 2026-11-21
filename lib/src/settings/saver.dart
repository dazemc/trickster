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
  BarSettings? _base;
  final _changes = <BarSettings Function(BarSettings)>[];
  var _previewScheduled = false;
  var _leases = 0;

  /// [change] receives the current settings and returns the next ones. A
  /// second independent change in the same frame composes onto the pending
  /// document; the same field still collapses to the latest value.
  void apply(BarSettings Function(BarSettings) change) {
    _base ??= bloc.settings;
    final next = change(_pending ?? bloc.settings);
    _pending = next;
    _changes.add(change);
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      _saveComposed();
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
    final pending = _composedPending();
    _pending = null;
    _base = null;
    _changes.clear();
    if (pending == null || bloc.isClosed) {
      return;
    }
    if (wait) {
      await bloc.saveNow(pending);
    } else {
      bloc.add(SettingsAppSaveRequested(pending));
    }
  }

  void _saveComposed() {
    final pending = _composedPending();
    _pending = null;
    _base = null;
    _changes.clear();
    if (pending != null && !bloc.isClosed) {
      bloc.add(SettingsAppSaveRequested(pending));
    }
  }

  /// If a save landed while this batch was pending, rebuild the batch over
  /// the newer document. Applying to the already-previewed state would
  /// double non-idempotent changes (a keyboard swap), so only rebase when the
  /// document revision actually advanced.
  BarSettings? _composedPending() {
    final base = _base;
    if (_pending == null) {
      return null;
    }
    if (base == null || bloc.settings.revision <= base.revision) {
      return _pending;
    }
    var next = bloc.settings;
    for (final change in _changes) {
      next = change(next);
    }
    return next;
  }

  /// Re-applies the pending batch's change closures onto [latest], so a
  /// control touched during a close flush lands on the newest document rather
  /// than a stale whole snapshot.
  void rebase(BarSettings latest) {
    if (_pending == null) {
      return;
    }
    var next = latest;
    for (final change in _changes) {
      next = change(next);
    }
    _pending = next;
    _base = latest;
  }

  /// Whether this document still has an unsaved edit or a live debounce.
  static bool hasPendingFor(SettingsAppBloc bloc) {
    final saver = _savers[bloc];
    return saver != null && (saver._pending != null || saver._timer != null);
  }

  /// Flushes the document saver currently leased for [bloc], if any.
  static Future<void> flushFor(SettingsAppBloc bloc, {bool wait = true}) async {
    final saver = _savers[bloc];
    if (saver != null) {
      await saver.flush(wait: wait);
    }
  }

  /// Rebases the pending batch for [bloc] onto [latest], if one exists.
  static void rebaseFor(SettingsAppBloc bloc, BarSettings latest) {
    _savers[bloc]?.rebase(latest);
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
    final pending = _composedPending();
    _pending = null;
    _base = null;
    _changes.clear();
    _savers[bloc] = null;
    if (flush && pending != null && !bloc.isClosed) {
      bloc.add(SettingsAppSaveRequested(pending));
    }
  }
}
