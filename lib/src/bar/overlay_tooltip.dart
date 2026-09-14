import 'package:flutter/widgets.dart';

import '../layout/system_bar.dart';
import '../state/overlay_tooltip.dart';
import '../theme/tokens.dart';
import 'pill.dart';

/// The contents of one tooltip surface: a transparent click-through overlay
/// with a small pill centered under the hovered item. Semantics stay on the
/// tray button, so the tooltip itself is excluded from the tree.
class OverlayTooltipSurface extends StatelessWidget {
  const OverlayTooltipSurface({required this.session, super.key});

  final OverlayTooltipSession session;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomSingleChildLayout(
        delegate: _TooltipLayout(
          side: session.side,
          thickness: session.thickness,
          click: session.click,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SystemBarCard(
            accent: session.accent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              session.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: ShellText.systemBarCaption,
            ),
          ),
        ),
      ),
    );
  }
}

/// Places the pill beside or below the hovered item, centered on it along
/// the bar's main axis and clamped inside the output.
class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout({
    required this.side,
    required this.thickness,
    required this.click,
  });

  final SystemBarSide side;
  final double thickness;
  final Offset click;

  static const double _gap = 4;

  // Unbounded constraints: the pill sizes to its label, not to the output.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  double _clamp(double value, double max) =>
      value.clamp(0.0, max < 0 ? 0.0 : max);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return switch (side) {
      SystemBarSide.top => Offset(
        _clamp(click.dx - childSize.width / 2, size.width - childSize.width),
        thickness + _gap,
      ),
      SystemBarSide.bottom => Offset(
        _clamp(click.dx - childSize.width / 2, size.width - childSize.width),
        _clamp(
          size.height - thickness - _gap - childSize.height,
          size.height - childSize.height,
        ),
      ),
      SystemBarSide.left => Offset(
        thickness + _gap,
        _clamp(click.dy - childSize.height / 2, size.height - childSize.height),
      ),
      SystemBarSide.right => Offset(
        _clamp(
          size.width - thickness - _gap - childSize.width,
          size.width - childSize.width,
        ),
        _clamp(click.dy - childSize.height / 2, size.height - childSize.height),
      ),
      SystemBarSide.hidden => click,
    };
  }

  @override
  bool shouldRelayout(_TooltipLayout oldDelegate) =>
      oldDelegate.side != side ||
      oldDelegate.thickness != thickness ||
      oldDelegate.click != click;
}
