import 'package:flutter/widgets.dart';

import '../services/workspaces.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class WorkspacesPill extends StatelessWidget {
  const WorkspacesPill({
    required this.accent,
    required this.workspaces,
    super.key,
  });

  final WallpaperAccent accent;
  final List<Workspace> workspaces;

  @override
  Widget build(BuildContext context) {
    return SystemBarCard(
      accent: accent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < workspaces.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Text(
              workspaces[i].name,
              style: ShellText.systemBarValue.copyWith(
                color: workspaces[i].focused
                    ? accent.color
                    : workspaces[i].urgent
                    ? ShellTelemetryColors.warning
                    : ShellMediaColors.lightForegroundSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
