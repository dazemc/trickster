import 'package:flutter/widgets.dart';

import '../../config/settings.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../locale.dart';
import '../../theme/motion.dart';
import '../../theme/tokens.dart';
import '../controller.dart';
import '../saver.dart';
import '../scope.dart';
import '../settings_theme.dart';

/// Pulls a module's display name from the shared catalog.
String moduleLabel(AppLocalizations l10n, String module) {
  return switch (module) {
    'workspaces' => l10n.moduleWorkspaces,
    'tray' => l10n.moduleTray,
    'media' => l10n.moduleMedia,
    'cpu' => l10n.moduleCpu,
    'gpu' => l10n.moduleGpu,
    'battery' => l10n.moduleBattery,
    'clock' => l10n.moduleClock,
    _ => module,
  };
}

/// Modules page: every module the bar knows, toggled on or off and ordered
/// exactly as the strip renders it.
class ModulesPage extends StatefulWidget {
  const ModulesPage({super.key});

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  DebouncedSaver? _saver;

  @override
  void dispose() {
    _saver?.dispose();
    super.dispose();
  }

  DebouncedSaver _saverFor(SettingsAppController controller) =>
      _saver ??= DebouncedSaver(controller);

  void _toggle(SettingsAppController controller, String module, bool enabled) {
    _saverFor(controller).apply((settings) {
      final modules = List<String>.of(settings.modules);
      if (enabled) {
        if (!modules.contains(module)) {
          modules.add(module);
        }
      } else {
        modules.remove(module);
      }
      return settings.copyWith(modules: modules);
    });
  }

  void _move(SettingsAppController controller, String module, int delta) {
    _saverFor(controller).apply((settings) {
      final modules = List<String>.of(settings.modules);
      final index = modules.indexOf(module);
      final target = index + delta;
      if (index < 0 || target < 0 || target >= modules.length) {
        return settings;
      }
      modules
        ..removeAt(index)
        ..insert(target, module);
      return settings.copyWith(modules: modules);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    // Disabled modules stay listed, appended after the configured ones.
    final ordered = <String>[
      ...controller.settings.modules,
      for (final module in BarSettings.knownModules)
        if (!controller.settings.includes(module)) module,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(
          title: l10n.settingsModulesTitle,
          caption: l10n.settingsModulesCaption,
        ),
        const SizedBox(height: 20),
        SettingsCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              for (final module in ordered)
                _ModuleRow(
                  key: ValueKey<String>('module-$module'),
                  module: module,
                  label: moduleLabel(l10n, module),
                  enabled: controller.settings.includes(module),
                  first: ordered.indexOf(module) == 0,
                  last: ordered.indexOf(module) == ordered.length - 1,
                  onToggle: (value) => _toggle(controller, module, value),
                  onMoveUp: () => _move(controller, module, -1),
                  onMoveDown: () => _move(controller, module, 1),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.module,
    required this.label,
    required this.enabled,
    required this.first,
    required this.last,
    required this.onToggle,
    required this.onMoveUp,
    required this.onMoveDown,
    super.key,
  });

  final String module;
  final String label;
  final bool enabled;
  final bool first;
  final bool last;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _MoveButton(
            key: ValueKey<String>('module-up-$module'),
            label: l10n.settingsModuleMoveUp,
            up: true,
            enabled: !first,
            onPressed: onMoveUp,
          ),
          const SizedBox(width: 4),
          _MoveButton(
            key: ValueKey<String>('module-down-$module'),
            label: l10n.settingsModuleMoveDown,
            up: false,
            enabled: !last,
            onPressed: onMoveDown,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: ShellText.systemBarValue.copyWith(
                color: enabled
                    ? ShellMediaColors.lightForeground
                    : ShellMediaColors.lightForegroundSecondary,
              ),
            ),
          ),
          _ModuleToggle(
            key: ValueKey<String>('module-toggle-$module'),
            label: label,
            enabled: enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

class _ModuleToggle extends StatelessWidget {
  const _ModuleToggle({
    required this.label,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: enabled,
      label: label,
      hint: context.l10n.settingsModuleToggleHint,
      onTap: () => onChanged(!enabled),
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!enabled),
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Motion.standard,
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(999)),
                color: enabled
                    ? ShellBrandColors.defaultAccent
                    : SettingsColors.surfaceHigh,
                border: Border.all(color: SettingsColors.outline),
              ),
              child: AnimatedAlign(
                duration: Motion.pill,
                curve: Motion.standard,
                alignment: enabled
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled
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
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({
    required this.label,
    required this.up,
    required this.enabled,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool up;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? onPressed : null,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? onPressed : null,
            child: SizedBox.square(
              dimension: 24,
              child: Center(
                child: CustomPaint(
                  size: const Size(8, 8),
                  painter: _ArrowPainter(
                    up: up,
                    color: enabled
                        ? ShellMediaColors.lightForeground
                        : ShellMediaColors.lightForegroundSecondary.withValues(
                            alpha: 0.35,
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

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.up, required this.color});

  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (up) {
      path
        ..moveTo(0, size.height)
        ..lineTo(size.width / 2, 0)
        ..lineTo(size.width, size.height);
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0);
    }
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.up != up || oldDelegate.color != color;
}
