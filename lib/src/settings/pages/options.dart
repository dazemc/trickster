import 'package:flutter/widgets.dart';
import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/controller.dart';
import 'package:trickster/src/settings/saver.dart';
import 'package:trickster/src/settings/scope.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/theme/motion.dart';
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
              _ToggleRow(
                label: l10n.settingsWorkspacesShowEmpty,
                value: settings.workspaces.showEmpty,
                onChanged: (value) => _apply(
                  controller,
                  (settings) => settings.copyWith(
                    workspaces: WorkspaceOptions(
                      showEmpty: value,
                      max: settings.workspaces.max,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SliderRow(
                sliderKey: const ValueKey<String>('options-workspaces-max'),
                label: l10n.settingsWorkspacesMax,
                value: settings.workspaces.max.toDouble(),
                min: 1,
                max: 64,
                display: '${settings.workspaces.max}',
                onChanged: (value) => _apply(
                  controller,
                  (settings) => settings.copyWith(
                    workspaces: WorkspaceOptions(
                      showEmpty: settings.workspaces.showEmpty,
                      max: value.round(),
                    ),
                  ),
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
              Text(
                l10n.settingsClockFormat,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellMediaColors.lightForegroundSecondary,
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
              Text(
                l10n.settingsMeterCaption,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellMediaColors.lightForegroundSecondary,
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

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      onTap: () => onChanged(!value),
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: Row(
              children: [
                Expanded(child: Text(label, style: ShellText.systemBarValue)),
                AnimatedContainer(
                  duration: Motion.pill,
                  curve: Motion.standard,
                  width: 44,
                  height: 24,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    color: value
                        ? ShellBrandColors.defaultAccent
                        : SettingsColors.surfaceHigh,
                    border: Border.all(color: SettingsColors.outline),
                  ),
                  child: AnimatedAlign(
                    duration: Motion.pill,
                    curve: Motion.standard,
                    alignment: value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value
                            ? SettingsColors.background
                            : ShellMediaColors.lightForegroundSecondary,
                      ),
                      child: const SizedBox.square(dimension: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

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
      ],
    );
  }
}
