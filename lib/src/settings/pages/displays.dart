import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../layout/system_bar.dart';
import '../../locale.dart';
import '../../platform/layer_shell.dart';
import '../../theme/motion.dart';
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
                    _ChoiceChip(
                      key: ValueKey<String>('side-${side.name}'),
                      label: _sideLabel(l10n, side),
                      selected: outputs.side == side,
                      onPressed: () => _applyNow(
                        controller,
                        outputs.copyWith(
                          side: side,
                          // `hidden` parses to thickness 0; leaving it
                          // hidden would make the next visible choice a
                          // zero-thickness bar.
                          thickness: side == SystemBarSide.hidden
                              ? outputs.thickness
                              : (outputs.thickness > 0
                                    ? outputs.thickness
                                    : 32),
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
                value: outputs.thickness.clamp(20, 80),
                min: 20,
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

String _sideLabel(AppLocalizations l10n, SystemBarSide side) {
  return switch (side) {
    SystemBarSide.top => l10n.settingsSideTop,
    SystemBarSide.bottom => l10n.settingsSideBottom,
    SystemBarSide.left => l10n.settingsSideLeft,
    SystemBarSide.right => l10n.settingsSideRight,
    SystemBarSide.hidden => l10n.settingsSideHidden,
  };
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Motion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(999)),
                color: selected
                    ? ShellBrandColors.defaultAccent
                    : SettingsColors.surfaceHigh,
                border: Border.all(color: SettingsColors.outline),
              ),
              child: Text(
                label,
                style: ShellText.systemBarCaption.copyWith(
                  color: selected
                      ? SettingsColors.background
                      : ShellMediaColors.lightForeground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
