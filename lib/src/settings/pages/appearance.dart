import 'package:flutter/widgets.dart';

import '../../locale.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import '../color_format.dart';
import '../color_wheel.dart';
import '../controller.dart';
import '../scope.dart';
import '../saver.dart';
import '../settings_theme.dart';

/// Denial's accent presets, starting from the shell's default.
const List<Color> accentPresets = <Color>[
  ShellBrandColors.defaultAccent,
  Color(0xff8ab4ff),
  Color(0xff78dce8),
  Color(0xff8ee6c1),
  Color(0xffffd166),
  Color(0xffff9f6b),
  Color(0xffff6b6b),
  Color(0xffff8ad8),
];

/// Appearance page: preset swatches plus the HSV wheel, writing `accent`.
/// Saves are debounced so dragging the wheel writes once per gesture.
class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  DebouncedSaver? _saver;

  @override
  void dispose() {
    _saver?.dispose();
    super.dispose();
  }

  void _apply(SettingsAppController controller, Color? accent) {
    _saver ??= DebouncedSaver(controller);
    _saver!.apply((settings) => settings.withAccent(accent));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final accent = controller.settings.accent ?? ShellBrandColors.defaultAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(
          title: l10n.settingsAppearanceTitle,
          caption: l10n.settingsAppearanceCaption,
        ),
        const SizedBox(height: 20),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsAccentPresets,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellMediaColors.lightForegroundSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final preset in accentPresets)
                    _SwatchButton(
                      key: ValueKey<String>(
                        'accent-preset-${formatOpaqueColorHex(preset)}',
                      ),
                      color: preset,
                      selected: preset.toARGB32() == accent.toARGB32(),
                      onPressed: () => _apply(controller, preset),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 176,
                    child: HsvColorWheel(
                      color: accent,
                      onChanged: (color) => _apply(controller, color),
                    ),
                  ),
                  const SizedBox(width: 28),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formatOpaqueColorHex(accent),
                        style: ShellText.systemBarValue.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 14),
                      SettingsButton(
                        label: l10n.settingsAccentReset,
                        onPressed: () => _apply(controller, null),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwatchButton extends StatefulWidget {
  const _SwatchButton({
    required this.color,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SwatchButton> createState() => _SwatchButtonState();
}

class _SwatchButtonState extends State<_SwatchButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scale = _hovered ? 1.12 : 1.0;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: formatOpaqueColorHex(widget.color),
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedScale(
              duration: Motion.pill,
              curve: Motion.standard,
              scale: scale,
              child: AnimatedContainer(
                duration: Motion.pill,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  border: Border.all(
                    color: widget.selected
                        ? ShellMediaColors.lightForeground
                        : SettingsColors.outline,
                    width: widget.selected ? 2.0 : 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
