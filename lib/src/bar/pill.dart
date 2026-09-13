import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/accent.dart';
import '../theme/motion.dart';

class SystemBarCard extends StatelessWidget {
  const SystemBarCard({
    required this.accent,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    super.key,
  });

  final WallpaperAccent accent;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final topFill = accent.cardFillTop();
    final bottomFill = accent.cardFill();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            topFill.withValues(alpha: 0.92),
            bottomFill.withValues(alpha: 0.88),
          ],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Padding(
        padding: padding,
        child: Align(child: child),
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
