import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/keyboard_layout.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

/// Keyboard caption plus the active short layout. The full layout set lives
/// in the hover tooltip. No click target and no icon.
class KeyboardLayoutPill extends StatelessWidget {
  const KeyboardLayoutPill({
    required this.accent,
    required this.state,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final KeyboardLayoutState state;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    if (!state.hasLayout) {
      return const SizedBox.shrink();
    }
    final caption = context.l10n.metricKeyboardLayout;
    final active = state.active!;
    final layouts = state.names.isEmpty
        ? active
        : state.names.map((name) => name.toUpperCase()).join(' / ');
    final captionStyle = ShellText.systemBarCaption.copyWith(
      color: accent.captionColor(),
    );
    final valueStyle = ShellText.systemBarValue;
    final labels = Semantics(
      label: caption,
      value: active,
      child: ExcludeSemantics(
        child: vertical
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(caption, style: captionStyle),
                  Text(active, style: valueStyle),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(caption, style: captionStyle),
                  const SizedBox(width: 5),
                  Text(active, style: valueStyle),
                ],
              ),
      ),
    );
    return PillTooltip(
      accent: accent,
      label: '$caption $active · ${context.l10n.keyboardLayoutNames(layouts)}',
      child: SystemBarCard(
        accent: accent,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 6 : 12),
        child: labels,
      ),
    );
  }
}
