import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../layout/system_bar.dart';
import '../state/overlay_tooltip.dart';
import '../theme/accent.dart';

/// The strip's edge and band size, so pills can place their tooltips without
/// threading the geometry through every module.
class StripGeometry extends InheritedWidget {
  const StripGeometry({
    required this.side,
    required this.thickness,
    required super.child,
    super.key,
  });

  final SystemBarSide side;
  final double thickness;

  static StripGeometry? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<StripGeometry>();
  }

  @override
  bool updateShouldNotify(StripGeometry oldWidget) {
    return oldWidget.side != side || oldWidget.thickness != thickness;
  }
}

/// Hover tooltip for one pill, rendered on the transient overlay surface the
/// tray tooltips use. Semantics remain the accessible path; this adds the
/// visual detail on hover.
class PillTooltip extends StatefulWidget {
  const PillTooltip({
    required this.accent,
    required this.label,
    required this.child,
    this.delay = const Duration(milliseconds: 450),
    super.key,
  });

  final WallpaperAccent accent;
  final String label;
  final Widget child;
  final Duration delay;

  @override
  State<PillTooltip> createState() => _PillTooltipState();
}

class _PillTooltipState extends State<PillTooltip> {
  Timer? _timer;
  OverlayTooltipController? _controller;
  late final String _id = 'pill-${identityHashCode(this)}';
  var _hovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = OverlayTooltipScope.maybeOf(context);
  }

  @override
  void didUpdateWidget(covariant PillTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Live data (percent, track) keeps the open tooltip current; deferred
    // because notifying during this build would mark ancestors dirty.
    if (_hovered && oldWidget.label != widget.label) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hovered) {
          _show();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_controller?.close(itemId: _id));
    super.dispose();
  }

  void _show() {
    final controller = _controller;
    final geometry = StripGeometry.maybeOf(context);
    if (controller == null || geometry == null || !mounted) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    final center = box.localToGlobal(box.size.center(Offset.zero));
    unawaited(
      controller.show(
        barViewId: View.of(context).viewId,
        itemId: _id,
        label: widget.label,
        accent: widget.accent,
        click: center,
        side: geometry.side,
        thickness: geometry.thickness,
      ),
    );
  }

  void _handleEnter(PointerEnterEvent event) {
    _hovered = true;
    _timer?.cancel();
    _timer = Timer(widget.delay, _show);
  }

  void _handleExit(PointerExitEvent event) {
    _hovered = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_controller?.close(itemId: _id));
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: widget.child,
    );
  }
}
