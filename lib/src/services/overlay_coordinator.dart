/// The transient surfaces the bar can show at once.
enum OverlayKind { trayMenu, calendar, volumeSlider, tooltip }

/// App-owned mutual exclusion for the bar's overlay blocs.
///
/// The tray menu, calendar, and volume slider are modal: at most one is open,
/// and an open modal excludes tooltips. A tooltip is non-modal relative to
/// another tooltip and retargets in place. The coordinator owns only claims
/// and dismissal order; every overlay bloc keeps its own surface lifecycle
/// and generation guard.
class OverlayCoordinator {
  OverlayCoordinator({this.dismissTimeout = const Duration(milliseconds: 500)});

  /// Upper bound for one overlay's dismissal during a transition. A dead
  /// surface must never hold the next open indefinitely.
  final Duration dismissTimeout;

  final Map<OverlayKind, Future<void> Function()> _dismissers = {};
  OverlayKind? _modal;
  var _tooltip = false;
  var _disposed = false;
  Future<void> _queue = Future<void>.value();

  /// Whether a modal currently owns the overlay slot.
  bool get hasModal => _modal != null;

  /// Whether a tooltip currently owns the non-modal slot.
  bool get hasTooltip => _tooltip;

  /// Registers the bloc that owns [kind]'s dismissal.
  void register(OverlayKind kind, Future<void> Function() dismiss) {
    _dismissers[kind] = dismiss;
  }

  /// Drops [kind]'s registration at teardown.
  void unregister(OverlayKind kind) {
    _dismissers.remove(kind);
  }

  /// Requests [kind], closing whatever the policy requires first.
  ///
  /// Returns false only for a tooltip requested while a modal owns the slot.
  Future<bool> request(OverlayKind kind) {
    if (_disposed) {
      return Future<bool>.value(false);
    }
    final result = _queue.then((_) => _grant(kind));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> _grant(OverlayKind kind) async {
    if (_disposed) {
      return false;
    }
    if (kind == OverlayKind.tooltip) {
      if (_modal != null) {
        return false;
      }
      _tooltip = true;
      return true;
    }

    // A modal opens over no tooltip: close it before touching the modal slot.
    if (_tooltip) {
      await _dismiss(OverlayKind.tooltip);
      _tooltip = false;
    }
    final previous = _modal;
    if (previous != null && previous != kind) {
      await _dismiss(previous);
      if (_modal == previous) {
        _modal = null;
      }
    }
    _modal = kind;
    return true;
  }

  Future<void> _dismiss(OverlayKind kind) async {
    final dismiss = _dismissers[kind];
    if (dismiss == null) {
      return;
    }
    try {
      await dismiss().timeout(dismissTimeout);
    } on Object {
      // A dead or slow surface must not block the next open. The bloc's own
      // generation guard makes a late completion harmless.
    }
  }

  /// Drops this kind's claim. A newer modal's claim is never affected.
  void release(OverlayKind kind) {
    if (kind == OverlayKind.tooltip) {
      _tooltip = false;
      return;
    }
    if (_modal == kind) {
      _modal = null;
    }
  }

  /// Ends coordination at app teardown.
  void dispose() {
    _disposed = true;
    _dismissers.clear();
    _modal = null;
    _tooltip = false;
  }
}
