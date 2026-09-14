import 'dart:math' as math;

import 'package:flutter/widgets.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final settings = controller.settings;
    return switch (widget.module) {
      'workspaces' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.availableOutputs.isNotEmpty) ...[
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
