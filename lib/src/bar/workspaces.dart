import 'package:flutter/widgets.dart';

import '../services/workspaces.dart';
import '../theme/accent.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class WorkspacesPill extends StatelessWidget {
  const WorkspacesPill({
    required this.accent,
    required this.workspaces,
    required this.horizontal,
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

  @override
  Widget build(BuildContext context) {
    final count = workspaces.length;
    final active = workspaces.indexWhere((workspace) => workspace.focused);
    final mainExtent = _itemExtent * count;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
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
                  SizedBox(
                    key: ValueKey<String>('workspace-pip-${workspace.id}'),
                    width: horizontal ? _itemExtent : _crossExtent,
                    height: horizontal ? _crossExtent : _itemExtent,
                    child: Center(
                      child: SizedBox.square(
                        dimension: _pipSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: workspace.focused
                                ? accent.color
                                : ShellMediaColors.lightForegroundSecondary
                                      .withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Alignment _activeAlignment(int active, int count, bool horizontal) {
  final index = active < 0 ? 0 : active;
  final position = count <= 1
      ? 0.0
      : -1.0 + (2.0 * index / (count - 1));
  return horizontal ? Alignment(position, 0) : Alignment(0, position);
}
