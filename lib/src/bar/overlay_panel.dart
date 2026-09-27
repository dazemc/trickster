import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/state/capabilities_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

/// Positions a measured overlay panel against the strip's inner edge,
/// centered on the click and clamped inside the output so a pill near a
/// corner never pushes it off screen.
class OverlayPanelLayoutDelegate extends SingleChildLayoutDelegate {
  const OverlayPanelLayoutDelegate({required this.anchor, required this.side});

  final Offset anchor;
  final SystemBarSide side;
  static const double margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(margin, size.width - childSize.width - margin);
    final maxY = math.max(margin, size.height - childSize.height - margin);
    return switch (side) {
      SystemBarSide.top || SystemBarSide.hidden => Offset(
        (anchor.dx - childSize.width / 2).clamp(margin, maxX),
        (anchor.dy + margin).clamp(margin, maxY),
      ),
      SystemBarSide.bottom => Offset(
        (anchor.dx - childSize.width / 2).clamp(margin, maxX),
        (anchor.dy - childSize.height - margin).clamp(margin, maxY),
      ),
      SystemBarSide.left => Offset(
        (anchor.dx + margin).clamp(margin, maxX),
        (anchor.dy - childSize.height / 2).clamp(margin, maxY),
      ),
      SystemBarSide.right => Offset(
        (anchor.dx - childSize.width - margin).clamp(margin, maxX),
        (anchor.dy - childSize.height / 2).clamp(margin, maxY),
      ),
    };
  }

  @override
  bool shouldRelayout(OverlayPanelLayoutDelegate oldDelegate) {
    return oldDelegate.anchor != anchor || oldDelegate.side != side;
  }
}

/// The panel fill every overlay shares: the pills' hosted-blur glass when
/// the host advertises it, the opaque accent fill otherwise.
BoxDecoration overlayPanelDecoration(
  BuildContext context,
  WallpaperAccent accent,
) {
  final glass =
      context.select((CapabilitiesBloc bloc) => bloc.state.blur) &&
      context.select((SettingsBloc bloc) => bloc.state.appearance.blur);
  return BoxDecoration(
    color: glass ? null : accent.cardFill(),
    gradient: glass
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ShellMediaColors.darkness.withValues(alpha: 0.30),
              ShellMediaColors.darkness.withValues(alpha: 0.26),
            ],
          )
        : null,
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    border: Border.all(color: ShellMediaColors.glassSurface),
    boxShadow: const [
      BoxShadow(color: Color(0x88000000), blurRadius: 18, spreadRadius: 1),
    ],
  );
}
