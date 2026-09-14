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
import 'package:trickster/src/settings/module_options.dart';
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
/// ordered as the strip renders it. Dragging a row lifts it whole, opens a
/// live gap where it would land, and commits on release.
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
  /// How far past a zone's card still counts as that zone's drop area, so
  /// releasing below the last row appends instead of snapping back.
  static const double _zoneDropReach = 48;

  DebouncedSaver? _saver;
  late final List<ModuleAvailability> _unavailable = widget.availabilityProbe();

  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
  final Map<ModuleZone, GlobalKey> _zoneKeys = <ModuleZone, GlobalKey>{};

  final Set<String> _expanded = <String>{};
  String? _dragging;
  ModuleZone? _previewZone;
  int _previewIndex = 0;
  Offset? _lastPointer;
  bool _dropHandled = false;

  GlobalKey _rowKey(String module) =>
      _rowKeys.putIfAbsent(module, GlobalKey.new);

  GlobalKey _zoneKey(ModuleZone zone) =>
      _zoneKeys.putIfAbsent(zone, GlobalKey.new);

  @override
  void dispose() {
    _saver?.dispose();
    super.dispose();
  }

  DebouncedSaver _saverFor(SettingsAppController controller) =>
      _saver ??= DebouncedSaver(controller);

  /// The configured modules per zone, in strip order; [exclude] removes the
  /// row currently under the pointer.
  Map<ModuleZone, List<String>> _groupsFor(
    BarSettings settings, {
    String? exclude,
  }) {
    final unavailable = <String>{
      for (final unavailable in _unavailable) unavailable.module,
    };
    return <ModuleZone, List<String>>{
      for (final zone in ModuleZone.values)
        zone: [
          for (final module in settings.modules)
            if (module != exclude &&
                !unavailable.contains(module) &&
                settings.zoneFor(module) == zone)
              module,
        ],
    };
  }

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

  /// Places [dragged] at [index] within [zone] (clamped); the rest of the
  /// strip keeps its order.
  void _dropOn(
    SettingsAppController controller,
    String dragged, {
    required ModuleZone zone,
    required int index,
  }) {
    _saverFor(controller).apply((settings) {
      final placement = Map<String, ModuleZone>.of(settings.modulePlacement);
      if (zone == defaultModuleZone(dragged)) {
        placement.remove(dragged);
      } else {
        placement[dragged] = zone;
      }
      final modules = List<String>.of(settings.modules)..remove(dragged);
      final inZone = [
        for (final candidate in modules)
          if ((placement[candidate] ?? defaultModuleZone(candidate)) == zone)
            candidate,
      ];
      final at = index.clamp(0, inZone.length);
      final insertAt = inZone.isEmpty
          ? modules.length
          : at < inZone.length
          ? modules.indexOf(inZone[at])
          : modules.indexOf(inZone.last) + 1;
      modules.insert(insertAt, dragged);
      return settings.copyWith(modulePlacement: placement, modules: modules);
    });
  }

  void _moveZoneBy(SettingsAppController controller, String module, int delta) {
    final current = controller.settings.zoneFor(module);
    final next = ModuleZone.values.indexOf(current) + delta;
    if (next < 0 || next >= ModuleZone.values.length) {
      return;
    }
    final target = ModuleZone.values[next];
    final groups = _groupsFor(controller.settings, exclude: module);
    _dropOn(
      controller,
      module,
      zone: target,
      index: groups[target]?.length ?? 0,
    );
  }

  void _startDrag(
    SettingsAppController controller,
    String module,
    ModuleZone zone,
  ) {
    final current = _groupsFor(controller.settings)[zone] ?? const <String>[];
    setState(() {
      _dragging = module;
      _previewZone = zone;
      _previewIndex = current.indexOf(module).clamp(0, current.length);
    });
  }

  /// Tracks the pointer over the segment geometry so the gap follows the
  /// drag before release.
  ///
  /// The nearest zone wins within [_zoneDropReach], so releasing under the
  /// last row still appends there instead of snapping back; the Disabled
  /// section clears the preview when the pointer enters it.
  void _updateDrag(SettingsAppController controller, Offset position) {
    final dragging = _dragging;
    if (dragging == null) {
      return;
    }
    _lastPointer = position;
    final groups = _groupsFor(controller.settings, exclude: dragging);
    ModuleZone? zone;
    var bestDistance = _zoneDropReach;
    for (final entry in groups.entries) {
      final box =
          _zoneKey(entry.key).currentContext?.findRenderObject() as RenderBox?;
      if (box == null) {
        continue;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final distance = position.dy < rect.top
          ? rect.top - position.dy
          : position.dy > rect.bottom
          ? position.dy - rect.bottom
          : 0.0;
      if (distance > _zoneDropReach) {
        continue;
      }
      if (zone == null || distance < bestDistance) {
        bestDistance = distance;
        zone = entry.key;
      }
    }
    if (zone == null) {
      return;
    }
    var index = 0;
    for (final candidate in groups[zone]!) {
      final rowBox =
          _rowKey(candidate).currentContext?.findRenderObject() as RenderBox?;
      if (rowBox == null) {
        continue;
      }
      final rowRect = rowBox.localToGlobal(Offset.zero) & rowBox.size;
      if (position.dy > rowRect.center.dy) {
        index += 1;
      }
    }
    if (zone == _previewZone && index == _previewIndex) {
      return;
    }
    setState(() {
      _previewZone = zone;
      _previewIndex = index;
    });
  }

  /// True when [position] sits inside a placement segment; used when the
  /// target's acceptance did not register but the release clearly landed.
  bool _withinSegment(Offset position) {
    for (final zone in ModuleZone.values) {
      final box =
          _zoneKey(zone).currentContext?.findRenderObject() as RenderBox?;
      if (box == null) {
        continue;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.inflate(_zoneDropReach).contains(position)) {
        return true;
      }
    }
    return false;
  }

  void _endDrag(SettingsAppController controller, bool accepted) {
    final module = _dragging;
    final zone = _previewZone;
    final index = _previewIndex;
    final pointer = _lastPointer;
    final handled = _dropHandled;
    _dropHandled = false;
    _lastPointer = null;
    setState(() {
      _dragging = null;
      _previewZone = null;
    });
    if (handled || module == null || zone == null) {
      return;
    }
    // The target usually accepts; fall back to the release position so a
    // first drag never silently reverts.
    if (!accepted && (pointer == null || !_withinSegment(pointer))) {
      return;
    }
    _dropOn(controller, module, zone: zone, index: index);
  }

  /// Turns [module] off from the Disabled section's drop target.
  void _disableDropped(SettingsAppController controller, String module) {
    _dropHandled = true;
    _saverFor(controller).apply((settings) {
      final modules = List<String>.of(settings.modules)..remove(module);
      return settings.copyWith(modules: modules);
    });
  }

  /// The always-present "Drop a module here" strip at the end of a zone and
  /// in an empty Disabled section.
  Widget _dropHere({required String label, required bool active}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: active
              ? ShellBrandColors.defaultAccent.withValues(alpha: 0.10)
              : null,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(
            color: active
                ? ShellBrandColors.defaultAccent
                : SettingsColors.outline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropPreview() {
    return Container(
      key: const ValueKey<String>('module-drop-preview'),
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: ShellBrandColors.defaultAccent.withValues(alpha: 0.10),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(
          color: ShellBrandColors.defaultAccent.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final settings = controller.settings;
    // The dragged row stays in the tree (its Draggable collapses it to a
    // zero-height slot) so the drag survives the preview rebuilds.
    final groups = _groupsFor(settings);
    final unavailableModules = <String>{
      for (final unavailable in _unavailable) unavailable.module,
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
      required double feedbackWidth,
      bool draggableOut = false,
    }) {
      final hasOptions = reorderable && moduleHasOptions(module);
      return _ModuleRow(
        key: ValueKey<String>('module-$module'),
        module: module,
        label: moduleLabel(l10n, module),
        enabled: settings.includes(module),
        reorderable: reorderable || draggableOut,
        options: hasOptions ? ModuleOptionsPanel(module: module) : null,
        optionsExpanded: _expanded.contains(module),
        onToggleOptions: hasOptions
            ? () => setState(() {
                if (!_expanded.remove(module)) {
                  _expanded.add(module);
                }
              })
            : null,
        feedbackWidth: feedbackWidth,
        onDragStart: () => _startDrag(controller, module, zone),
        onDragUpdate: (position) => _updateDrag(controller, position),
        onDragEnd: (accepted) => _endDrag(controller, accepted),
        onToggle: (value) => _toggle(controller, module, value),
        onKeyboardMove: draggableOut
            ? (_) {}
            : (delta) => _moveWithinZone(controller, module, delta),
        onKeyboardZone: draggableOut
            ? (_) {}
            : (delta) => _moveZoneBy(controller, module, delta),
      );
    }

    List<Widget> segmentChildren(
      ModuleZone zone,
      List<String> modules,
      double feedbackWidth,
    ) {
      final dragging = _dragging;
      final showPreview = dragging != null && _previewZone == zone;
      // The preview index counts the rows without the lifted one, while the
      // rendered list still holds its collapsed slot; step past that slot
      // so the gap lands under the half of the row the pointer is on.
      var previewAt = _previewIndex.clamp(0, modules.length);
      if (showPreview) {
        final sourceIndex = modules.indexOf(dragging);
        if (sourceIndex >= 0 && sourceIndex < previewAt) {
          previewAt += 1;
        }
      }
      return <Widget>[
        for (var index = 0; index <= modules.length; index++) ...[
          if (showPreview && index == previewAt) _dropPreview(),
          if (index < modules.length)
            KeyedSubtree(
              key: _rowKey(modules[index]),
              child: moduleRow(
                modules[index],
                zone: zone,
                reorderable: true,
                feedbackWidth: feedbackWidth,
              ),
            ),
        ],
      ];
    }

    return LayoutBuilder(
      builder: (context, constraints) => DragTarget<String>(
        onWillAcceptWithDetails: (details) => true,
        onAcceptWithDetails: (_) {},
        builder: (context, candidates, rejected) => Column(
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
                  key: const ValueKey<String>('reset-modules'),
                  label: l10n.settingsResetOption(l10n.settingsModulesTitle),
                  enabled:
                      !listEquals(settings.modules, BarSettings.knownModules) ||
                      settings.modulePlacement.isNotEmpty,
                  onPressed: () => _saverFor(controller).apply(
                    (settings) => settings.copyWith(
                      modules: BarSettings.knownModules,
                      modulePlacement: const <String, ModuleZone>{},
                    ),
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
              DecoratedBox(
                key: _zoneKey(entry.key),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  border: _dragging != null && _previewZone == entry.key
                      ? Border.all(
                          color: ShellBrandColors.defaultAccent,
                          width: 1.5,
                        )
                      : null,
                ),
                child: SettingsCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: entry.value.isEmpty && _previewZone != entry.key
                      ? _dropHere(
                          label: l10n.settingsModulesEmptyZone,
                          active: false,
                        )
                      : Column(
                          children: segmentChildren(
                            entry.key,
                            entry.value,
                            constraints.maxWidth,
                          ),
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
            SettingsHeading(
              key: const ValueKey<String>('module-zone-disabled'),
              title: l10n.settingsModulesDisabled,
            ),
            const SizedBox(height: 10),
            DragTarget<String>(
              key: const ValueKey<String>('module-zone-disabled-drop'),
              onWillAcceptWithDetails: (_) => true,
              onAcceptWithDetails: (details) =>
                  _disableDropped(controller, details.data),
              builder: (context, candidates, rejected) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(18)),
                  border: candidates.isNotEmpty
                      ? Border.all(
                          color: ShellBrandColors.defaultAccent,
                          width: 1.5,
                        )
                      : null,
                ),
                child: SettingsCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: disabled.isEmpty && candidates.isEmpty
                      ? _dropHere(
                          label: l10n.settingsModulesEmptyZone,
                          active: false,
                        )
                      : Column(
                          children: [
                            for (final module in disabled)
                              moduleRow(
                                module,
                                zone: settings.zoneFor(module),
                                reorderable: false,
                                draggableOut: true,
                                feedbackWidth: constraints.maxWidth,
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
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
    required this.options,
    required this.optionsExpanded,
    required this.onToggleOptions,
    required this.feedbackWidth,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onToggle,
    required this.onKeyboardMove,
    required this.onKeyboardZone,
    super.key,
  });

  final String module;
  final String label;
  final bool enabled;
  final bool reorderable;
  final Widget? options;
  final bool optionsExpanded;
  final VoidCallback? onToggleOptions;
  final double feedbackWidth;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final ValueChanged<bool> onDragEnd;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onKeyboardMove;
  final ValueChanged<int> onKeyboardZone;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _ModuleDragHandle(
            key: ValueKey<String>('module-drag-$module'),
            label: l10n.settingsModuleDrag,
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
          if (onToggleOptions != null) ...[
            _ModuleOptionsButton(
              key: ValueKey<String>('module-options-$module'),
              label: l10n.settingsModuleOptions(label),
              expanded: optionsExpanded,
              onPressed: onToggleOptions!,
            ),
            const SizedBox(width: 8),
          ],
          _ModuleToggle(
            key: ValueKey<String>('module-toggle-$module'),
            label: label,
            enabled: enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
    final Widget top = !reorderable
        ? header
        // The row travels whole and its slot closes behind it; the proxy
        // keeps the segment's width so the move previews its landing shape.
        : Draggable<String>(
            data: module,
            maxSimultaneousDrags: 1,
            feedback: SizedBox(
              key: const ValueKey<String>('module-drag-feedback'),
              width: feedbackWidth,
              child: _DragFeedback(label: label),
            ),
            childWhenDragging: const SizedBox.shrink(),
            onDragStarted: onDragStart,
            onDragUpdate: (details) => onDragUpdate(details.globalPosition),
            onDragEnd: (details) => onDragEnd(details.wasAccepted),
            child: header,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        top,
        if (options != null && optionsExpanded)
          Padding(
            padding: const EdgeInsets.only(
              left: 64,
              right: 16,
              top: 4,
              bottom: 12,
            ),
            child: options,
          ),
      ],
    );
  }
}

/// The gear that reveals one module's typed options.
class _ModuleOptionsButton extends StatelessWidget {
  const _ModuleOptionsButton({
    required this.label,
    required this.expanded,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: expanded,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 24,
              child: Center(
                child: Icon(
                  LucideIcons.settings,
                  size: 15,
                  color: expanded
                      ? ShellBrandColors.defaultAccent
                      : ShellMediaColors.lightForegroundSecondary,
                ),
              ),
            ),
          ),
        ),
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
    required this.label,
    required this.enabled,
    required this.onKeyboardMove,
    required this.onKeyboardZone,
    super.key,
  });

  final String label;
  final bool enabled;
  final ValueChanged<int> onKeyboardMove;
  final ValueChanged<int> onKeyboardZone;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? ShellMediaColors.lightForegroundSecondary
        : ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.3);
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
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.grab
                : SystemMouseCursors.basic,
            child: SizedBox.square(
              dimension: 24,
              child: Center(
                child: Icon(LucideIcons.gripVertical, size: 15, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lifted row under the pointer: the row's own layout at the segment's
/// width, so the proxy reads as the row moving rather than a floating label.
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 24,
              child: Center(
                child: Icon(
                  LucideIcons.gripVertical,
                  size: 15,
                  color: ShellMediaColors.lightForegroundSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: ShellText.systemBarValue)),
            _ModuleToggle(label: label, enabled: true, onChanged: (_) {}),
          ],
        ),
      ),
    );
  }
}
