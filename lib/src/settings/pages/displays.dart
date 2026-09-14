import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../layout/system_bar.dart';
import '../../locale.dart';
import '../../platform/layer_shell.dart';
import '../../theme/tokens.dart';
import '../controller.dart';
import '../scope.dart';
import '../settings_theme.dart';

/// Displays page: edge, thickness, and which outputs host the bar, written
/// through the `system_bar=` grammar.
class DisplaysPage extends StatefulWidget {
  const DisplaysPage({super.key});

  @override
  State<DisplaysPage> createState() => _DisplaysPageState();
}

class _DisplaysPageState extends State<DisplaysPage> {
  Timer? _saveTimer;

  /// Horizontal and vertical strips keep their own thickness so switching
  /// edges never drags the other orientation's band along. Remembered for
  /// this app session; the file stores only the current one.
  double? _horizontalThickness;
  double? _verticalThickness;

  /// Vertical strips need room for the inline caption and value or the
  /// media controls; below this the pills clip.
  static const double _verticalMinThickness = 72;
  static const double _horizontalDefault = 32;

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  /// Live preview while a control moves, saved once the movement pauses.
  void _apply(SettingsAppController controller, OutputsConfig next) {
    controller.previewOutputs(next);
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(controller.saveOutputs(next)),
    );
  }

  /// Discrete choices save immediately.
  void _applyNow(SettingsAppController controller, OutputsConfig next) {
    _saveTimer?.cancel();
    _saveTimer = null;
    controller.previewOutputs(next);
    unawaited(controller.saveOutputs(next));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final outputs = controller.outputs;
    final available = controller.availableOutputs;
    final selected = outputs.connectors.isEmpty
        ? available.map((output) => output.name).toSet()
        : outputs.connectors.toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(
          title: l10n.settingsDisplaysTitle,
          caption: l10n.settingsDisplaysCaption,
        ),
        const SizedBox(height: 20),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsSideLabel,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellMediaColors.lightForegroundSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final side in const [
                    SystemBarSide.top,
                    SystemBarSide.bottom,
                    SystemBarSide.left,
                    SystemBarSide.right,
                    SystemBarSide.hidden,
                  ])
                    SettingsChoiceChip(
                      key: ValueKey<String>('side-${side.name}'),
                      label: _sideLabel(l10n, side),
                      selected: outputs.side == side,
                      onPressed: () => _applyNow(
                        controller,
                        outputs.copyWith(
                          side: side,
                          thickness: _thicknessForSide(side, outputs),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Text(
                    l10n.settingsThicknessLabel,
                    style: ShellText.systemBarCaption.copyWith(
                      color: ShellMediaColors.lightForegroundSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${outputs.thickness.round()}',
                    style: ShellText.systemBarValue,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SettingsSlider(
                key: const ValueKey<String>('thickness-slider'),
                value: outputs.thickness.clamp(_minThickness(outputs.side), 80),
                min: _minThickness(outputs.side),
                max: 80,
                onChanged: outputs.side == SystemBarSide.hidden
                    ? null
                    : (value) => _apply(
                        controller,
                        outputs.copyWith(thickness: value.roundToDouble()),
                      ),
                onChangeEnd: outputs.side == SystemBarSide.hidden
                    ? null
                    : (value) => _applyNow(
                        controller,
                        outputs.copyWith(thickness: value.roundToDouble()),
                      ),
              ),
              const SizedBox(height: 22),
              Text(
                l10n.settingsOutputsLabel,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellMediaColors.lightForegroundSecondary,
                ),
              ),
              const SizedBox(height: 10),
              if (available.isEmpty)
                Text(
                  l10n.settingsOutputsUnavailable,
                  style: ShellText.systemBarCaption.copyWith(
                    color: ShellMediaColors.lightForegroundSecondary,
                  ),
                )
              else
                Column(
                  children: [
                    for (final output in available)
                      _OutputRow(
                        key: ValueKey<String>('output-${output.name}'),
                        output: output,
                        selected: selected.contains(output.name),
                        onToggle: () => _toggleOutput(
                          controller,
                          outputs,
                          available,
                          output.name,
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (outputs.connectors.isEmpty)
                      Text(
                        l10n.settingsOutputAll,
                        style: ShellText.systemBarCaption.copyWith(
                          color: ShellMediaColors.lightForegroundSecondary,
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

  /// The thickness a newly selected edge should use: the current band is
  /// remembered for its own orientation, and the target orientation gets
  /// the band it last had (or a safe default).
  double _thicknessForSide(SystemBarSide side, OutputsConfig outputs) {
    final current = outputs.side;
    if (current.isHorizontal) {
      _horizontalThickness = outputs.thickness;
    } else if (current != SystemBarSide.hidden) {
      _verticalThickness = outputs.thickness;
    }
    if (side == SystemBarSide.hidden) {
      return outputs.thickness;
    }
    if (side.isHorizontal) {
      final thickness = _horizontalThickness ?? _horizontalDefault;
      return thickness < 20 ? 20 : thickness;
    }
    final thickness = _verticalThickness ?? _verticalMinThickness;
    return thickness < _verticalMinThickness
        ? _verticalMinThickness
        : thickness;
  }

  void _toggleOutput(
    SettingsAppController controller,
    OutputsConfig outputs,
    List<LayerOutput> available,
    String name,
  ) {
    final all = available.map((output) => output.name).toList();
    final selected = outputs.connectors.isEmpty
        ? all.toSet()
        : outputs.connectors.toSet();
    if (selected.contains(name)) {
      selected.remove(name);
    } else {
      selected.add(name);
    }
    // The grammar treats an empty list as every output, so the last output
    // cannot be deselected here.
    if (selected.isEmpty) {
      return;
    }
    final ordered = [
      for (final connector in all)
        if (selected.contains(connector)) connector,
    ];
    _applyNow(
      controller,
      outputs.copyWith(
        connectors: selected.length == all.length ? const [] : ordered,
      ),
    );
  }
}

/// The smallest band that does not clip that orientation's pills.
double _minThickness(SystemBarSide side) {
  return side.isHorizontal ? 20 : _DisplaysPageState._verticalMinThickness;
}

String _sideLabel(AppLocalizations l10n, SystemBarSide side) {
  return switch (side) {
    SystemBarSide.top => l10n.settingsSideTop,
    SystemBarSide.bottom => l10n.settingsSideBottom,
    SystemBarSide.left => l10n.settingsSideLeft,
    SystemBarSide.right => l10n.settingsSideRight,
    SystemBarSide.hidden => l10n.settingsSideHidden,
  };
}

class _OutputRow extends StatelessWidget {
  const _OutputRow({
    required this.output,
    required this.selected,
    required this.onToggle,
    super.key,
  });

  final LayerOutput output;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      toggled: selected,
      label: output.name,
      hint: l10n.settingsOutputToggleHint,
      onTap: onToggle,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${output.name}  ${output.width}×${output.height}',
                      style: ShellText.systemBarValue.copyWith(
                        color: selected
                            ? ShellMediaColors.lightForeground
                            : ShellMediaColors.lightForegroundSecondary,
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? ShellBrandColors.defaultAccent
                          : SettingsColors.surfaceHigh,
                      border: Border.all(color: SettingsColors.outline),
                    ),
                    child: const SizedBox.square(dimension: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
