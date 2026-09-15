import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show InkWell, Material, MaterialType, NoSplash, SystemMouseCursors;
import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart' show PipStyle;
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';

class WorkspacesPill extends StatelessWidget {
  const WorkspacesPill({
    required this.accent,
    required this.workspaces,
    required this.horizontal,
    this.style = PipStyle.number,
    this.onPressed,
    super.key,
  });

  static const Key lensKey = ValueKey<String>('workspaces-lens');

  static const double _itemExtent = 20;
  static const double _crossExtent = 18;
  static const double _lensSize = 17;
  static const double _dotExtent = 7;

  final WallpaperAccent accent;
  final List<Workspace> workspaces;
  final bool horizontal;

  /// How each pip paints: its name, a dot, or a Roman numeral.
  final PipStyle style;
  final ValueChanged<Workspace>? onPressed;

  @override
  Widget build(BuildContext context) {
    final count = workspaces.length;
    final active = workspaces.indexWhere((workspace) => workspace.focused);
    final mainExtent = _itemExtent * count;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // One scale for the whole rail: every numeral paints at the same size,
    // sized so the widest one fits the pip cell.
    final textScale = style == PipStyle.roman
        ? romanPipScale([
            for (final workspace in workspaces)
              pipLabel(workspace.name, PipStyle.roman),
          ])
        : 1.0;
    return SystemBarCard(
      accent: accent,
      padding: horizontal
          ? const EdgeInsets.symmetric(horizontal: 4)
          : const EdgeInsets.all(4),
      child: SizedBox(
        width: horizontal ? mainExtent : _crossExtent,
        height: horizontal ? _crossExtent : mainExtent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: AnimatedAlign(
                key: lensKey,
                duration: reduceMotion ? Duration.zero : Motion.workspaceSwitch,
                curve: Motion.md3Emphasized,
                alignment: _activeAlignment(active, count, horizontal),
                child: _WorkspaceActiveLens(
                  workspace: active,
                  horizontal: horizontal,
                  reduceMotion: reduceMotion,
                ),
              ),
            ),
            Flex(
              direction: horizontal ? Axis.horizontal : Axis.vertical,
              children: [
                for (final workspace in workspaces)
                  _WorkspacePipButton(
                    key: ValueKey<String>('workspace-pip-${workspace.id}'),
                    workspace: workspace,
                    accent: accent,
                    horizontal: horizontal,
                    style: style,
                    textScale: textScale,
                    onPressed: onPressed == null
                        ? null
                        : () => onPressed!(workspace),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspacePipButton extends StatelessWidget {
  const _WorkspacePipButton({
    required this.workspace,
    required this.accent,
    required this.horizontal,
    required this.style,
    required this.textScale,
    required this.onPressed,
    super.key,
  });

  final Workspace workspace;
  final WallpaperAccent accent;
  final bool horizontal;
  final PipStyle style;

  /// Rail-wide scale for the pip glyph (Roman numerals shrink as one).
  final double textScale;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final description = workspace.occupied
        ? l10n.workspaceOccupied
        : l10n.workspaceEmpty;
    final label =
        '${l10n.workspaceLabel(workspace.name)}, $description'
        '${workspace.urgent ? ', ${l10n.workspaceUrgent}' : ''}'
        '${workspace.focused ? ', ${l10n.workspaceActive}' : ''}';
    final textStyle = workspace.focused
        ? ShellText.systemBarValue.copyWith(
            color: accent.color,
            fontSize: ShellText.systemBarValue.fontSize! + 1,
          )
        : ShellText.systemBarCaption.copyWith(
            color: workspace.occupied
                ? ShellMediaColors.lightForeground
                : ShellMediaColors.lightForegroundSecondary.withValues(
                    alpha: 0.3,
                  ),
            fontSize: ShellText.systemBarCaption.fontSize! + 2,
          );
    final dotColor = workspace.focused
        ? accent.color
        : workspace.occupied
        ? ShellMediaColors.lightForeground
        : ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.3);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final itemSize = horizontal
        ? const Size(WorkspacesPill._itemExtent, WorkspacesPill._crossExtent)
        : const Size(WorkspacesPill._crossExtent, WorkspacesPill._itemExtent);
    return PillTooltip(
      accent: accent,
      label: label,
      child: Semantics(
        button: true,
        selected: workspace.focused,
        label: label,
        onTap: onPressed,
        child: ExcludeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              mouseCursor: SystemMouseCursors.click,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return accent.color.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed)) {
                  return accent.color.withValues(alpha: 0.08);
                }
                return ShellMediaColors.transparentDark;
              }),
              onTap: onPressed,
              child: SizedBox(
                width: itemSize.width,
                height: itemSize.height,
                child: Center(
                  child: style == PipStyle.dot
                      ? SizedBox.square(
                          key: ValueKey<String>(
                            'workspace-dot-${workspace.id}',
                          ),
                          dimension: WorkspacesPill._dotExtent,
                          child: AnimatedContainer(
                            duration: reduceMotion
                                ? Duration.zero
                                : Motion.pill,
                            curve: Motion.standard,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColor,
                            ),
                          ),
                        )
                      : AnimatedDefaultTextStyle(
                          duration: reduceMotion ? Duration.zero : Motion.pill,
                          curve: Motion.standard,
                          style: textStyle,
                          // Natural layout, then one uniform scale for every
                          // numeral so no pip renders larger than another.
                          child: OverflowBox(
                            maxWidth: double.infinity,
                            maxHeight: double.infinity,
                            child: Transform.scale(
                              scale: textScale,
                              child: Text(
                                pipLabel(workspace.name, style),
                                maxLines: 1,
                              ),
                            ),
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

/// One scale for a rail's Roman numerals: the widest label scaled to fit the
/// pip cell, so every numeral paints at the same size.
double romanPipScale(Iterable<String> labels, {double maxWidth = 16}) {
  final style = ShellText.systemBarValue.copyWith(
    fontSize: ShellText.systemBarValue.fontSize! + 1,
  );
  var scale = 1.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    if (width > maxWidth) {
      scale = math.min(scale, maxWidth / width);
    }
  }
  return scale;
}

/// The glyph one pip paints: the name for `number`, a Roman numeral when the
/// name is a countable number for `roman`, and the name again when it is not.
String pipLabel(String name, PipStyle style) {
  if (style != PipStyle.roman) {
    return name;
  }
  final value = int.tryParse(name);
  if (value == null) {
    return name;
  }
  return romanNumeral(value) ?? name;
}

/// `1` → `I` … `3999` → `MMMCMXCIX`; null when the value has no compact
/// Roman form.
String? romanNumeral(int value) {
  if (value < 1 || value > 3999) {
    return null;
  }
  const table = <(int, String)>[
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  final out = StringBuffer();
  var rest = value;
  for (final (amount, glyph) in table) {
    while (rest >= amount) {
      out.write(glyph);
      rest -= amount;
    }
  }
  return out.toString();
}

Alignment _activeAlignment(int active, int count, bool horizontal) {
  final index = active < 0 ? 0 : active;
  final position = count <= 1 ? 0.0 : -1.0 + (2.0 * index / (count - 1));
  return horizontal ? Alignment(position, 0) : Alignment(0, position);
}

class _WorkspaceActiveLens extends StatefulWidget {
  const _WorkspaceActiveLens({
    required this.workspace,
    required this.horizontal,
    required this.reduceMotion,
  });

  final int workspace;
  final bool horizontal;
  final bool reduceMotion;

  @override
  State<_WorkspaceActiveLens> createState() => _WorkspaceActiveLensState();
}

class _WorkspaceActiveLensState extends State<_WorkspaceActiveLens>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shape = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );
  var _generation = 0;

  @override
  void didUpdateWidget(_WorkspaceActiveLens oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _generation++;
      _shape.stop();
      _shape.value = 1;
    } else if (widget.workspace != oldWidget.workspace) {
      _generation++;
      unawaited(_animateLiquid(_generation));
    }
  }

  Future<void> _animateLiquid(int generation) async {
    _shape.stop();
    try {
      await _shape
          .animateTo(
            1.34,
            duration: Motion.workspaceIndicatorTakeoff,
            curve: Motion.md3EmphasizedAccelerate,
          )
          .orCancel;
      if (generation != _generation) {
        return;
      }
      await _shape
          .animateTo(
            0.94,
            duration: Motion.workspaceIndicatorTravel,
            curve: Motion.standard,
          )
          .orCancel;
      if (generation != _generation) {
        return;
      }
      await _shape
          .animateTo(
            1,
            duration: Motion.workspaceIndicatorSettle,
            curve: Motion.md3EmphasizedDecelerate,
          )
          .orCancel;
    } on TickerCanceled {
      // A newer workspace target continues from the current deformation.
    }
  }

  @override
  void dispose() {
    _generation++;
    _shape.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shape,
      builder: (context, child) {
        final mainScale = _shape.value;
        final delta = mainScale - 1;
        final crossScale = delta >= 0 ? 1 - (delta * 0.34) : 1 - (delta * 0.72);
        return Transform.scale(
          scaleX: widget.horizontal ? mainScale : crossScale,
          scaleY: widget.horizontal ? crossScale : mainScale,
          child: child,
        );
      },
      child: SizedBox(
        width: widget.horizontal
            ? WorkspacesPill._itemExtent
            : WorkspacesPill._crossExtent,
        height: widget.horizontal
            ? WorkspacesPill._crossExtent
            : WorkspacesPill._itemExtent,
        child: Center(
          child: SizedBox.square(
            dimension: WorkspacesPill._lensSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ShellMediaColors.darkness.withValues(alpha: 0.36),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
