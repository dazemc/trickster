import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/controller.dart';
import 'package:trickster/src/settings/saver.dart';
import 'package:trickster/src/settings/scope.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';

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

String _zoneLabel(AppLocalizations l10n, ModuleZone zone) {
  return switch (zone) {
    ModuleZone.leading => l10n.settingsPlacementLeading,
    ModuleZone.center => l10n.settingsPlacementCenter,
    ModuleZone.trailing => l10n.settingsPlacementTrailing,
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

  void _place(
    SettingsAppController controller,
    String module,
    ModuleZone zone,
  ) {
    _saverFor(controller).apply((settings) {
      final placement = Map<String, ModuleZone>.of(settings.modulePlacement);
      if (zone == defaultModuleZone(module)) {
        placement.remove(module);
      } else {
        placement[module] = zone;
      }
      return settings.copyWith(modulePlacement: placement);
    });
  }

  void _moveWithinZone(
    SettingsAppController controller,
    String module,
    int delta,
  ) {
    _saverFor(controller).apply((settings) {
      final zone = settings.zoneFor(module);
      final segment = [
        for (final candidate in settings.modules)
          if (settings.zoneFor(candidate) == zone) candidate,
      ];
      final index = segment.indexOf(module);
      final target = index + delta;
      if (index < 0 || target < 0 || target >= segment.length) {
        return settings;
      }
      final modules = List<String>.of(settings.modules);
      final other = segment[target];
      final a = modules.indexOf(module);
      final b = modules.indexOf(other);
      modules[a] = other;
      modules[b] = module;
      return settings.copyWith(modules: modules);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final settings = controller.settings;
    final groups = <ModuleZone, List<String>>{
      for (final zone in ModuleZone.values)
        zone: [
          for (final module in settings.modules)
            if (settings.zoneFor(module) == zone) module,
        ],
    };
    final disabled = <String>[
      for (final module in BarSettings.knownModules)
        if (!settings.includes(module)) module,
    ];

    Widget moduleRow(String module, {required bool first, required bool last}) {
      final enabled = settings.includes(module);
      return _ModuleRow(
        key: ValueKey<String>('module-$module'),
        module: module,
        label: moduleLabel(l10n, module),
        enabled: enabled,
        first: !enabled || first,
        last: !enabled || last,
        zone: settings.zoneFor(module),
        placementExplicit: settings.modulePlacement.containsKey(module),
        onPlace: (zone) => _place(controller, module, zone),
        onResetPlacement: () => _saverFor(controller).apply((settings) {
          final placement = Map<String, ModuleZone>.of(settings.modulePlacement)
            ..remove(module);
          return settings.copyWith(modulePlacement: placement);
        }),
        onToggle: (value) => _toggle(controller, module, value),
        onMoveUp: () => _moveWithinZone(controller, module, -1),
        onMoveDown: () => _moveWithinZone(controller, module, 1),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SettingsHeading(
                title: l10n.settingsModulesTitle,
                caption: l10n.settingsModulesCaption,
              ),
            ),
            SettingsResetButton(
              key: const ValueKey<String>('reset-module-order'),
              label: l10n.settingsResetOption(l10n.settingsModulesTitle),
              enabled: !listEquals(
                controller.settings.modules,
                BarSettings.knownModules,
              ),
              onPressed: () => _saverFor(controller).apply(
                (settings) =>
                    settings.copyWith(modules: BarSettings.knownModules),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (final entry in groups.entries)
          if (entry.value.isNotEmpty) ...[
            SettingsHeading(
              key: ValueKey<String>('module-zone-${entry.key.wire}'),
              title: _zoneLabel(l10n, entry.key),
            ),
            const SizedBox(height: 10),
            SettingsCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (final (index, module) in entry.value.indexed)
                    moduleRow(
                      module,
                      first: index == 0,
                      last: index == entry.value.length - 1,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        if (disabled.isNotEmpty) ...[
          SettingsHeading(
            key: const ValueKey<String>('module-zone-disabled'),
            title: l10n.settingsModulesDisabled,
          ),
          const SizedBox(height: 10),
          SettingsCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final (index, module) in disabled.indexed)
                  moduleRow(
                    module,
                    first: index == 0,
                    last: index == disabled.length - 1,
                  ),
              ],
            ),
          ),
        ],
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
    required this.zone,
    required this.placementExplicit,
    required this.onPlace,
    required this.onResetPlacement,
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
  final ModuleZone zone;
  final bool placementExplicit;
  final ValueChanged<ModuleZone> onPlace;
  final VoidCallback onResetPlacement;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (enabled)
            Padding(
              padding: const EdgeInsets.only(left: 64, top: 8, bottom: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.settingsModulePlacement,
                    style: ShellText.systemBarCaption.copyWith(
                      color: ShellMediaColors.lightForegroundSecondary,
                    ),
                  ),
                  for (final place in ModuleZone.values)
                    SettingsChoiceChip(
                      key: ValueKey<String>(
                        'module-placement-$module-${place.wire}',
                      ),
                      label: _zoneLabel(l10n, place),
                      selected: zone == place,
                      onPressed: () => onPlace(place),
                    ),
                  SettingsResetButton(
                    key: ValueKey<String>('reset-placement-$module'),
                    label: l10n.settingsResetOption(
                      l10n.settingsModulePlacement,
                    ),
                    enabled: placementExplicit,
                    onPressed: onResetPlacement,
                  ),
                ],
              ),
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
                child: Icon(
                  up ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 15,
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
    );
  }
}
