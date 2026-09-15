import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/availability.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/module_options.dart';
import 'package:trickster/src/settings/modules_bloc.dart';
import 'package:trickster/src/settings/settings_theme.dart';
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
  const ModulesPage({this.workspaceNames, super.key});

  /// Source of live workspace names for the pip mapping editor; null asks
  /// the running bar over the control socket.
  final Future<List<String>> Function()? workspaceNames;

  @override
  State<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends State<ModulesPage> {
  /// How far past a zone's card a release still counts, used when the page
  /// target did not register the drop.
  static const double _zoneDropReach = 120;

  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
  final Map<ModuleZone, GlobalKey> _zoneKeys = <ModuleZone, GlobalKey>{};

  final GlobalKey _disabledKey = GlobalKey();

  GlobalKey _rowKey(String module) =>
      _rowKeys.putIfAbsent(module, GlobalKey.new);

  GlobalKey _zoneKey(ModuleZone zone) =>
      _zoneKeys.putIfAbsent(zone, GlobalKey.new);

  /// Tracks the pointer over the segment geometry so the gap follows the
  /// drag before release.
  ///
  /// The nearest zone wins wherever the pointer is, so releasing under the
  /// last row appends there. Hovering the Disabled area leaves the preview
  /// alone (only the pointer is recorded): that card is the
  /// drag-to-disable gesture.
  void _updateDrag(ModulesBloc modules, Offset position) {
    final state = modules.state;
    final dragging = state.dragging;
    if (dragging == null) {
      return;
    }
    final disabledBox =
        _disabledKey.currentContext?.findRenderObject() as RenderBox?;
    if (disabledBox != null) {
      final disabledRect =
          disabledBox.localToGlobal(Offset.zero) & disabledBox.size;
      if (disabledRect.contains(position)) {
        modules.add(
          ModulesDragPreviewed(
            zone: state.previewZone,
            index: state.previewIndex,
            position: position,
          ),
        );
        return;
      }
    }
    final groups = moduleGroups(
      context.read<SettingsAppBloc>().settings,
      state.unavailable,
      exclude: dragging,
    );
    ModuleZone? zone;
    var bestDistance = double.infinity;
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
    modules.add(
      ModulesDragPreviewed(zone: zone, index: index, position: position),
    );
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

  /// The zone's rows without the module currently in flight; the dragged row
  /// stays in the tree (collapsed) so the drag survives rebuilds, but an
  /// emptied zone still shows its drop hint.
  List<String> _visibleModules(List<String> modules, String? dragging) {
    if (dragging == null) {
      return modules;
    }
    return [
      for (final module in modules)
        if (module != dragging) module,
    ];
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
          // Keep the label's space when highlighted so the card never
          // resizes under the pointer; hovering just fades the text out.
          child: Opacity(
            opacity: active ? 0 : 1,
            child: Text(
              label,
              style: ShellText.systemBarCaption.copyWith(
                color: ShellMediaColors.lightForegroundSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watch<SettingsAppBloc>().settings;
    final modules = context.watch<ModulesBloc>();
    final state = modules.state;
    // The dragged row stays in the tree (its Draggable collapses it to a
    // zero-height slot) so the drag survives the preview rebuilds.
    final groups = moduleGroups(settings, state.unavailable);
    final unavailableModules = <String>{
      for (final unavailable in state.unavailable) unavailable.module,
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
        options: hasOptions
            ? ModuleOptionsPanel(
                module: module,
                workspaceNames: widget.workspaceNames,
              )
            : null,
        optionsExpanded: state.expanded.contains(module),
        onToggleOptions: hasOptions
            ? () => modules.add(ModulesOptionsToggled(module))
            : null,
        feedbackWidth: feedbackWidth,
        onDragStart: () =>
            modules.add(ModulesDragStarted(module: module, zone: zone)),
        onDragUpdate: (position) => _updateDrag(modules, position),
        onDragEnd: (accepted) {
          final pointer = modules.state.lastPointer;
          modules.add(
            ModulesDragEnded(
              accepted: accepted,
              withinSegment: pointer != null && _withinSegment(pointer),
            ),
          );
        },
        onToggle: (value) =>
            modules.add(ModulesToggled(module: module, enabled: value)),
        onKeyboardMove: draggableOut
            ? (_) {}
            : (delta) => modules.add(
                ModulesMovedWithinZone(module: module, delta: delta),
              ),
        onKeyboardZone: draggableOut
            ? (_) {}
            : (delta) =>
                  modules.add(ModulesMovedZoneBy(module: module, delta: delta)),
      );
    }

    List<Widget> segmentChildren(
      ModuleZone zone,
      List<String> modules,
      double feedbackWidth,
    ) {
      final dragging = state.dragging;
      final showPreview = dragging != null && state.previewZone == zone;
      // The preview index counts the rows without the lifted one, while the
      // rendered list still holds its collapsed slot; step past that slot
      // so the gap lands under the half of the row the pointer is on.
      var previewAt = state.previewIndex.clamp(0, modules.length);
      if (showPreview) {
        final sourceIndex = modules.indexOf(dragging);
        if (sourceIndex >= 0 && sourceIndex < previewAt) {
          previewAt += 1;
        }
      }
      return <Widget>[
        for (var index = 0; index < modules.length; index++)
          _RowSlot(
            key: _rowKey(modules[index]),
            lineAbove: showPreview && index == previewAt,
            lineBelow:
                showPreview &&
                previewAt == modules.length &&
                index == modules.length - 1,
            child: moduleRow(
              modules[index],
              zone: zone,
              reorderable: true,
              feedbackWidth: feedbackWidth,
            ),
          ),
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
                  onPressed: () => modules.add(const ModulesReset()),
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
                  border:
                      state.dragging != null && state.previewZone == entry.key
                      ? Border.all(
                          color: ShellBrandColors.defaultAccent,
                          width: 1.5,
                        )
                      : null,
                ),
                child: SettingsCard(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      ...segmentChildren(
                        entry.key,
                        entry.value,
                        constraints.maxWidth,
                      ),
                      // The dragged row stays in the tree (collapsed) so the
                      // drag survives; an emptied zone keeps its hint for the
                      // whole drag so the layout never toggles under the
                      // pointer.
                      if (_visibleModules(entry.value, state.dragging).isEmpty)
                        _dropHere(
                          label: l10n.settingsModulesEmptyZone,
                          active: state.previewZone == entry.key,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (state.unavailable.isNotEmpty) ...[
              SettingsHeading(
                key: const ValueKey<String>('module-zone-unavailable'),
                title: l10n.settingsModulesUnavailable,
              ),
              const SizedBox(height: 10),
              SettingsCard(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    for (final unavailable in state.unavailable)
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
                  modules.add(ModulesDroppedOnDisabled(details.data)),
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
                  key: _disabledKey,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  // Rows stay in the tree (the dragged one collapses) so the
                  // drag survives; an emptied section keeps its hint. The
                  // hint never changes size, so hovering cannot toggle it.
                  child: Column(
                    children: [
                      for (final module in disabled)
                        moduleRow(
                          module,
                          zone: settings.zoneFor(module),
                          reorderable: false,
                          draggableOut: true,
                          feedbackWidth: constraints.maxWidth,
                        ),
                      if (_visibleModules(disabled, state.dragging).isEmpty)
                        _dropHere(
                          label: l10n.settingsModulesEmptyZone,
                          active: candidates.isNotEmpty,
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

/// Paints the insertion line over a row's top or bottom edge without
/// changing the layout, so dragging never shifts the rows under the pointer.
class _RowSlot extends StatelessWidget {
  const _RowSlot({
    required this.child,
    required this.lineAbove,
    required this.lineBelow,
    super.key,
  });

  final Widget child;
  final bool lineAbove;
  final bool lineBelow;

  @override
  Widget build(BuildContext context) {
    // Always a Stack: the child must never be reparented mid-drag, or its
    // gesture state is disposed and the drag cancels.
    return Stack(
      children: [
        child,
        if (lineAbove)
          Positioned(left: 16, right: 16, top: 0, height: 3, child: _line()),
        if (lineBelow)
          Positioned(left: 16, right: 16, bottom: 0, height: 3, child: _line()),
      ],
    );
  }

  Widget _line() {
    return Container(
      key: const ValueKey<String>('module-drop-preview'),
      decoration: BoxDecoration(
        color: ShellBrandColors.defaultAccent,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
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
          SettingsToggle(
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
            SettingsToggle(label: label, enabled: true, onChanged: (_) {}),
          ],
        ),
      ),
    );
  }
}
