import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/availability.dart';
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

String _reasonLabel(AppLocalizations l10n, ModuleUnavailableReason reason) {
  return switch (reason) {
    ModuleUnavailableReason.noBattery => l10n.settingsUnavailableNoBattery,
  };
}

String _zoneLabel(AppLocalizations l10n, ModuleZone zone) {
  return switch (zone) {
    ModuleZone.leading => l10n.settingsPlacementLeading,
    ModuleZone.center => l10n.settingsPlacementCenter,
    ModuleZone.trailing => l10n.settingsPlacementTrailing,
  };
}

/// Modules page: every module the bar knows, grouped by placement zone and
/// ordered as the strip renders it. Drag a row onto another segment to move
/// it there, or onto another row to reorder it.
class ModulesPage extends StatefulWidget {
  const ModulesPage({
    this.availabilityProbe = probeModuleAvailability,
    super.key,
  });

  /// Hardware probe; injected by the shell and faked in tests.
  final List<ModuleAvailability> Function() availabilityProbe;

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  DebouncedSaver? _saver;
  late final List<ModuleAvailability> _unavailable = widget.availabilityProbe();

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

  /// Keyboard reorder within a zone: swaps [module] with its neighbour.
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

  /// Places [dragged] in [zone], before [before] when given; appends after
  /// the zone's last module otherwise.
  void _dropOn(
    SettingsAppController controller,
    String dragged, {
    required ModuleZone zone,
    String? before,
  }) {
    _saverFor(controller).apply((settings) {
      final placement = Map<String, ModuleZone>.of(settings.modulePlacement);
      if (zone == defaultModuleZone(dragged)) {
        placement.remove(dragged);
      } else {
        placement[dragged] = zone;
      }
      final modules = List<String>.of(settings.modules)..remove(dragged);
      var index = before == null ? -1 : modules.indexOf(before);
      if (index < 0) {
        final last = modules.lastIndexWhere(
          (candidate) =>
              (placement[candidate] ?? defaultModuleZone(candidate)) == zone,
        );
        index = last >= 0 ? last + 1 : modules.length;
      }
      modules.insert(index.clamp(0, modules.length), dragged);
      return settings.copyWith(modulePlacement: placement, modules: modules);
    });
  }

  void _moveZoneBy(SettingsAppController controller, String module, int delta) {
    final current = controller.settings.zoneFor(module);
    final next = ModuleZone.values.indexOf(current) + delta;
    if (next < 0 || next >= ModuleZone.values.length) {
      return;
    }
    _dropOn(controller, module, zone: ModuleZone.values[next]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final settings = controller.settings;
    final unavailableModules = <String>{
      for (final unavailable in _unavailable) unavailable.module,
    };
    final groups = <ModuleZone, List<String>>{
      for (final zone in ModuleZone.values)
        zone: [
          for (final module in settings.modules)
            if (!unavailableModules.contains(module) &&
                settings.zoneFor(module) == zone)
              module,
        ],
    };
    final disabled = <String>[
      for (final module in BarSettings.knownModules)
        if (!settings.includes(module) && !unavailableModules.contains(module))
          module,
    ];

    Widget moduleRow(
      String module, {
      required ModuleZone zone,
      required bool reorderable,
    }) {
      return _ModuleRow(
        key: ValueKey<String>('module-$module'),
        module: module,
        label: moduleLabel(l10n, module),
        enabled: settings.includes(module),
        reorderable: reorderable,
        onToggle: (value) => _toggle(controller, module, value),
        onDrop: (dragged) =>
            _dropOn(controller, dragged, zone: zone, before: module),
        onKeyboardMove: (delta) => _moveWithinZone(controller, module, delta),
        onKeyboardZone: (delta) => _moveZoneBy(controller, module, delta),
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
              key: const ValueKey<String>('reset-placement'),
              label: l10n.settingsResetOption(l10n.settingsModulePlacement),
              enabled: settings.modulePlacement.isNotEmpty,
              onPressed: () => _saverFor(controller).apply(
                (settings) => settings.copyWith(
                  modulePlacement: const <String, ModuleZone>{},
                ),
              ),
            ),
            const SizedBox(width: 6),
            SettingsResetButton(
              key: const ValueKey<String>('reset-module-order'),
              label: l10n.settingsResetOption(l10n.settingsModulesTitle),
              enabled: !listEquals(settings.modules, BarSettings.knownModules),
              onPressed: () => _saverFor(controller).apply(
                (settings) =>
                    settings.copyWith(modules: BarSettings.knownModules),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (final entry in groups.entries) ...[
          SettingsHeading(
            key: ValueKey<String>('module-zone-${entry.key.wire}'),
            title: _zoneLabel(l10n, entry.key),
          ),
          const SizedBox(height: 10),
          _ZoneDropTarget(
            key: ValueKey<String>('module-zone-drop-${entry.key.wire}'),
            onAccept: (dragged) =>
                _dropOn(controller, dragged, zone: entry.key),
            child: SettingsCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: entry.value.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        l10n.settingsModulesEmptyZone,
                        style: ShellText.systemBarCaption.copyWith(
                          color: ShellMediaColors.lightForegroundSecondary,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final module in entry.value)
                          moduleRow(module, zone: entry.key, reorderable: true),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_unavailable.isNotEmpty) ...[
          SettingsHeading(
            key: const ValueKey<String>('module-zone-unavailable'),
            title: l10n.settingsModulesUnavailable,
          ),
          const SizedBox(height: 10),
          SettingsCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final unavailable in _unavailable)
                  _UnavailableRow(
                    key: ValueKey<String>(
                      'module-unavailable-${unavailable.module}',
                    ),
                    label: moduleLabel(l10n, unavailable.module),
                    reason: _reasonLabel(l10n, unavailable.reason),
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
                for (final module in disabled)
                  moduleRow(
                    module,
                    zone: settings.zoneFor(module),
                    reorderable: false,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A module this machine cannot run, with the reason why.
class _UnavailableRow extends StatelessWidget {
  const _UnavailableRow({required this.label, required this.reason, super.key});

  final String label;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: ShellText.systemBarValue.copyWith(
                color: ShellMediaColors.lightForegroundSecondary,
              ),
            ),
          ),
          Text(
            reason,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary.withValues(
                alpha: 0.7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.module,
    required this.label,
    required this.enabled,
    required this.reorderable,
    required this.onToggle,
    required this.onDrop,
    required this.onKeyboardMove,
    required this.onKeyboardZone,
    super.key,
  });

  final String module;
  final String label;
  final bool enabled;
  final bool reorderable;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onDrop;
  final ValueChanged<int> onKeyboardMove;
  final ValueChanged<int> onKeyboardZone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _ModuleDragHandle(
            key: ValueKey<String>('module-drag-$module'),
            module: module,
            label: l10n.settingsModuleDrag,
            feedbackLabel: label,
            enabled: reorderable,
            onKeyboardMove: onKeyboardMove,
            onKeyboardZone: onKeyboardZone,
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
    if (!reorderable) {
      return row;
    }
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != module,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidates, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? const Color(0x00000000)
              : ShellBrandColors.defaultAccent.withValues(alpha: 0.08),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: row,
      ),
    );
  }
}

/// A segment's card as a whole is a drop target; hovering draws an accent
/// outline so an empty segment still reads as droppable.
class _ZoneDropTarget extends StatelessWidget {
  const _ZoneDropTarget({
    required this.onAccept,
    required this.child,
    super.key,
  });

  final ValueChanged<String> onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: candidates.isEmpty
              ? null
              : Border.all(color: ShellBrandColors.defaultAccent, width: 1.5),
        ),
        child: child,
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

/// The drag affordance for a module row: pointer drag moves the row, and
/// ctrl+arrow / ctrl+shift+arrow keep keyboard reordering and zone moves.
class _ModuleDragHandle extends StatelessWidget {
  const _ModuleDragHandle({
    required this.module,
    required this.label,
    required this.feedbackLabel,
    required this.enabled,
    required this.onKeyboardMove,
    required this.onKeyboardZone,
    super.key,
  });

  final String module;
  final String label;
  final String feedbackLabel;
  final bool enabled;
  final ValueChanged<int> onKeyboardMove;
  final ValueChanged<int> onKeyboardZone;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? ShellMediaColors.lightForegroundSecondary
        : ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.3);
    final handle = MouseRegion(
      cursor: enabled ? SystemMouseCursors.grab : SystemMouseCursors.basic,
      child: SizedBox.square(
        dimension: 24,
        child: Center(
          child: Icon(LucideIcons.gripVertical, size: 15, color: color),
        ),
      ),
    );
    return Semantics(
      label: label,
      enabled: enabled,
      child: ExcludeSemantics(
        child: Focus(
          canRequestFocus: enabled,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent ||
                !HardwareKeyboard.instance.isControlPressed) {
              return KeyEventResult.ignored;
            }
            final shift = HardwareKeyboard.instance.isShiftPressed;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowUp) {
              shift ? onKeyboardZone(-1) : onKeyboardMove(-1);
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowDown) {
              shift ? onKeyboardZone(1) : onKeyboardMove(1);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: enabled
              ? Draggable<String>(
                  data: module,
                  maxSimultaneousDrags: 1,
                  feedback: _DragFeedback(label: feedbackLabel),
                  childWhenDragging: Opacity(opacity: 0.35, child: handle),
                  child: handle,
                )
              : handle,
        ),
      ),
    );
  }
}

/// The lifted row under the pointer: a card matching the segment's radius.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SettingsColors.surfaceHigh,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: SettingsColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Text(label, style: ShellText.systemBarValue),
      ),
    );
  }
}
