import 'package:flutter/material.dart'
    show InkWell, Material, MaterialType, NoSplash, SystemMouseCursors;
import 'package:flutter/widgets.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
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
    this.onPressed,
    super.key,
  });

  static const Key lensKey = ValueKey<String>('workspaces-lens');

  static const double _itemExtent = 20;
  static const double _crossExtent = 18;
  static const double _pipSize = 6;
  static const double _lensSize = 17;

  final WallpaperAccent accent;
  final List<Workspace> workspaces;
  final bool horizontal;
  final ValueChanged<Workspace>? onPressed;

  @override
  Widget build(BuildContext context) {
    final count = workspaces.length;
    final active = workspaces.indexWhere((workspace) => workspace.focused);
    final mainExtent = _itemExtent * count;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return PillTooltip(
      accent: accent,
      label: [for (final workspace in workspaces) workspace.name].join(', '),
      child: SystemBarCard(
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
                  duration: reduceMotion
                      ? Duration.zero
                      : Motion.workspaceSwitch,
                  curve: Motion.md3Emphasized,
                  alignment: _activeAlignment(active, count, horizontal),
                  child: SizedBox(
                    width: horizontal ? _itemExtent : _crossExtent,
                    height: horizontal ? _crossExtent : _itemExtent,
                    child: Center(
                      child: SizedBox.square(
                        dimension: _lensSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.color.withValues(alpha: 0.18),
                          ),
                        ),
                      ),
                    ),
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
                      onPressed: onPressed == null
                          ? null
                          : () => onPressed!(workspace),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspacePipButton extends StatefulWidget {
  const _WorkspacePipButton({
    required this.workspace,
    required this.accent,
    required this.horizontal,
    required this.onPressed,
    super.key,
  });

  final Workspace workspace;
  final WallpaperAccent accent;
  final bool horizontal;
  final VoidCallback? onPressed;

  @override
  State<_WorkspacePipButton> createState() => _WorkspacePipButtonState();
}

class _WorkspacePipButtonState extends State<_WorkspacePipButton> {
  var _hovered = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    final l10n = context.l10n;
    final description = workspace.occupied
        ? l10n.workspaceOccupied
        : l10n.workspaceEmpty;
    final label =
        '${l10n.workspaceLabel(workspace.name)}, $description'
        '${workspace.urgent ? ', ${l10n.workspaceUrgent}' : ''}'
        '${workspace.focused ? ', ${l10n.workspaceActive}' : ''}';
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      selected: workspace.focused,
      label: label,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            mouseCursor: SystemMouseCursors.click,
            splashFactory: NoSplash.splashFactory,
            overlayColor: WidgetStatePropertyAll(
              widget.accent.color.withValues(
                alpha: _hovered || _focused ? 0.12 : 0.0,
              ),
            ),
            onTap: widget.onPressed,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            child: SizedBox(
              width: widget.horizontal
                  ? WorkspacesPill._itemExtent
                  : WorkspacesPill._crossExtent,
              height: widget.horizontal
                  ? WorkspacesPill._crossExtent
                  : WorkspacesPill._itemExtent,
              child: Center(
                child: AnimatedContainer(
                  duration: reduceMotion ? Duration.zero : Motion.pill,
                  curve: Motion.standard,
                  width: WorkspacesPill._pipSize,
                  height: WorkspacesPill._pipSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _pipColor(workspace, widget.accent),
                    border: _focused
                        ? Border.all(color: widget.accent.color, width: 1.5)
                        : null,
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

Alignment _activeAlignment(int active, int count, bool horizontal) {
  final index = active < 0 ? 0 : active;
  final position = count <= 1 ? 0.0 : -1.0 + (2.0 * index / (count - 1));
  return horizontal ? Alignment(position, 0) : Alignment(0, position);
}

Color _pipColor(Workspace workspace, WallpaperAccent accent) {
  if (workspace.focused) {
    return accent.color;
  }
  if (workspace.urgent) {
    return ShellTelemetryColors.warning;
  }
  if (workspace.occupied) {
    return ShellMediaColors.lightForeground;
  }
  return ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.55);
}
