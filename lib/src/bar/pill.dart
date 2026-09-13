import 'dart:async';

import 'package:flutter/material.dart'
    show InkWell, Material, MaterialType, NoSplash, SystemMouseCursors;
import 'package:flutter/widgets.dart';

import '../theme/accent.dart';
import '../theme/backdrop_blur.dart';
import '../theme/motion.dart';

class SystemBarCard extends StatelessWidget {
  const SystemBarCard({
    required this.accent,
    required this.child,
    this.highlighted = false,
    this.focused = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    super.key,
  });

  final WallpaperAccent accent;
  final Widget child;
  final bool highlighted;
  final bool focused;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final topFill = highlighted
        ? Color.lerp(accent.cardFillTop(), accent.color, 0.12)!
        : accent.cardFillTop();
    final bottomFill = highlighted
        ? Color.lerp(accent.cardFill(), accent.color, 0.08)!
        : accent.cardFill();
    final blurred = BackdropBlur.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            topFill.withValues(alpha: blurred ? 0.74 : 0.92),
            bottomFill.withValues(alpha: blurred ? 0.66 : 0.88),
          ],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: focused ? Border.all(color: accent.color, width: 1.5) : null,
      ),
      child: Padding(
        padding: padding,
        child: Align(child: child),
      ),
    );
  }
}

/// Interactive pill: Semantics button plus tap, hover, and keyboard focus,
/// mirroring Denial's `_BatteryActionCard`. Highlight tints toward the
/// accent; focus adds the accent ring.
class TricksterActionCard extends StatefulWidget {
  const TricksterActionCard({
    required this.accent,
    required this.label,
    required this.onPressed,
    required this.child,
    this.hint,
    this.focusNode,
    super.key,
  });

  final WallpaperAccent accent;
  final String label;
  final String? hint;
  final VoidCallback onPressed;
  final Widget child;
  final FocusNode? focusNode;

  @override
  State<TricksterActionCard> createState() => _TricksterActionCardState();
}

class _TricksterActionCardState extends State<TricksterActionCard> {
  var _hovered = false;
  var _focused = false;
  FocusNode? _internalNode;

  FocusNode get _node => widget.focusNode ?? (_internalNode ??= FocusNode());

  @override
  void dispose() {
    _internalNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      hint: widget.hint,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            mouseCursor: SystemMouseCursors.click,
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Color(0x00000000)),
            focusNode: _node,
            onTap: widget.onPressed,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            child: SystemBarCard(
              accent: widget.accent,
              highlighted: _hovered || _focused,
              focused: _focused,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class SystemBarEntrance extends StatefulWidget {
  const SystemBarEntrance({
    required this.index,
    required this.horizontal,
    required this.child,
    super.key,
  });

  final int index;
  final bool horizontal;
  final Widget child;

  @override
  State<SystemBarEntrance> createState() => _SystemBarEntranceState();
}

class _SystemBarEntranceState extends State<SystemBarEntrance>
    with SingleTickerProviderStateMixin {
  static const double _slideDistance = 12.0;
  static const Duration _stagger = Duration(milliseconds: 60);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.cardSettle,
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(_stagger * widget.index, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Motion.standard,
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        final travel = (1.0 - t) * _slideDistance;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: widget.horizontal ? Offset(travel, 0) : Offset(0, travel),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
