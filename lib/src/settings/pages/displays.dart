import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/l10n/generated/app_localizations.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/theme/tokens.dart';

/// Displays page: edge, thickness, and which outputs host the bar, written
/// through the `system_bar=` grammar.
class DisplaysPage extends StatefulWidget {
  const DisplaysPage({super.key});

  @override
  State<DisplaysPage> createState() => _DisplaysPageState();
}

class _DisplaysPageState extends State<DisplaysPage> {
  Timer? _saveTimer;
  SettingsAppBloc? _bloc;

  /// The newest slider value whose debounced save has not been enqueued yet.
  /// Kept in the page so a direct unmount can still enqueue that exact value:
  /// [SettingsAppBloc.flushOutputs] only sees a draft after the queued preview
  /// event has been processed, which may happen after this page is gone.
  OutputsConfig? _pendingSave;

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
    _saveTimer = null;
    final pending = _pendingSave;
    _pendingSave = null;
    final bloc = _bloc;
    if (bloc != null && !bloc.isClosed) {
      if (pending != null) {
        // The shell usually flushes before navigation, but a direct unmount
        // can land before the preview event makes `_outputsDraft` true.
        // Enqueue the value explicitly instead of asking the bloc to flush a
        // draft it may not have observed yet.
        bloc.add(SettingsAppOutputsSaveRequested(pending));
      } else {
        unawaited(bloc.flushOutputs());
      }
    }
    super.dispose();
  }

  /// Live preview while a control moves, saved once the movement pauses.
  void _apply(SettingsAppBloc bloc, OutputsConfig next) {
    _pendingSave = next;
    bloc.add(SettingsAppOutputsPreviewed(next));
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      _saveTimer = null;
      _pendingSave = null;
      bloc.add(SettingsAppOutputsSaveRequested(next));
    });
  }

  /// Discrete choices save immediately.
  void _applyNow(SettingsAppBloc bloc, OutputsConfig next) {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pendingSave = null;
    bloc.add(SettingsAppOutputsPreviewed(next));
    bloc.add(SettingsAppOutputsSaveRequested(next));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<SettingsAppBloc>();
    _bloc = controller;
    final (outputs, available) = context.select(
      (SettingsAppBloc bloc) =>
          (bloc.state.outputs, bloc.state.availableOutputs),
    );
    final outputsError = context.select(
      (SettingsAppBloc bloc) => bloc.state.outputsError,
    );
    final selected = outputs.connectors.isEmpty
        ? available.map((output) => output.name).toSet()
        : outputs.connectors.toSet();
    final hidden = outputs.side == SystemBarSide.hidden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(
          title: l10n.settingsDisplaysTitle,
          caption: l10n.settingsDisplaysCaption,
        ),
        if (outputsError != null) ...[
          const SizedBox(height: 16),
          // A failed write must not look like a saved one: the page keeps
          // showing the attempted values, so the banner states plainly that
          // the bar still uses its previous placement.
          Semantics(
            container: true,
            liveRegion: true,
            child: SettingsCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsOutputsSaveError,
                    style: ShellText.systemBarCaption.copyWith(
                      color: ShellTelemetryColors.danger,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    outputsError,
                    style: ShellText.systemBarCaption.copyWith(
                      color: ShellMediaColors.lightForegroundSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
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
                                // Hidden carries no connector selection in
                                // the grammar; clear it here so switching
                                // back to an edge starts from all outputs.
                                connectors: side == SystemBarSide.hidden
                                    ? const <String>[]
                                    : outputs.connectors,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SettingsResetButton(
                    key: const ValueKey<String>('reset-side'),
                    label: l10n.settingsResetOption(l10n.settingsSideLabel),
                    enabled: outputs.side != SystemBarSide.top,
                    onPressed: () => _applyNow(
                      controller,
                      outputs.copyWith(
                        side: SystemBarSide.top,
                        thickness: _thicknessForSide(
                          SystemBarSide.top,
                          outputs,
                        ),
                        connectors: hidden
                            ? const <String>[]
                            : outputs.connectors,
                      ),
                    ),
                  ),
                ],
              ),
              if (hidden) ...[
                const SizedBox(height: 14),
                Text(
                  l10n.settingsHiddenNote,
                  style: ShellText.systemBarCaption.copyWith(
                    color: ShellMediaColors.lightForegroundSecondary,
                  ),
                ),
              ],
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
                    hidden ? '0' : '${outputs.safeThickness.round()}',
                    style: ShellText.systemBarValue,
                  ),
                  const Spacer(),
                  SettingsResetButton(
                    key: const ValueKey<String>('reset-thickness'),
                    label: l10n.settingsResetOption(
                      l10n.settingsThicknessLabel,
                    ),
                    enabled:
                        !hidden &&
                        outputs.safeThickness.round() !=
                            _defaultThickness(outputs.side).round(),
                    onPressed: () => _applyNow(
                      controller,
                      outputs.copyWith(
                        thickness: _defaultThickness(outputs.side),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SettingsSlider(
                key: const ValueKey<String>('thickness-slider'),
                value: hidden
                    ? _minThickness(outputs.side)
                    : outputs.safeThickness.clamp(
                        _minThickness(outputs.side),
                        80,
                      ),
                min: _minThickness(outputs.side),
                max: 80,
                onChanged: hidden
                    ? null
                    : (value) => _apply(
                        controller,
                        outputs.copyWith(thickness: value.roundToDouble()),
                      ),
                onChangeEnd: hidden
                    ? null
                    : (value) => _applyNow(
                        controller,
                        outputs.copyWith(thickness: value.roundToDouble()),
                      ),
              ),
              const SizedBox(height: 22),
              if (!hidden) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.settingsOutputsLabel,
                        style: ShellText.systemBarCaption.copyWith(
                          color: ShellMediaColors.lightForegroundSecondary,
                        ),
                      ),
                    ),
                    SettingsResetButton(
                      key: const ValueKey<String>('reset-outputs'),
                      label: l10n.settingsResetOption(
                        l10n.settingsOutputsLabel,
                      ),
                      enabled: outputs.connectors.isNotEmpty,
                      onPressed: () => _applyNow(
                        controller,
                        outputs.copyWith(connectors: const <String>[]),
                      ),
                    ),
                  ],
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
            ],
          ),
        ),
      ],
    );
  }

  /// The thickness a newly selected edge should use: the current band is
  /// remembered for its own orientation, and the target orientation gets
  /// the band it last had (or a safe default).
  ///
  /// The hidden grammar carries neither geometry nor connectors, so entering
  /// hidden forgets the remembered bands and leaving it starts from the
  /// documented default. This is what makes hidden honest: switching back to
  /// an edge shows all outputs at the default thickness, not a stale
  /// selection that the file no longer contains.
  double _thicknessForSide(SystemBarSide side, OutputsConfig outputs) {
    final current = outputs.side;
    if (current.isHorizontal) {
      _horizontalThickness = outputs.safeThickness;
    } else if (current != SystemBarSide.hidden) {
      _verticalThickness = outputs.safeThickness;
    }
    if (side == SystemBarSide.hidden) {
      _horizontalThickness = null;
      _verticalThickness = null;
      return 0;
    }
    if (current == SystemBarSide.hidden) {
      return _defaultThickness(side);
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
    SettingsAppBloc controller,
    OutputsConfig outputs,
    List<LayerOutput> available,
    String name,
  ) {
    final all = available.map((output) => output.name).toList();
    final availableSet = all.toSet();
    final selected = outputs.connectors.isEmpty
        ? all.toSet()
        : outputs.connectors.toSet();
    if (selected.contains(name)) {
      selected.remove(name);
    } else {
      selected.add(name);
    }
    // The grammar treats an empty list as every output, so the last visible
    // output cannot be deselected here.
    if (selected.isEmpty) {
      return;
    }
    // A connector that is currently unplugged still belongs to the explicit
    // selection; dropping it would silently change what the bar hosts when
    // it returns. Only visible outputs drive the all-outputs shorthand.
    final visible = [
      for (final connector in all)
        if (selected.contains(connector)) connector,
    ];
    final stale = [
      for (final connector in outputs.connectors)
        if (!availableSet.contains(connector) && selected.contains(connector))
          connector,
    ];
    final ordered = [...visible, ...stale];
    final allVisible = visible.length == all.length;
    _applyNow(
      controller,
      outputs.copyWith(
        connectors: allVisible && stale.isEmpty ? const [] : ordered,
      ),
    );
  }
}

/// The smallest band that does not clip that orientation's pills.
double _defaultThickness(SystemBarSide side) => side.isHorizontal ? 32 : 72;

double _minThickness(SystemBarSide side) {
  return side == SystemBarSide.hidden || side.isHorizontal
      ? 20
      : _DisplaysPageState._verticalMinThickness;
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
                      '${output.name}  ${output.modeLabel}',
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
