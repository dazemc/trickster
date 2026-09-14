import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Collects the pill rectangles one strip surface should blur.
///
/// The compositor's background effect is surface-wide unless a region is
/// given, so each card registers a live rect provider here and the native
/// side turns the flush into the blur region. Flushes run after the frame
/// that moved a card, and [resend] re-queries them for scrolls that only
/// translate a cached layer.
class BlurRegionController {
  BlurRegionController({required this.onRegions});

  final ValueChanged<List<Rect>> onRegions;

  final Map<Object, List<Rect> Function()> _providers =
      <Object, List<Rect> Function()>{};
  List<Rect>? _sent;
  var _scheduled = false;

  void register(Object id, List<Rect> Function() regions) {
    _providers[id] = regions;
    _schedule();
  }

  void unregister(Object id) {
    if (_providers.remove(id) != null) {
      _schedule();
    }
  }

  /// Schedules a flush; pill paint calls this when its position may have
  /// changed.
  void refresh() {
    _schedule();
  }

  /// Re-queries every provider; used when the surface was remapped, scrolled,
  /// or the blur capability flipped on.
  void resend() {
    _schedule();
  }

  void dispose() {
    _providers.clear();
  }

  void _schedule() {
    if (_scheduled) {
      return;
    }
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final regions = <Rect>[
        for (final provider in _providers.values) ...provider(),
      ];
      if (_sent != null && listEquals(regions, _sent)) {
        return;
      }
      _sent = regions;
      onRegions(regions);
    });
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
      _controller?.register(_id, _currentRegions);
    }
  }

  @override
  void dispose() {
    _controller?.unregister(_id);
    super.dispose();
  }

  List<Rect> _currentRegions() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const <Rect>[];
    }
    return _roundedRegion(box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return widget.child;
    }
    return _BlurRegionReporter(
      onPaint: _controller!.refresh,
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
