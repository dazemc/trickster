import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

typedef BlurBoundsProvider = Rect? Function();

class _CachedBlurRegion {
  const _CachedBlurRegion({
    required this.bounds,
    required this.radius,
    required this.regions,
  });

  final Rect bounds;
  final double radius;
  final List<Rect> regions;
}

/// Collects the pill rectangles one strip surface should blur.
///
/// The compositor's background effect is surface-wide unless a region is
/// given, so each card registers a live bounds provider here and the native
/// side turns the flush into the blur region. Scanline rows are cached by
/// `(bounds, radius)`: a repaint with unchanged geometry costs one bounds
/// read, not a row rebuild. Flushes run after the frame that moved a card,
/// and [resend] re-queries all bounds for scrolls that only translate a cached
/// layer, reusing every unchanged row set.
class BlurRegionController {
  BlurRegionController({required this.onRegions});

  final ValueChanged<List<Rect>> onRegions;

  final Map<Object, BlurBoundsProvider> _providers =
      <Object, BlurBoundsProvider>{};
  final Map<Object, _CachedBlurRegion> _cache = <Object, _CachedBlurRegion>{};
  final Set<Object> _dirty = <Object>{};
  List<Rect>? _sent;
  var _structural = false;
  var _scheduled = false;
  var _disposed = false;
  var _debugRegionBuilds = 0;

  @visibleForTesting
  int get debugRegionBuilds => _debugRegionBuilds;

  void register(Object id, BlurBoundsProvider bounds) {
    if (_disposed) {
      return;
    }
    _providers[id] = bounds;
    _dirty.add(id);
    _structural = true;
    _schedule();
  }

  void unregister(Object id) {
    if (_disposed || _providers.remove(id) == null) {
      return;
    }
    _cache.remove(id);
    _dirty.remove(id);
    _structural = true;
    _schedule();
  }

  /// Schedules a flush; pill paint calls this when its position may have
  /// changed. With an [id], only that provider is re-read; no argument marks
  /// every provider.
  void refresh([Object? id]) {
    if (_disposed) {
      return;
    }
    if (id == null) {
      _dirty.addAll(_providers.keys);
    } else if (_providers.containsKey(id)) {
      _dirty.add(id);
    } else {
      return;
    }
    _schedule();
  }

  /// Re-queries every provider; used when the surface was remapped, scrolled,
  /// or the blur capability flipped on. Unchanged bounds reuse their cached
  /// rows.
  void resend() {
    if (_disposed) {
      return;
    }
    _dirty.addAll(_providers.keys);
    _schedule();
  }

  void dispose() {
    _disposed = true;
    _providers.clear();
    _cache.clear();
    _dirty.clear();
    _sent = null;
  }

  void _schedule() {
    if (_disposed || _scheduled) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) {
        return;
      }
      _flush();
    });
  }

  void _flush() {
    var changed = _structural;
    for (final id in _dirty.toList()) {
      final provider = _providers[id];
      if (provider == null) {
        continue;
      }
      final bounds = provider();
      final cached = _cache[id];
      if (bounds == null) {
        if (cached != null) {
          _cache.remove(id);
          changed = true;
        }
        continue;
      }
      final radius = bounds.shortestSide / 2;
      if (cached != null &&
          cached.bounds == bounds &&
          cached.radius == radius) {
        continue;
      }
      _cache[id] = _CachedBlurRegion(
        bounds: bounds,
        radius: radius,
        regions: _roundedRegion(bounds),
      );
      assert(() {
        _debugRegionBuilds += 1;
        return true;
      }());
      changed = true;
    }
    _dirty.clear();
    _structural = false;
    if (!changed) {
      return;
    }
    final regions = <Rect>[
      for (final id in _providers.keys) ...?_cache[id]?.regions,
    ];
    if (_sent != null && listEquals(regions, _sent)) {
      return;
    }
    _sent = regions;
    onRegions(regions);
  }
}

/// Provides the strip's [BlurRegionController] to the pills inside it.
class BlurRegionScope extends InheritedWidget {
  const BlurRegionScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final BlurRegionController? controller;

  static BlurRegionController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BlurRegionScope>()?.controller;

  @override
  bool updateShouldNotify(BlurRegionScope oldWidget) =>
      oldWidget.controller != controller;
}

/// Registers its child's live bounds with the enclosing [BlurRegionScope].
/// A no-op without a scope, so tests and hosts without the protocol pay
/// nothing.
class BlurRegion extends StatefulWidget {
  const BlurRegion({required this.child, super.key});

  final Widget child;

  @override
  State<BlurRegion> createState() => _BlurRegionState();
}

class _BlurRegionState extends State<BlurRegion> {
  final Object _id = Object();
  BlurRegionController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = BlurRegionScope.maybeOf(context);
    if (next != _controller) {
      _controller?.unregister(_id);
      _controller = next;
      _controller?.register(_id, _currentBounds);
    }
  }

  @override
  void dispose() {
    _controller?.unregister(_id);
    super.dispose();
  }

  Rect? _currentBounds() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return widget.child;
    }
    final controller = _controller!;
    return _BlurRegionReporter(
      onPaint: () => controller.refresh(_id),
      child: widget.child,
    );
  }
}

class _BlurRegionReporter extends SingleChildRenderObjectWidget {
  const _BlurRegionReporter({required this.onPaint, required super.child});

  final VoidCallback onPaint;

  @override
  _RenderBlurRegionReporter createRenderObject(BuildContext context) =>
      _RenderBlurRegionReporter(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderBlurRegionReporter renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderBlurRegionReporter extends RenderProxyBox {
  _RenderBlurRegionReporter(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    onPaint();
  }
}

/// Approximates a stadium card as one-pixel horizontal strips so the blur
/// follows the rounded ends; `wl_region` takes only axis-aligned rects, so
/// a single rectangle would show squared corners.
List<Rect> _roundedRegion(Rect bounds) {
  final radius = bounds.shortestSide / 2;
  if (radius <= 0.5 || bounds.width <= 1 || bounds.height <= 1) {
    return <Rect>[bounds];
  }
  final rows = bounds.height.round();
  return <Rect>[
    for (var row = 0; row < rows; row++)
      Rect.fromLTWH(
        bounds.left + _cornerInset(row + 0.5, bounds.height, radius),
        bounds.top + row,
        bounds.width - 2 * _cornerInset(row + 0.5, bounds.height, radius),
        1,
      ),
  ];
}

double _cornerInset(double y, double height, double radius) {
  final center = y < radius
      ? y
      : y > height - radius
      ? height - y
      : radius;
  final fromCap = radius - center;
  return radius - math.sqrt(math.max(0, radius * radius - fromCap * fromCap));
}
