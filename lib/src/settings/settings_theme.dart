import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:trickster/src/locale.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';

/// The settings window's surface palette: the strip's glass language at
/// window scale, without Material scaffolding.
abstract final class SettingsColors {
  static const Color background = Color(0xff0b0b12);
  static const Color backgroundTop = Color(0xff14141f);
  static const Color surface = Color(0xff171722);
  static const Color surfaceHigh = Color(0xff1f1f2c);
  static const Color outline = Color(0x22ffffff);
}

/// One panel in the settings window, mirroring the strip's pill fills.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SettingsColors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: SettingsColors.outline),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The window's close control. The compositor tiles this window, so it may
/// draw no decorations at all; the app carries its own.
class SettingsCloseButton extends StatefulWidget {
  const SettingsCloseButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  State<SettingsCloseButton> createState() => _SettingsCloseButtonState();
}

class _SettingsCloseButtonState extends State<SettingsCloseButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.settingsClose,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hovered
                    ? SettingsColors.surfaceHigh
                    : SettingsColors.surface,
                border: Border.all(color: SettingsColors.outline),
              ),
              child: const Center(
                child: Icon(
                  LucideIcons.x,
                  size: 14,
                  color: ShellMediaColors.lightForegroundSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small text button in the settings window.
class SettingsButton extends StatefulWidget {
  const SettingsButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  State<SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<SettingsButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Motion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _hovered
                    ? SettingsColors.surfaceHigh
                    : SettingsColors.surface,
                borderRadius: const BorderRadius.all(Radius.circular(999)),
                border: Border.all(color: SettingsColors.outline),
              ),
              child: Text(widget.label, style: ShellText.systemBarCaption),
            ),
          ),
        ),
      ),
    );
  }
}

/// A track-and-knob slider in the settings window.
class SettingsSlider extends StatefulWidget {
  const SettingsSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
    this.label,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Semantics label; the thickness slider keeps its own default.
  final String? label;

  @override
  State<SettingsSlider> createState() => _SettingsSliderState();
}

class _SettingsSliderState extends State<SettingsSlider> {
  static const double _trackHeight = 6;
  static const double _height = 28;

  double? _dragValue;

  bool get _enabled => widget.onChanged != null;

  double _valueAt(Offset position, double width) {
    final fraction = (position.dx / width).clamp(0.0, 1.0);
    return widget.min + fraction * (widget.max - widget.min);
  }

  void _update(Offset position, double width, {required bool ended}) {
    final value = _valueAt(position, width);
    setState(() => _dragValue = ended ? null : value);
    if (ended) {
      widget.onChangeEnd?.call(value);
    } else {
      widget.onChanged?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.value;
    final fraction = widget.max > widget.min
        ? ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0)
        : 0.0;
    return Semantics(
      slider: true,
      enabled: _enabled,
      label: widget.label ?? context.l10n.settingsThicknessLabel,
      value: '${value.round()}',
      increasedValue: '${(value + 1).clamp(widget.min, widget.max).round()}',
      decreasedValue: '${(value - 1).clamp(widget.min, widget.max).round()}',
      onIncrease: _enabled
          ? () => widget.onChangeEnd?.call(
              (value + 1).clamp(widget.min, widget.max),
            )
          : null,
      onDecrease: _enabled
          ? () => widget.onChangeEnd?.call(
              (value - 1).clamp(widget.min, widget.max),
            )
          : null,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return MouseRegion(
              cursor: _enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _enabled
                    ? (details) =>
                          _update(details.localPosition, width, ended: true)
                    : null,
                onHorizontalDragUpdate: _enabled
                    ? (details) =>
                          _update(details.localPosition, width, ended: false)
                    : null,
                onHorizontalDragEnd: _enabled
                    ? (_) => _update(
                        Offset(fraction * width, 0),
                        width,
                        ended: true,
                      )
                    : null,
                child: SizedBox(
                  height: _height,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(999),
                          ),
                          color: SettingsColors.surfaceHigh,
                        ),
                        child: const SizedBox(
                          width: double.infinity,
                          height: _trackHeight,
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: fraction,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(999),
                            ),
                            color: _enabled
                                ? ShellBrandColors.defaultAccent
                                : SettingsColors.outline,
                          ),
                          child: const SizedBox(height: _trackHeight),
                        ),
                      ),
                      Align(
                        alignment: Alignment(fraction * 2 - 1, 0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _enabled
                                ? ShellMediaColors.lightForeground
                                : ShellMediaColors.lightForegroundSecondary,
                            border: Border.all(
                              color: SettingsColors.background,
                              width: 2,
                            ),
                          ),
                          child: const SizedBox.square(dimension: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A pill-shaped choice in the settings window.
class SettingsChoiceChip extends StatelessWidget {
  const SettingsChoiceChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Motion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(999)),
                color: selected
                    ? ShellBrandColors.defaultAccent
                    : SettingsColors.surfaceHigh,
                border: Border.all(color: SettingsColors.outline),
              ),
              child: Text(
                label,
                style: ShellText.systemBarCaption.copyWith(
                  color: selected
                      ? SettingsColors.background
                      : ShellMediaColors.lightForeground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section heading inside the settings window.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading({required this.title, this.caption, super.key});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ShellText.systemBarValue.copyWith(fontSize: 15)),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// A circular-arrow button that reverts one option to its shipped default.
///
/// [label] names the option for assistive tech; callers disable it while the
/// value already equals the default so the affordance reads as inert.
class SettingsResetButton extends StatefulWidget {
  const SettingsResetButton({
    required this.label,
    required this.onPressed,
    this.enabled = true,
    super.key,
  });

  static const double extent = 24;

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<SettingsResetButton> createState() => _SettingsResetButtonState();
}

class _SettingsResetButtonState extends State<SettingsResetButton> {
  var _hovered = false;
  var _focused = false;

  Color get _glyphColor {
    if (!widget.enabled) {
      return ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.3);
    }
    return _hovered || _focused
        ? ShellMediaColors.lightForeground
        : ShellMediaColors.lightForegroundSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      hint: context.l10n.settingsResetHint,
      onTap: widget.enabled ? widget.onPressed : null,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: FocusableActionDetector(
            enabled: widget.enabled,
            onShowHoverHighlight: (value) => setState(() => _hovered = value),
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled ? widget.onPressed : null,
              child: SizedBox.square(
                dimension: SettingsResetButton.extent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hovered || _focused
                        ? SettingsColors.surfaceHigh
                        : ShellMediaColors.transparentDark,
                    border: _focused
                        ? Border.all(
                            color: ShellBrandColors.defaultAccent,
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: Center(
                    child: Icon(
                      LucideIcons.rotateCcw,
                      size: 13,
                      color: _glyphColor,
                    ),
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
