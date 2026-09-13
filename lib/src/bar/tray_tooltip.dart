import 'package:flutter/widgets.dart';

import '../layout/system_bar.dart';
import '../state/tray_tooltip.dart';
import '../theme/tokens.dart';
import 'pill.dart';

/// The contents of one tooltip surface: a transparent click-through overlay
/// with a small pill centered under the hovered item. Semantics stay on the
/// tray button, so the tooltip itself is excluded from the tree.
class TrayTooltipSurface extends StatelessWidget {
  const TrayTooltipSurface({required this.session, super.key});

  final TrayTooltipSession session;

  @override
  Widget build(BuildContext context) {
    final anchor = _anchor(MediaQuery.sizeOf(context));
    return ExcludeSemantics(
      child: CustomSingleChildLayout(
        delegate: _TooltipLayout(anchor: anchor),
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

  /// The strip's inner edge at the hovered item, in overlay coordinates.
  Offset _anchor(Size size) {
    return switch (session.side) {
      SystemBarSide.top => Offset(session.click.dx, session.thickness + 4),
      SystemBarSide.bottom => Offset(
        session.click.dx,
        size.height - session.thickness - 4,
      ),
      SystemBarSide.left => Offset(session.thickness + 4, session.click.dy),
      SystemBarSide.right => Offset(
        size.width - session.thickness - 4,
        session.click.dy,
      ),
      SystemBarSide.hidden => session.click,
    };
  }
}

/// Centers the pill on the anchor and clamps it inside the output.
class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout({required this.anchor});

  final Offset anchor;

  // Unbounded constraints: the pill sizes to its label, not to the output.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = (size.width - childSize.width).clamp(0.0, double.infinity);
    return Offset(
      (anchor.dx - childSize.width / 2).clamp(0.0, maxLeft),
      anchor.dy,
    );
  }

  @override
  bool shouldRelayout(_TooltipLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
