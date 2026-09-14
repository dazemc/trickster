import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/controller.dart';
import 'package:trickster/src/settings/saver.dart';
import 'package:trickster/src/settings/scope.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/theme/tokens.dart';

/// Whether [module] owns any of the typed options the bar decodes.
bool moduleHasOptions(String module) {
  return switch (module) {
    'workspaces' || 'clock' || 'cpu' || 'gpu' || 'battery' => true,
    _ => false,
  };
}

/// The typed options for one module, revealed by its row's gear. The page
/// used to split these into a separate tab; they live under their module
/// now.
class ModuleOptionsPanel extends StatefulWidget {
  const ModuleOptionsPanel({required this.module, super.key});

  final String module;

  @override
  State<ModuleOptionsPanel> createState() => _ModuleOptionsPanelState();
}

class _ModuleOptionsPanelState extends State<ModuleOptionsPanel> {
  DebouncedSaver? _saver;

  @override
  void dispose() {
    _saver?.dispose();
    super.dispose();
  }

  void _apply(
    SettingsAppController controller,
    BarSettings Function(BarSettings) change,
  ) {
    (_saver ??= DebouncedSaver(controller)).apply(change);
  }

  /// Moves [display] to [index] in the chain and persists the whole order, so
  /// the displays the host appended keep an explicit position.
  void _reorderDisplay(
    SettingsAppController controller,
    List<String> chain,
    String display,
    int index,
  ) {
    final order = List<String>.of(chain)..remove(display);
    order.insert(index.clamp(0, order.length), display);
    _apply(
      controller,
      (settings) => settings.copyWith(
        workspaces: WorkspaceOptions(
          count: settings.workspaces.count,
          perOutput: settings.workspaces.perOutput,
          displayOrder: order,
        ),
      ),
    );
  }

  Widget _displayOrderRow(
    SettingsAppController controller,
    BarSettings settings,
    List<String> chain,
    int index,
  ) {
    final l10n = context.l10n;
    final display = chain[index];
    final range = settings.workspaces.rangeFor(display, chain);
    return _DisplayOrderRow(
      key: ValueKey<String>('display-order-$display'),
      display: display,
      main: index == 0,
      range: range == null ? '' : '${range.$1}-${range.$2}',
      dragLabel: l10n.settingsModuleDrag,
      mainLabel: l10n.settingsWorkspacesMain,
      setMainLabel: l10n.settingsWorkspacesSetMain,
      onSetMain: () => _reorderDisplay(controller, chain, display, 0),
      onMoveHere: (dragged) =>
          _reorderDisplay(controller, chain, dragged, index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final settings = controller.settings;
    final connected = <String>[
      for (final output in controller.availableOutputs) output.name,
    ];
    final chain = settings.workspaces.chainFor(connected);
    return switch (widget.module) {
      'workspaces' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chain.isNotEmpty) ...[
            Text(
              l10n.settingsWorkspacesDisplayOrder,
              style: ShellText.systemBarCaption.copyWith(
                color: ShellMediaColors.lightForegroundSecondary,
              ),
            ),
            const SizedBox(height: 10),
            SettingsCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (var index = 0; index < chain.length; index++)
                    _displayOrderRow(controller, settings, chain, index),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsWorkspacesPerDisplay,
              style: ShellText.systemBarCaption.copyWith(
                color: ShellMediaColors.lightForegroundSecondary,
              ),
            ),
            const SizedBox(height: 10),
            for (final output in controller.availableOutputs) ...[
              _SliderRow(
                sliderKey: ValueKey<String>(
                  'options-workspaces-count-${output.name}',
                ),
                label: output.name,
                value: settings.workspaces.countFor(output.name).toDouble(),
                min: 2,
                max: 9,
                display: '${settings.workspaces.countFor(output.name)}',
                resetKey: ValueKey<String>(
                  'reset-workspaces-count-${output.name}',
                ),
                resetLabel: l10n.settingsResetOption(output.name),
                resetEnabled: settings.workspaces.perOutput.containsKey(
                  output.name,
                ),
                onChanged: (value) => _apply(controller, (settings) {
                  final perOutput = Map<String, int>.of(
                    settings.workspaces.perOutput,
                  );
                  perOutput[output.name] = value.round();
                  return settings.copyWith(
                    workspaces: WorkspaceOptions(
                      count: settings.workspaces.count,
                      perOutput: perOutput,
                      displayOrder: settings.workspaces.displayOrder,
                    ),
                  );
                }),
                onReset: () => _apply(controller, (settings) {
                  final perOutput = Map<String, int>.of(
                    settings.workspaces.perOutput,
                  )..remove(output.name);
                  return settings.copyWith(
                    workspaces: WorkspaceOptions(
                      count: settings.workspaces.count,
                      perOutput: perOutput,
                      displayOrder: settings.workspaces.displayOrder,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
      'clock' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChoiceHeader(
            label: l10n.settingsClockFormat,
            resetKey: const ValueKey<String>('reset-clock-format'),
            resetLabel: l10n.settingsResetOption(l10n.settingsClockFormat),
            resetEnabled: settings.clock.format != ClockFormat.locale,
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(clock: const ClockOptions()),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in ClockFormat.values)
                SettingsChoiceChip(
                  key: ValueKey<String>('clock-format-${format.wire}'),
                  label: _clockFormatLabel(l10n, format),
                  selected: settings.clock.format == format,
                  onPressed: () => _apply(
                    controller,
                    (settings) =>
                        settings.copyWith(clock: ClockOptions(format: format)),
                  ),
                ),
            ],
          ),
        ],
      ),
      'cpu' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SliderRow(
            sliderKey: const ValueKey<String>('options-cpu-warn'),
            label: l10n.settingsWarnLabel,
            value: settings.cpu.warn,
            min: 0,
            max: 1,
            display: '${(settings.cpu.warn * 100).round()}%',
            resetKey: const ValueKey<String>('reset-cpu-warn'),
            resetLabel: l10n.settingsResetOption(l10n.settingsWarnLabel),
            resetEnabled: settings.cpu.warn != const CpuOptions().warn,
            onChanged: (value) {
              final warn = value;
              _apply(controller, (settings) {
                final critical = settings.cpu.critical <= warn
                    ? (warn + 0.01).clamp(0.01, 1.0)
                    : settings.cpu.critical;
                return settings.copyWith(
                  cpu: CpuOptions(warn: warn, critical: critical),
                );
              });
            },
            onReset: () => _apply(controller, (settings) {
              final warn = math
                  .min(const CpuOptions().warn, settings.cpu.critical - 0.01)
                  .clamp(0.0, 0.99);
              return settings.copyWith(
                cpu: CpuOptions(warn: warn, critical: settings.cpu.critical),
              );
            }),
          ),
          const SizedBox(height: 10),
          _SliderRow(
            sliderKey: const ValueKey<String>('options-cpu-critical'),
            label: l10n.settingsCriticalLabel,
            value: settings.cpu.critical,
            min: 0,
            max: 1,
            display: '${(settings.cpu.critical * 100).round()}%',
            resetKey: const ValueKey<String>('reset-cpu-critical'),
            resetLabel: l10n.settingsResetOption(l10n.settingsCriticalLabel),
            resetEnabled: settings.cpu.critical != const CpuOptions().critical,
            onChanged: (value) {
              final critical = value;
              _apply(controller, (settings) {
                final warn = settings.cpu.warn >= critical
                    ? (critical - 0.01).clamp(0.0, 0.99)
                    : settings.cpu.warn;
                return settings.copyWith(
                  cpu: CpuOptions(warn: warn, critical: critical),
                );
              });
            },
            onReset: () => _apply(controller, (settings) {
              final critical = math
                  .max(const CpuOptions().critical, settings.cpu.warn + 0.01)
                  .clamp(0.01, 1.0);
              return settings.copyWith(
                cpu: CpuOptions(warn: settings.cpu.warn, critical: critical),
              );
            }),
          ),
        ],
      ),
      'battery' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SliderRow(
            sliderKey: const ValueKey<String>('options-battery-warn'),
            label: l10n.settingsWarnLabel,
            value: settings.battery.warn.toDouble(),
            min: 1,
            max: 100,
            display: '${settings.battery.warn}%',
            resetKey: const ValueKey<String>('reset-battery-warn'),
            resetLabel: l10n.settingsResetOption(l10n.settingsWarnLabel),
            resetEnabled: settings.battery.warn != const BatteryOptions().warn,
            onChanged: (value) {
              final warn = value.round();
              _apply(controller, (settings) {
                final critical = settings.battery.critical >= warn
                    ? warn - 1
                    : settings.battery.critical;
                return settings.copyWith(
                  battery: BatteryOptions(warn: warn, critical: critical),
                );
              });
            },
            onReset: () => _apply(controller, (settings) {
              final warn = math
                  .max(
                    const BatteryOptions().warn,
                    settings.battery.critical + 1,
                  )
                  .clamp(1, 99);
              return settings.copyWith(
                battery: BatteryOptions(
                  warn: warn,
                  critical: settings.battery.critical,
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          _SliderRow(
            sliderKey: const ValueKey<String>('options-battery-critical'),
            label: l10n.settingsCriticalLabel,
            value: settings.battery.critical.toDouble(),
            min: 1,
            max: 100,
            display: '${settings.battery.critical}%',
            resetKey: const ValueKey<String>('reset-battery-critical'),
            resetLabel: l10n.settingsResetOption(l10n.settingsCriticalLabel),
            resetEnabled:
                settings.battery.critical != const BatteryOptions().critical,
            onChanged: (value) {
              final critical = value.round();
              _apply(controller, (settings) {
                final warn = settings.battery.warn <= critical
                    ? critical + 1
                    : settings.battery.warn;
                return settings.copyWith(
                  battery: BatteryOptions(warn: warn, critical: critical),
                );
              });
            },
            onReset: () => _apply(controller, (settings) {
              final critical = math
                  .min(
                    const BatteryOptions().critical,
                    settings.battery.warn - 1,
                  )
                  .clamp(1, 99);
              return settings.copyWith(
                battery: BatteryOptions(
                  warn: settings.battery.warn,
                  critical: critical,
                ),
              );
            }),
          ),
        ],
      ),
      'gpu' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChoiceHeader(
            label: l10n.settingsMeterCaption,
            resetKey: const ValueKey<String>('reset-meter-caption'),
            resetLabel: l10n.settingsResetOption(l10n.settingsMeterCaption),
            resetEnabled:
                settings.meter.captionSource != MeterCaptionSource.generic,
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(meter: const MeterOptions()),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final source in MeterCaptionSource.values)
                SettingsChoiceChip(
                  key: ValueKey<String>('meter-caption-${source.name}'),
                  label: _captionLabel(l10n, source),
                  selected: settings.meter.captionSource == source,
                  onPressed: () => _apply(
                    controller,
                    (settings) => settings.copyWith(
                      meter: MeterOptions(captionSource: source),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

String _clockFormatLabel(AppLocalizations l10n, ClockFormat format) {
  return switch (format) {
    ClockFormat.locale => l10n.settingsClockFormatLocale,
    ClockFormat.hour24 => l10n.settingsClockFormat24,
    ClockFormat.hour12 => l10n.settingsClockFormat12,
  };
}

String _captionLabel(AppLocalizations l10n, MeterCaptionSource source) {
  return switch (source) {
    MeterCaptionSource.generic => l10n.settingsMeterCaptionGeneric,
    MeterCaptionSource.device => l10n.settingsMeterCaptionDevice,
  };
}

/// A caption row with the option's reset arrow at the trailing edge.
class _ChoiceHeader extends StatelessWidget {
  const _ChoiceHeader({
    required this.label,
    required this.resetKey,
    required this.resetLabel,
    required this.resetEnabled,
    required this.onReset,
  });

  final String label;
  final Key resetKey;
  final String resetLabel;
  final bool resetEnabled;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary,
            ),
          ),
        ),
        SettingsResetButton(
          key: resetKey,
          label: resetLabel,
          enabled: resetEnabled,
          onPressed: onReset,
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.sliderKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.resetKey,
    required this.resetLabel,
    required this.resetEnabled,
    required this.onChanged,
    required this.onReset,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final Key resetKey;
  final String resetLabel;
  final bool resetEnabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary,
            ),
          ),
        ),
        Expanded(
          child: SettingsSlider(
            key: sliderKey,
            value: value.clamp(min, max),
            min: min,
            max: max,
            label: label,
            onChanged: onChanged,
            onChangeEnd: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: ShellText.systemBarValue,
          ),
        ),
        const SizedBox(width: 4),
        SettingsResetButton(
          key: resetKey,
          label: resetLabel,
          enabled: resetEnabled,
          onPressed: onReset,
        ),
      ],
    );
  }
}

/// One display in the chain order: grip, name, main badge (or set-as-main),
/// and the absolute workspace range it owns.
class _DisplayOrderRow extends StatelessWidget {
  const _DisplayOrderRow({
    required this.display,
    required this.main,
    required this.range,
    required this.dragLabel,
    required this.mainLabel,
    required this.setMainLabel,
    required this.onSetMain,
    required this.onMoveHere,
    super.key,
  });

  final String display;
  final bool main;
  final String range;
  final String dragLabel;
  final String mainLabel;
  final String setMainLabel;
  final VoidCallback onSetMain;
  final ValueChanged<String> onMoveHere;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != display,
      onAcceptWithDetails: (details) => onMoveHere(details.data),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: active
                  ? SettingsColors.surfaceHigh
                  : SettingsColors.surface,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              border: Border.all(
                color: active
                    ? ShellBrandColors.defaultAccent
                    : SettingsColors.outline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Draggable<String>(
                    key: ValueKey<String>('display-drag-$display'),
                    data: display,
                    maxSimultaneousDrags: 1,
                    feedback: _DisplayDragFeedback(label: display),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: _DisplayGrip(label: dragLabel),
                    ),
                    child: _DisplayGrip(label: dragLabel),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(display, style: ShellText.systemBarValue),
                  ),
                  if (main)
                    _MainBadge(
                      key: ValueKey<String>('display-main-$display'),
                      label: mainLabel,
                    )
                  else
                    SettingsChoiceChip(
                      key: ValueKey<String>('display-set-main-$display'),
                      label: setMainLabel,
                      selected: false,
                      onPressed: onSetMain,
                    ),
                  const SizedBox(width: 10),
                  Text(
                    range,
                    style: ShellText.systemBarCaption.copyWith(
                      color: ShellMediaColors.lightForegroundSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The drag handle that lifts one display row.
class _DisplayGrip extends StatelessWidget {
  const _DisplayGrip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: Icon(
                LucideIcons.gripVertical,
                size: 15,
                color: ShellMediaColors.lightForegroundSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The lifted row under the pointer.
class _DisplayDragFeedback extends StatelessWidget {
  const _DisplayDragFeedback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SettingsColors.surfaceHigh,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: SettingsColors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(label, style: ShellText.systemBarValue),
      ),
    );
  }
}

/// The badge carried by the first display of the chain.
class _MainBadge extends StatelessWidget {
  const _MainBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShellBrandColors.defaultAccent.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          style: ShellText.systemBarCaption.copyWith(
            color: ShellBrandColors.defaultAccent,
          ),
        ),
      ),
    );
  }
}
