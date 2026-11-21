import 'package:flutter/services.dart' show LogicalKeyboardKey;
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

/// Whether the settings window paints its glass: the host must advertise the
/// effect and the document's `appearance.blur` must allow it, so one key
/// controls every glass surface.
bool settingsGlassEnabled({
  required bool hostBlur,
  required bool documentBlur,
}) => hostBlur && documentBlur;

/// Whether the settings window sits on a compositor-blurred backdrop. Absent
/// means false, so tests and hosts without the protocol keep opaque fills.
class SettingsGlass extends InheritedWidget {
  const SettingsGlass({required this.enabled, required super.child, super.key});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsGlass>()?.enabled ??
      false;

  /// A large panel fill: translucent over a blurred backdrop, opaque
  /// otherwise.
  static Color panel(BuildContext context, Color opaque) =>
      of(context) ? opaque.withValues(alpha: 0.72) : opaque;

  /// A control fill (chips, buttons, tracks): lighter than [panel] so the
  /// controls read as raised glass.
  static Color control(BuildContext context, Color opaque) =>
      of(context) ? opaque.withValues(alpha: 0.62) : opaque;

  @override
  bool updateShouldNotify(SettingsGlass oldWidget) =>
      oldWidget.enabled != enabled;
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
        color: SettingsGlass.panel(context, SettingsColors.surface),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: SettingsColors.outline),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The hover and keyboard-focus state a settings control paints.
@immutable
class SettingsControlFocus {
  const SettingsControlFocus({required this.hovered, required this.focused});

  final bool hovered;
  final bool focused;
}

/// Pointer and keyboard activation shared by the settings controls.
///
/// The child builder receives the interaction state so each control paints
/// its own focus ring. A tap, Enter, or Space fires [onPressed]; Tab reaches
/// the control through the inner [FocusableActionDetector].
class SettingsActivatable extends StatefulWidget {
  const SettingsActivatable({
    required this.onPressed,
    required this.builder,
    this.enabled = true,
    super.key,
  });

  final VoidCallback onPressed;
  final bool enabled;
  final Widget Function(BuildContext context, SettingsControlFocus focus)
  builder;

  @override
  State<SettingsActivatable> createState() => _SettingsActivatableState();
}

class _SettingsActivatableState extends State<SettingsActivatable> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'settings-control');
  var _hovered = false;
  var _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (value != _hovered) {
      setState(() => _hovered = value);
    }
  }

  void _setFocused(bool value) {
    if (value != _focused) {
      setState(() => _focused = value);
    }
  }

  void _activate() {
    if (widget.enabled) {
      widget.onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      enabled: widget.enabled,
      focusNode: _focusNode,
      onShowHoverHighlight: _setHovered,
      onShowFocusHighlight: _setFocused,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onPressed : null,
          child: widget.builder(
            context,
            SettingsControlFocus(hovered: _hovered, focused: _focused),
          ),
        ),
      ),
    );
  }
}

/// The window's close control. The compositor tiles this window, so it may
/// draw no decorations at all; the app carries its own.
class SettingsCloseButton extends StatelessWidget {
  const SettingsCloseButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.settingsClose,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SettingsActivatable(
          onPressed: onPressed,
          builder: (context, focus) => AnimatedContainer(
            duration: Motion.duration(context, Motion.pill),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SettingsGlass.control(
                context,
                focus.hovered
                    ? SettingsColors.surfaceHigh
                    : SettingsColors.surface,
              ),
              border: focus.focused
                  ? Border.all(
                      color: ShellBrandColors.defaultAccent,
                      width: 1.5,
                    )
                  : Border.all(color: SettingsColors.outline),
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
    );
  }
}

/// A small text button in the settings window.
class SettingsButton extends StatelessWidget {
  const SettingsButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SettingsActivatable(
          onPressed: onPressed,
          builder: (context, focus) => AnimatedContainer(
            duration: Motion.duration(context, Motion.pill),
            curve: Motion.standard,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: SettingsGlass.control(
                context,
                focus.hovered
                    ? SettingsColors.surfaceHigh
                    : SettingsColors.surface,
              ),
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              border: focus.focused
                  ? Border.all(
                      color: ShellBrandColors.defaultAccent,
                      width: 1.5,
                    )
                  : Border.all(color: SettingsColors.outline),
            ),
            child: Text(label, style: ShellText.systemBarCaption),
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
    this.semanticsValueBuilder,
    this.semanticsStep = 1,
    super.key,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Semantics label; the thickness slider keeps its own default.
  final String? label;

  /// Formats the announced value; null uses the rounded raw value.
  final String Function(double value)? semanticsValueBuilder;

  /// How far one assistive increase/decrease moves [value].
  final double semanticsStep;

  @override
  State<SettingsSlider> createState() => _SettingsSliderState();
}

class _SettingsSliderState extends State<SettingsSlider> {
  static const double _trackHeight = 6;
  static const double _height = 28;

  final FocusNode _focusNode = FocusNode(debugLabel: 'settings-slider');
  double? _dragValue;
  var _focused = false;

  bool get _enabled => widget.onChanged != null;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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

  /// Moves by one semantics step from the committed value; arrow keys and
  /// assistive technology share this path so both land on the same value.
  void _step(double delta) {
    if (!_enabled) {
      return;
    }
    final current = widget.value;
    final next = (current + delta).clamp(widget.min, widget.max);
    if (next == current) {
      return;
    }
    (widget.onChangeEnd ?? widget.onChanged)?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.value;
    final fraction = widget.max > widget.min
        ? ((value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0)
        : 0.0;
    final semanticsValue =
        widget.semanticsValueBuilder?.call(value) ?? '${value.round()}';
    final step = widget.semanticsStep;
    final increased = (value + step).clamp(widget.min, widget.max);
    final decreased = (value - step).clamp(widget.min, widget.max);
    return Semantics(
      slider: true,
      enabled: _enabled,
      label: widget.label ?? context.l10n.settingsThicknessLabel,
      value: semanticsValue,
      increasedValue:
          widget.semanticsValueBuilder?.call(increased) ??
          '${increased.round()}',
      decreasedValue:
          widget.semanticsValueBuilder?.call(decreased) ??
          '${decreased.round()}',
      onIncrease: _enabled ? () => _step(step) : null,
      onDecrease: _enabled ? () => _step(-step) : null,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return FocusableActionDetector(
              enabled: _enabled,
              focusNode: _focusNode,
              onShowFocusHighlight: (value) => setState(() => _focused = value),
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(LogicalKeyboardKey.arrowLeft):
                    _SliderStepIntent(-step),
                const SingleActivator(LogicalKeyboardKey.arrowDown):
                    _SliderStepIntent(-step),
                const SingleActivator(LogicalKeyboardKey.arrowRight):
                    _SliderStepIntent(step),
                const SingleActivator(LogicalKeyboardKey.arrowUp):
                    _SliderStepIntent(step),
              },
              actions: <Type, Action<Intent>>{
                _SliderStepIntent: CallbackAction<_SliderStepIntent>(
                  onInvoke: (intent) {
                    _step(intent.delta);
                    return null;
                  },
                ),
              },
              child: MouseRegion(
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
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(
                        Radius.circular(999),
                      ),
                      border: _focused
                          ? Border.all(
                              color: ShellBrandColors.defaultAccent,
                              width: 1.5,
                            )
                          : null,
                    ),
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
                              color: SettingsGlass.control(
                                context,
                                SettingsColors.surfaceHigh,
                              ),
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
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SliderStepIntent extends Intent {
  const _SliderStepIntent(this.delta);

  final double delta;
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
        child: SettingsActivatable(
          onPressed: onPressed,
          builder: (context, focus) => AnimatedContainer(
            duration: Motion.duration(context, Motion.pill),
            curve: Motion.standard,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              color: selected
                  ? ShellBrandColors.defaultAccent
                  : SettingsGlass.control(context, SettingsColors.surfaceHigh),
              border: focus.focused
                  ? Border.all(
                      // The selected fill is the accent too; a light ring
                      // keeps the focused state visible on it.
                      color: selected
                          ? ShellMediaColors.lightForeground
                          : ShellBrandColors.defaultAccent,
                      width: 1.5,
                    )
                  : Border.all(color: SettingsColors.outline),
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
    );
  }
}

/// A pill switch with a label, used by option panels for boolean keys.
class SettingsToggle extends StatefulWidget {
  const SettingsToggle({
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.hint,
    super.key,
  });

  final String label;
  final bool enabled;

  /// Null disables the control.
  final ValueChanged<bool>? onChanged;

  /// Accessible hint; null uses the generic setting-toggle hint.
  final String? hint;

  @override
  State<SettingsToggle> createState() => _SettingsToggleState();
}

class _SettingsToggleState extends State<SettingsToggle> {
  final FocusNode _focusNode = FocusNode();
  var _focused = false;

  bool get _interactive => widget.onChanged != null;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    final onChanged = widget.onChanged;
    if (onChanged != null) {
      onChanged(!widget.enabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: widget.enabled,
      enabled: _interactive,
      label: widget.label,
      hint: widget.hint ?? context.l10n.settingsToggleHint,
      onTap: _interactive ? _toggle : null,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          enabled: _interactive,
          focusNode: _focusNode,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _toggle();
                return null;
              },
            ),
          },
          child: MouseRegion(
            cursor: _interactive
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _interactive ? _toggle : null,
              child: AnimatedContainer(
                duration: Motion.duration(context, Motion.pill),
                curve: Motion.standard,
                width: 44,
                height: 24,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(999)),
                  color: !_interactive
                      ? SettingsGlass.control(
                          context,
                          SettingsColors.surfaceHigh,
                        )
                      : widget.enabled
                      ? ShellBrandColors.defaultAccent
                      : SettingsGlass.control(
                          context,
                          SettingsColors.surfaceHigh,
                        ),
                  border: _focused
                      ? Border.all(
                          // An enabled toggle fills with the accent; the
                          // light ring keeps focus visible on that fill.
                          color: widget.enabled
                              ? ShellMediaColors.lightForeground
                              : ShellBrandColors.defaultAccent,
                          width: 1.5,
                        )
                      : Border.all(color: SettingsColors.outline),
                ),
                child: AnimatedAlign(
                  duration: Motion.duration(context, Motion.pill),
                  curve: Motion.standard,
                  alignment: widget.enabled
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.enabled
                          ? SettingsColors.background
                          : ShellMediaColors.lightForegroundSecondary,
                    ),
                    child: const SizedBox.square(dimension: 16),
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

/// A labeled [SettingsToggle] with its reset control, used by option panels.
class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    required this.toggleKey,
    required this.label,
    required this.value,
    required this.resetKey,
    required this.resetLabel,
    required this.resetEnabled,
    required this.onChanged,
    required this.onReset,
    this.enabled = true,
    this.hint,
    this.note,
    super.key,
  });

  final Key toggleKey;
  final String label;
  final bool value;
  final Key resetKey;
  final String resetLabel;
  final bool resetEnabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onReset;

  /// False disables the switch and its reset.
  final bool enabled;

  /// Accessible hint; null uses the generic setting-toggle hint.
  final String? hint;

  /// An optional line below the row explaining why it is unavailable.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Expanded(
          // The switch already carries [label]; excluding this copy stops a
          // screen reader from announcing the setting twice.
          child: ExcludeSemantics(
            child: Text(
              label,
              style: ShellText.systemBarCaption.copyWith(
                color: ShellMediaColors.lightForegroundSecondary,
              ),
            ),
          ),
        ),
        SettingsToggle(
          key: toggleKey,
          label: label,
          enabled: value,
          onChanged: enabled ? onChanged : null,
          hint: hint,
        ),
        const SizedBox(width: 12),
        SettingsResetButton(
          key: resetKey,
          label: resetLabel,
          enabled: enabled && resetEnabled,
          onPressed: onReset,
        ),
      ],
    );
    final note = this.note;
    if (note == null) {
      return row;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: 4),
        Text(
          note,
          style: ShellText.systemBarCaption.copyWith(
            color: ShellMediaColors.lightForegroundSecondary.withValues(
              alpha: 0.7,
            ),
          ),
        ),
      ],
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
class SettingsResetButton extends StatelessWidget {
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

  Color _glyphColor(SettingsControlFocus focus) {
    if (!enabled) {
      return ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.3);
    }
    return focus.hovered || focus.focused
        ? ShellMediaColors.lightForeground
        : ShellMediaColors.lightForegroundSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: context.l10n.settingsResetHint,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: SettingsActivatable(
          enabled: enabled,
          onPressed: onPressed,
          builder: (context, focus) => SizedBox.square(
            dimension: SettingsResetButton.extent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: focus.hovered || focus.focused
                    ? SettingsGlass.control(context, SettingsColors.surfaceHigh)
                    : ShellMediaColors.transparentDark,
                border: focus.focused
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
                  color: _glyphColor(focus),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
