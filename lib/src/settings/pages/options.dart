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

/// Module options page: every typed option the bar decodes, edited as the
/// document the bar already owns.
class OptionsPage extends StatefulWidget {
  const OptionsPage({super.key});

  @override
  State<OptionsPage> createState() => _OptionsPageState();
}

class _OptionsPageState extends State<OptionsPage> {
  DebouncedSaver? _saver;

  @override
  void dispose() {
    _saver?.dispose();
    super.dispose();
  }

  DebouncedSaver _saverFor(SettingsAppController controller) =>
      _saver ??= DebouncedSaver(controller);

  void _apply(
    SettingsAppController controller,
    BarSettings Function(BarSettings) change,
  ) {
    _saverFor(controller).apply(change);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final settings = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(
          title: l10n.settingsOptionsTitle,
          caption: l10n.settingsOptionsCaption,
        ),
        const SizedBox(height: 20),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsHeading(title: l10n.settingsWorkspacesSection),
              const SizedBox(height: 14),
              _SliderRow(
                sliderKey: const ValueKey<String>('options-workspaces-count'),
                label: l10n.settingsWorkspacesCount,
                value: settings.workspaces.count.toDouble(),
                min: 2,
                max: 9,
                display: '${settings.workspaces.count}',
                resetKey: const ValueKey<String>('reset-workspaces-count'),
                resetLabel: l10n.settingsResetOption(
                  l10n.settingsWorkspacesCount,
                ),
                resetEnabled:
                    settings.workspaces.count != const WorkspaceOptions().count,
                onChanged: (value) => _apply(
                  controller,
                  (settings) => settings.copyWith(
                    workspaces: WorkspaceOptions(count: value.round()),
                  ),
                ),
                onReset: () => _apply(
                  controller,
                  (settings) =>
                      settings.copyWith(workspaces: const WorkspaceOptions()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsHeading(title: l10n.settingsClockSection),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsClockFormat,
                      style: ShellText.systemBarCaption.copyWith(
                        color: ShellMediaColors.lightForegroundSecondary,
                      ),
                    ),
                  ),
                  SettingsResetButton(
                    key: const ValueKey<String>('reset-clock-format'),
                    label: l10n.settingsResetOption(l10n.settingsClockFormat),
                    enabled: settings.clock.format != ClockFormat.locale,
                    onPressed: () => _apply(
                      controller,
                      (settings) =>
                          settings.copyWith(clock: const ClockOptions()),
                    ),
                  ),
                ],
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
                        (settings) => settings.copyWith(
                          clock: ClockOptions(format: format),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsHeading(title: l10n.settingsCpuSection),
              const SizedBox(height: 14),
              _SliderRow(
                sliderKey: const ValueKey<String>('options-cpu-warn'),
                label: l10n.settingsWarnLabel,
                value: settings.cpu.warn,
                min: 0,
                max: 1,
                display: '${(settings.cpu.warn * 100).round()}%',
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
                resetKey: const ValueKey<String>('reset-cpu-warn'),
                resetLabel: l10n.settingsResetOption(l10n.settingsWarnLabel),
                resetEnabled: settings.cpu.warn != const CpuOptions().warn,
                onReset: () => _apply(controller, (settings) {
                  final warn = math
                      .min(
                        const CpuOptions().warn,
                        settings.cpu.critical - 0.01,
                      )
                      .clamp(0.0, 0.99);
                  return settings.copyWith(
                    cpu: CpuOptions(
                      warn: warn,
                      critical: settings.cpu.critical,
                    ),
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
                resetKey: const ValueKey<String>('reset-cpu-critical'),
                resetLabel: l10n.settingsResetOption(
                  l10n.settingsCriticalLabel,
                ),
                resetEnabled:
                    settings.cpu.critical != const CpuOptions().critical,
                onReset: () => _apply(controller, (settings) {
                  final critical = math
                      .max(
                        const CpuOptions().critical,
                        settings.cpu.warn + 0.01,
                      )
                      .clamp(0.01, 1.0);
                  return settings.copyWith(
                    cpu: CpuOptions(
                      warn: settings.cpu.warn,
                      critical: critical,
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsHeading(title: l10n.settingsBatterySection),
              const SizedBox(height: 14),
              _SliderRow(
                sliderKey: const ValueKey<String>('options-battery-warn'),
                label: l10n.settingsWarnLabel,
                value: settings.battery.warn.toDouble(),
                min: 1,
                max: 100,
                display: '${settings.battery.warn}%',
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
                resetKey: const ValueKey<String>('reset-battery-warn'),
                resetLabel: l10n.settingsResetOption(l10n.settingsWarnLabel),
                resetEnabled:
                    settings.battery.warn != const BatteryOptions().warn,
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
                resetKey: const ValueKey<String>('reset-battery-critical'),
                resetLabel: l10n.settingsResetOption(
                  l10n.settingsCriticalLabel,
                ),
                resetEnabled:
                    settings.battery.critical !=
                    const BatteryOptions().critical,
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
        ),
        const SizedBox(height: 16),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsHeading(title: l10n.settingsMeterSection),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsMeterCaption,
                      style: ShellText.systemBarCaption.copyWith(
                        color: ShellMediaColors.lightForegroundSecondary,
                      ),
                    ),
                  ),
                  SettingsResetButton(
                    key: const ValueKey<String>('reset-meter-caption'),
                    label: l10n.settingsResetOption(l10n.settingsMeterCaption),
                    enabled:
                        settings.meter.captionSource !=
                        const MeterOptions().captionSource,
                    onPressed: () => _apply(
                      controller,
                      (settings) =>
                          settings.copyWith(meter: const MeterOptions()),
                    ),
                  ),
                ],
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
        ),
      ],
    );
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
