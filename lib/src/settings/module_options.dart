import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show
        Color,
        Divider,
        InputBorder,
        InputDecoration,
        Material,
        MaterialType,
        MenuAnchor,
        MenuItemButton,
        MenuStyle,
        TextField,
        WidgetStatePropertyAll;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/color_format.dart';
import 'package:trickster/src/settings/color_wheel.dart';
import 'package:trickster/src/settings/saver.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/settings/workspace_names.dart';
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
  const ModuleOptionsPanel({
    required this.module,
    this.workspaceNames,
    super.key,
  });

  /// Source of live workspace names for the pip mapping editor; null asks
  /// the running bar over the control socket.
  final Future<List<String>> Function()? workspaceNames;

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
    SettingsAppBloc controller,
    BarSettings Function(BarSettings) change,
  ) {
    (_saver ??= DebouncedSaver(controller)).apply(change);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.watch<SettingsAppBloc>();
    final settings = controller.settings;
    return switch (widget.module) {
      'workspaces' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChoiceHeader(
            label: l10n.settingsWorkspacesPipStyle,
            resetKey: const ValueKey<String>('reset-workspaces-pip-style'),
            resetLabel: l10n.settingsResetOption(
              l10n.settingsWorkspacesPipStyle,
            ),
            resetEnabled: settings.workspaces.pipStyle != PipStyle.number,
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(
                workspaces: WorkspaceOptions(
                  imageSource: settings.workspaces.imageSource,
                  imageByWorkspace: settings.workspaces.imageByWorkspace,
                  tintSvg: settings.workspaces.tintSvg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in PipStyle.values)
                SettingsChoiceChip(
                  key: ValueKey<String>('workspaces-pip-${style.wire}'),
                  label: _pipStyleLabel(l10n, style),
                  selected: settings.workspaces.pipStyle == style,
                  onPressed: () => _apply(
                    controller,
                    (settings) => settings.copyWith(
                      workspaces: WorkspaceOptions(
                        pipStyle: style,
                        imageSource: settings.workspaces.imageSource,
                        imageByWorkspace: settings.workspaces.imageByWorkspace,
                        tintSvg: settings.workspaces.tintSvg,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (settings.workspaces.pipStyle == PipStyle.image) ...[
            const SizedBox(height: 14),
            _ImageRow(
              value: settings.workspaces.imageSource,
              rowKey: const ValueKey<String>('workspaces-image-row'),
              browseKey: const ValueKey<String>('workspaces-image-browse'),
              clearKey: const ValueKey<String>('workspaces-image-clear'),
              label: l10n.settingsWorkspacesImage,
              emptyLabel: l10n.settingsWorkspacesImageNone,
              browseLabel: l10n.settingsWorkspacesBrowse,
              clearLabel: l10n.settingsWorkspacesImageClear,
              onBrowse: () async {
                final path = await LayerShell().pickImageFile();
                if (!mounted || path == null || path.isEmpty) {
                  return;
                }
                _apply(
                  controller,
                  (settings) => settings.copyWith(
                    workspaces: WorkspaceOptions(
                      pipStyle: PipStyle.image,
                      imageSource: path,
                      imageByWorkspace: settings.workspaces.imageByWorkspace,
                      tintSvg: settings.workspaces.tintSvg,
                    ),
                  ),
                );
              },
              onClear: () => _apply(
                controller,
                (settings) => settings.copyWith(
                  workspaces: WorkspaceOptions(
                    pipStyle: PipStyle.image,
                    imageByWorkspace: settings.workspaces.imageByWorkspace,
                    tintSvg: settings.workspaces.tintSvg,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _WorkspacePipMap(
              entries: settings.workspaces.imageByWorkspace,
              label: l10n.settingsWorkspacesPerWorkspace,
              nameHint: l10n.settingsWorkspacesNameHint,
              addLabel: l10n.settingsWorkspacesAddMapping,
              chooseLabel: l10n.settingsWorkspacesChoose,
              customLabel: l10n.settingsWorkspacesCustom,
              browseLabel: l10n.settingsWorkspacesBrowse,
              removeLabel: l10n.settingsWorkspacesRemoveMapping,
              pick: () => LayerShell().pickImageFile(),
              fetchNames: widget.workspaceNames,
              onAdd: (name, path) => _apply(
                controller,
                (settings) => settings.copyWith(
                  workspaces: WorkspaceOptions(
                    pipStyle: PipStyle.image,
                    imageSource: settings.workspaces.imageSource,
                    imageByWorkspace: {
                      ...settings.workspaces.imageByWorkspace,
                      name: path,
                    },
                    tintSvg: settings.workspaces.tintSvg,
                  ),
                ),
              ),
              onRemove: (name) => _apply(controller, (settings) {
                final mapping = Map<String, String>.of(
                  settings.workspaces.imageByWorkspace,
                )..remove(name);
                return settings.copyWith(
                  workspaces: WorkspaceOptions(
                    pipStyle: PipStyle.image,
                    imageSource: settings.workspaces.imageSource,
                    imageByWorkspace: mapping,
                    tintSvg: settings.workspaces.tintSvg,
                  ),
                );
              }),
            ),
            if (_hasSvgArtwork(settings.workspaces)) ...[
              const SizedBox(height: 14),
              SettingsToggleRow(
                toggleKey: const ValueKey<String>('workspaces-tint-svg'),
                label: l10n.settingsWorkspacesTintSvg,
                value: settings.workspaces.tintSvg,
                resetKey: const ValueKey<String>('reset-workspaces-tint-svg'),
                resetLabel: l10n.settingsResetOption(
                  l10n.settingsWorkspacesTintSvg,
                ),
                resetEnabled: settings.workspaces.tintSvg,
                onChanged: (value) => _apply(
                  controller,
                  (settings) => settings.copyWith(
                    workspaces: WorkspaceOptions(
                      pipStyle: PipStyle.image,
                      imageSource: settings.workspaces.imageSource,
                      imageByWorkspace: settings.workspaces.imageByWorkspace,
                      tintSvg: value,
                    ),
                  ),
                ),
                onReset: () => _apply(
                  controller,
                  (settings) => settings.copyWith(
                    workspaces: WorkspaceOptions(
                      pipStyle: PipStyle.image,
                      imageSource: settings.workspaces.imageSource,
                      imageByWorkspace: settings.workspaces.imageByWorkspace,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.settingsWorkspacesTintSvgHint,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellMediaColors.lightForegroundSecondary.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
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
              (settings) => settings.copyWith(
                clock: settings.clock.copyWith(format: ClockFormat.locale),
              ),
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
                      clock: settings.clock.copyWith(format: format),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const SizedBox(height: 18),
          SettingsToggleRow(
            toggleKey: const ValueKey<String>('clock-show-seconds'),
            label: l10n.settingsClockShowSeconds,
            value: settings.clock.showSeconds,
            resetKey: const ValueKey<String>('reset-clock-show-seconds'),
            resetLabel: l10n.settingsResetOption(l10n.settingsClockShowSeconds),
            resetEnabled: settings.clock.showSeconds,
            onChanged: (value) => _apply(
              controller,
              (settings) => settings.copyWith(
                clock: settings.clock.copyWith(showSeconds: value),
              ),
            ),
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(
                clock: settings.clock.copyWith(showSeconds: false),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _ChoiceHeader(
            label: l10n.settingsClockDateStyle,
            resetKey: const ValueKey<String>('reset-clock-date-style'),
            resetLabel: l10n.settingsResetOption(l10n.settingsClockDateStyle),
            resetEnabled: settings.clock.dateStyle != ClockDateStyle.short,
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(
                clock: settings.clock.copyWith(dateStyle: ClockDateStyle.short),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in ClockDateStyle.values)
                SettingsChoiceChip(
                  key: ValueKey<String>('clock-date-style-${style.wire}'),
                  label: _dateStyleLabel(l10n, style),
                  selected: settings.clock.dateStyle == style,
                  onPressed: () => _apply(
                    controller,
                    (settings) => settings.copyWith(
                      clock: settings.clock.copyWith(dateStyle: style),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SettingsToggleRow(
            toggleKey: const ValueKey<String>('clock-show-date'),
            label: l10n.settingsClockShowDate,
            value: settings.clock.showDate,
            resetKey: const ValueKey<String>('reset-clock-show-date'),
            resetLabel: l10n.settingsResetOption(l10n.settingsClockShowDate),
            resetEnabled: !settings.clock.showDate,
            onChanged: (value) => _apply(
              controller,
              (settings) => settings.copyWith(
                clock: settings.clock.copyWith(showDate: value),
              ),
            ),
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(
                clock: settings.clock.copyWith(showDate: true),
              ),
            ),
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
                  cpu: settings.cpu.copyWith(warn: warn, critical: critical),
                );
              });
            },
            onReset: () => _apply(controller, (settings) {
              final warn = math
                  .min(const CpuOptions().warn, settings.cpu.critical - 0.01)
                  .clamp(0.0, 0.99);
              return settings.copyWith(cpu: settings.cpu.copyWith(warn: warn));
            }),
          ),
          const SizedBox(height: 8),
          _ColorRow(
            fieldKey: const ValueKey<String>('cpu-warn-color'),
            label: l10n.settingsWarnColor,
            color: settings.cpu.warnColor,
            fallback: ShellTelemetryColors.warning,
            onChanged: (color) => _apply(
              controller,
              (settings) => settings.copyWith(
                cpu: settings.cpu.copyWith(warnColor: color),
              ),
            ),
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(
                cpu: settings.cpu.copyWith(warnColor: null),
              ),
            ),
            resetKey: const ValueKey<String>('reset-cpu-warn-color'),
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
                  cpu: settings.cpu.copyWith(warn: warn, critical: critical),
                );
              });
            },
            onReset: () => _apply(controller, (settings) {
              final critical = math
                  .max(const CpuOptions().critical, settings.cpu.warn + 0.01)
                  .clamp(0.01, 1.0);
              return settings.copyWith(
                cpu: settings.cpu.copyWith(critical: critical),
              );
            }),
          ),
          const SizedBox(height: 8),
          _ColorRow(
            fieldKey: const ValueKey<String>('cpu-critical-color'),
            label: l10n.settingsCriticalColor,
            color: settings.cpu.criticalColor,
            fallback: ShellTelemetryColors.danger,
            onChanged: (color) => _apply(
              controller,
              (settings) => settings.copyWith(
                cpu: settings.cpu.copyWith(criticalColor: color),
              ),
            ),
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(
                cpu: settings.cpu.copyWith(criticalColor: null),
              ),
            ),
            resetKey: const ValueKey<String>('reset-cpu-critical-color'),
          ),
          ..._meterControls(
            l10n: l10n,
            controller: controller,
            prefix: 'cpu',
            captionSource: settings.cpu.captionSource,
            captionPrefix: settings.cpu.captionPrefix,
            sparkline: settings.cpu.sparkline,
            onCaption: (settings, source) => settings.copyWith(
              cpu: settings.cpu.copyWith(captionSource: source),
            ),
            onCaptionPrefix: (settings, value) => settings.copyWith(
              cpu: settings.cpu.copyWith(
                captionPrefix: value.trim().isEmpty ? null : value.trim(),
              ),
            ),
            onSparkline: (settings, value) =>
                settings.copyWith(cpu: settings.cpu.copyWith(sparkline: value)),
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
          _SliderRow(
            sliderKey: const ValueKey<String>('options-gpu-warn'),
            label: l10n.settingsWarnLabel,
            value: settings.gpu.warn,
            min: 0,
            max: 1,
            display: '${(settings.gpu.warn * 100).round()}%',
            resetKey: const ValueKey<String>('reset-gpu-warn'),
            resetLabel: l10n.settingsResetOption(l10n.settingsWarnLabel),
            resetEnabled: settings.gpu.warn != const GpuOptions().warn,
            onChanged: (value) {
              final warn = value;
              _apply(controller, (settings) {
                final critical = settings.gpu.critical <= warn
                    ? (warn + 0.01).clamp(0.01, 1.0)
                    : settings.gpu.critical;
                return settings.copyWith(
                  gpu: settings.gpu.copyWith(warn: warn, critical: critical),
                );
              });
            },
            onReset: () => _apply(controller, (settings) {
              final warn = math
                  .min(const GpuOptions().warn, settings.gpu.critical - 0.01)
                  .clamp(0.0, 0.99);
              return settings.copyWith(gpu: settings.gpu.copyWith(warn: warn));
            }),
          ),
          const SizedBox(height: 8),
          _ColorRow(
            fieldKey: const ValueKey<String>('gpu-warn-color'),
            label: l10n.settingsWarnColor,
            color: settings.gpu.warnColor,
            fallback: ShellTelemetryColors.warning,
            onChanged: (color) => _apply(
              controller,
              (settings) => settings.copyWith(
                gpu: settings.gpu.copyWith(warnColor: color),
              ),
            ),
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(
                gpu: settings.gpu.copyWith(warnColor: null),
              ),
            ),
            resetKey: const ValueKey<String>('reset-gpu-warn-color'),
          ),
          const SizedBox(height: 10),
          _SliderRow(
            sliderKey: const ValueKey<String>('options-gpu-critical'),
            label: l10n.settingsCriticalLabel,
            value: settings.gpu.critical,
            min: 0,
            max: 1,
            display: '${(settings.gpu.critical * 100).round()}%',
            resetKey: const ValueKey<String>('reset-gpu-critical'),
            resetLabel: l10n.settingsResetOption(l10n.settingsCriticalLabel),
            resetEnabled: settings.gpu.critical != const GpuOptions().critical,
            onChanged: (value) {
              final critical = value;
              _apply(controller, (settings) {
                final warn = settings.gpu.warn >= critical
                    ? (critical - 0.01).clamp(0.0, 0.99)
                    : settings.gpu.warn;
                return settings.copyWith(
                  gpu: settings.gpu.copyWith(warn: warn, critical: critical),
                );
              });
            },
            onReset: () => _apply(controller, (settings) {
              final critical = math
                  .max(const GpuOptions().critical, settings.gpu.warn + 0.01)
                  .clamp(0.01, 1.0);
              return settings.copyWith(
                gpu: settings.gpu.copyWith(critical: critical),
              );
            }),
          ),
          const SizedBox(height: 8),
          _ColorRow(
            fieldKey: const ValueKey<String>('gpu-critical-color'),
            label: l10n.settingsCriticalColor,
            color: settings.gpu.criticalColor,
            fallback: ShellTelemetryColors.danger,
            onChanged: (color) => _apply(
              controller,
              (settings) => settings.copyWith(
                gpu: settings.gpu.copyWith(criticalColor: color),
              ),
            ),
            onReset: () => _apply(
              controller,
              (settings) => settings.copyWith(
                gpu: settings.gpu.copyWith(criticalColor: null),
              ),
            ),
            resetKey: const ValueKey<String>('reset-gpu-critical-color'),
          ),
          ..._meterControls(
            l10n: l10n,
            controller: controller,
            prefix: 'gpu',
            captionSource: settings.gpu.captionSource,
            captionPrefix: settings.gpu.captionPrefix,
            sparkline: settings.gpu.sparkline,
            onCaption: (settings, source) => settings.copyWith(
              gpu: settings.gpu.copyWith(captionSource: source),
            ),
            onCaptionPrefix: (settings, value) => settings.copyWith(
              gpu: settings.gpu.copyWith(
                captionPrefix: value.trim().isEmpty ? null : value.trim(),
              ),
            ),
            onSparkline: (settings, value) =>
                settings.copyWith(gpu: settings.gpu.copyWith(sparkline: value)),
          ),
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }

  /// The caption and sparkline controls one meter panel owns; CPU and GPU
  /// both carry an identical set.
  List<Widget> _meterControls({
    required AppLocalizations l10n,
    required SettingsAppBloc controller,
    required String prefix,
    required MeterCaptionSource captionSource,
    required String? captionPrefix,
    required bool sparkline,
    required BarSettings Function(
      BarSettings settings,
      MeterCaptionSource source,
    )
    onCaption,
    required BarSettings Function(BarSettings settings, String value)
    onCaptionPrefix,
    required BarSettings Function(BarSettings settings, bool value) onSparkline,
  }) {
    return [
      const SizedBox(height: 18),
      _ChoiceHeader(
        label: l10n.settingsMeterCaption,
        resetKey: ValueKey<String>('reset-$prefix-meter-caption'),
        resetLabel: l10n.settingsResetOption(l10n.settingsMeterCaption),
        resetEnabled: captionSource != MeterCaptionSource.generic,
        onReset: () => _apply(
          controller,
          (settings) => onCaption(settings, MeterCaptionSource.generic),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final source in MeterCaptionSource.values)
            SettingsChoiceChip(
              key: ValueKey<String>('$prefix-meter-caption-${source.name}'),
              label: _captionLabel(l10n, source),
              selected: captionSource == source,
              onPressed: () =>
                  _apply(controller, (settings) => onCaption(settings, source)),
            ),
        ],
      ),
      if (captionSource == MeterCaptionSource.custom) ...[
        const SizedBox(height: 12),
        _OptionTextField(
          fieldKey: ValueKey<String>('$prefix-meter-prefix'),
          label: l10n.settingsMeterPrefix,
          hint: l10n.settingsMeterPrefixHint,
          value: captionPrefix ?? '',
          onChanged: (value) => _apply(
            controller,
            (settings) => onCaptionPrefix(settings, value),
          ),
        ),
      ],
      const SizedBox(height: 18),
      SettingsToggleRow(
        toggleKey: ValueKey<String>('$prefix-meter-sparkline'),
        label: l10n.settingsMeterSparkline,
        value: sparkline,
        resetKey: ValueKey<String>('reset-$prefix-meter-sparkline'),
        resetLabel: l10n.settingsResetOption(l10n.settingsMeterSparkline),
        resetEnabled: !sparkline,
        onChanged: (value) =>
            _apply(controller, (settings) => onSparkline(settings, value)),
        onReset: () =>
            _apply(controller, (settings) => onSparkline(settings, true)),
      ),
    ];
  }
}

/// Whether any chosen artwork file compiles through the vector pipeline, so
/// the recolor option is worth showing.
bool _hasSvgArtwork(WorkspaceOptions workspaces) {
  final shared = workspaces.imageSource?.toLowerCase();
  return (shared?.endsWith('.svg') ?? false) ||
      workspaces.imageByWorkspace.values.any(
        (path) => path.toLowerCase().endsWith('.svg'),
      );
}

String _dateStyleLabel(AppLocalizations l10n, ClockDateStyle style) {
  return switch (style) {
    ClockDateStyle.short => l10n.settingsClockDateShort,
    ClockDateStyle.long => l10n.settingsClockDateLong,
    ClockDateStyle.weekday => l10n.settingsClockDateWeekday,
  };
}

String _pipStyleLabel(AppLocalizations l10n, PipStyle style) {
  return switch (style) {
    PipStyle.number => l10n.settingsWorkspacesPipNumber,
    PipStyle.dot => l10n.settingsWorkspacesPipDot,
    PipStyle.roman => l10n.settingsWorkspacesPipRoman,
    PipStyle.image => l10n.settingsWorkspacesPipImage,
  };
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
    MeterCaptionSource.custom => l10n.settingsMeterCaptionCustom,
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

/// One threshold tint, picked on the same wheel as the accent.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.fieldKey,
    required this.label,
    required this.color,
    required this.fallback,
    required this.resetKey,
    required this.onChanged,
    required this.onReset,
  });

  final Key fieldKey;
  final String label;

  /// The stored tint; null means the shell default ([fallback]).
  final Color? color;
  final Color fallback;
  final Key resetKey;
  final ValueChanged<Color> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final active = color ?? fallback;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox.square(
          dimension: 88,
          child: HsvColorWheel(
            key: fieldKey,
            color: active,
            semanticsLabel: label,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 18),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: ShellText.systemBarCaption.copyWith(
                color: ShellMediaColors.lightForegroundSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(formatOpaqueColorHex(active), style: ShellText.systemBarValue),
            const SizedBox(height: 8),
            SettingsResetButton(
              key: resetKey,
              label: context.l10n.settingsThresholdColorReset,
              enabled: color != null,
              onPressed: onReset,
            ),
          ],
        ),
      ],
    );
  }
}

/// A debounced text input for one typed option.
class _OptionTextField extends StatefulWidget {
  const _OptionTextField({
    required this.fieldKey,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_OptionTextField> createState() => _OptionTextFieldState();
}

class _OptionTextFieldState extends State<_OptionTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _OptionTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // External edits land when the field is not being typed in.
    if (widget.value != _controller.text && !_focus.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: ShellText.systemBarCaption.copyWith(
            color: ShellMediaColors.lightForegroundSecondary,
          ),
        ),
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: SettingsGlass.control(context, SettingsColors.surfaceHigh),
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            border: Border.all(color: SettingsColors.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                key: widget.fieldKey,
                controller: _controller,
                focusNode: _focus,
                style: ShellText.systemBarValue,
                cursorColor: ShellMediaColors.lightForeground,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: ShellText.systemBarCaption.copyWith(
                    color: ShellMediaColors.lightForegroundSecondary.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The browsed-image row: the chosen file's name, a Browse button that opens
/// the host's chooser, and a clear control.
class _ImageRow extends StatelessWidget {
  const _ImageRow({
    required this.value,
    required this.rowKey,
    required this.browseKey,
    required this.clearKey,
    required this.label,
    required this.emptyLabel,
    required this.browseLabel,
    required this.clearLabel,
    required this.onBrowse,
    required this.onClear,
  });

  final String? value;
  final Key rowKey;
  final Key browseKey;
  final Key clearKey;
  final String label;
  final String emptyLabel;
  final String browseLabel;
  final String clearLabel;
  final VoidCallback onBrowse;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final chosen = value == null || value!.isEmpty
        ? emptyLabel
        : value!.split('/').last;
    return Row(
      key: rowKey,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellMediaColors.lightForegroundSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                chosen,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ShellText.systemBarValue.copyWith(
                  color: value == null || value!.isEmpty
                      ? ShellMediaColors.lightForegroundSecondary.withValues(
                          alpha: 0.6,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SettingsButton(key: browseKey, label: browseLabel, onPressed: onBrowse),
        const SizedBox(width: 8),
        SettingsResetButton(
          key: clearKey,
          label: clearLabel,
          enabled: value != null && value!.isNotEmpty,
          onPressed: onClear,
        ),
      ],
    );
  }
}

/// Per-workspace artwork mapping: existing rows replace or drop, and one
/// name field plus Browse adds a new mapping.
class _WorkspacePipMap extends StatefulWidget {
  const _WorkspacePipMap({
    required this.entries,
    required this.label,
    required this.nameHint,
    required this.addLabel,
    required this.chooseLabel,
    required this.customLabel,
    required this.browseLabel,
    required this.removeLabel,
    required this.pick,
    required this.fetchNames,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, String> entries;
  final String label;
  final String nameHint;
  final String addLabel;
  final String chooseLabel;
  final String customLabel;
  final String browseLabel;
  final String removeLabel;
  final Future<String?> Function() pick;

  /// Source of live workspace names; null asks the bar over the socket.
  final Future<List<String>> Function()? fetchNames;
  final void Function(String name, String path) onAdd;
  final void Function(String name) onRemove;

  @override
  State<_WorkspacePipMap> createState() => _WorkspacePipMapState();
}

class _WorkspacePipMapState extends State<_WorkspacePipMap> {
  final TextEditingController _name = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<String> _names = const <String>[];
  var _custom = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadNames());
  }

  Future<void> _loadNames() async {
    final fetcher = widget.fetchNames;
    final names = await (fetcher != null ? fetcher() : fetchWorkspaceNames());
    if (!mounted) {
      return;
    }
    setState(() => _names = names);
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    final path = await widget.pick();
    if (!mounted || path == null || path.isEmpty) {
      return;
    }
    widget.onAdd(name, path);
    _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.entries.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: ShellText.systemBarCaption.copyWith(
            color: ShellMediaColors.lightForegroundSecondary,
          ),
        ),
        for (final name in names)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.systemBarValue,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.entries[name]!.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.systemBarCaption.copyWith(
                      color: ShellMediaColors.lightForegroundSecondary,
                    ),
                  ),
                ),
                SettingsButton(
                  key: ValueKey<String>('workspaces-map-$name-browse'),
                  label: widget.browseLabel,
                  onPressed: () async {
                    final path = await widget.pick();
                    if (!mounted || path == null || path.isEmpty) {
                      return;
                    }
                    widget.onAdd(name, path);
                  },
                ),
                const SizedBox(width: 8),
                SettingsResetButton(
                  key: ValueKey<String>('workspaces-map-$name-remove'),
                  label: widget.removeLabel,
                  enabled: true,
                  onPressed: () => widget.onRemove(name),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            MenuAnchor(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll<Color>(
                  SettingsColors.surfaceHigh,
                ),
                surfaceTintColor: const WidgetStatePropertyAll<Color>(
                  ShellMediaColors.transparentDark,
                ),
                shadowColor: const WidgetStatePropertyAll<Color>(
                  Color(0x88000000),
                ),
                shape: const WidgetStatePropertyAll<OutlinedBorder>(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ),
                padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                  EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                ),
              ),
              menuChildren: [
                for (final name in _names)
                  MenuItemButton(
                    key: ValueKey<String>('workspaces-map-pick-$name'),
                    onPressed: () {
                      setState(() {
                        _custom = false;
                        _name.text = name;
                      });
                      // Picking a workspace goes straight to the chooser.
                      unawaited(_add());
                    },
                    child: Text(
                      name,
                      style: ShellText.systemBarValue.copyWith(
                        color: ShellMediaColors.lightForeground,
                      ),
                    ),
                  ),
                if (_names.isNotEmpty)
                  const Divider(height: 1, color: SettingsColors.outline),
                MenuItemButton(
                  key: const ValueKey<String>('workspaces-map-pick-custom'),
                  onPressed: () {
                    setState(() {
                      _custom = true;
                      _name.clear();
                    });
                    _focus.requestFocus();
                  },
                  child: Text(
                    widget.customLabel,
                    style: ShellText.systemBarValue.copyWith(
                      color: ShellMediaColors.lightForeground,
                    ),
                  ),
                ),
              ],
              builder: (context, controller, child) => SettingsButton(
                key: const ValueKey<String>('workspaces-map-pick'),
                label: _name.text.isEmpty ? widget.chooseLabel : _name.text,
                onPressed: controller.isOpen
                    ? controller.close
                    : controller.open,
              ),
            ),
            if (_custom) ...[
              const SizedBox(width: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: SettingsGlass.control(
                      context,
                      SettingsColors.surfaceHigh,
                    ),
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    border: Border.all(color: SettingsColors.outline),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: TextField(
                        key: const ValueKey<String>('workspaces-map-name'),
                        controller: _name,
                        focusNode: _focus,
                        style: ShellText.systemBarValue,
                        cursorColor: ShellMediaColors.lightForeground,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: widget.nameHint,
                          hintStyle: ShellText.systemBarCaption.copyWith(
                            color: ShellMediaColors.lightForegroundSecondary
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        onSubmitted: (_) => unawaited(_add()),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SettingsButton(
                key: const ValueKey<String>('workspaces-map-custom-browse'),
                label: widget.browseLabel,
                onPressed: () => unawaited(_add()),
              ),
            ],
          ],
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
