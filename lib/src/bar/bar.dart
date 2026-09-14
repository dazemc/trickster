import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../config/settings.dart';
import '../layout/system_bar.dart';
import '../services/battery.dart';
import '../services/cpu.dart';
import '../services/gpu.dart';
import '../services/status_notifier.dart';
import '../services/workspaces.dart';
import '../state/battery_bloc.dart';
import '../state/cpu_bloc.dart';
import '../state/gpu_bloc.dart';
import '../state/media_bloc.dart';
import '../state/session_bloc.dart';
import '../state/settings_bloc.dart';
import '../state/tray_bloc.dart';
import '../state/workspaces_bloc.dart';
import '../theme/accent.dart';
import 'battery.dart';
import 'clock.dart';
import 'cpu.dart';
import 'gpu.dart';
import 'media.dart';
import 'pill.dart';
import 'tray.dart';
import 'workspaces.dart';

class TricksterBarStrip extends StatelessWidget {
  const TricksterBarStrip({
    required this.side,
    this.thickness = 32,
    this.output,
    this.onOpenPowerSettings = _noop,
    super.key,
  });

  final SystemBarSide side;

  /// Cross-axis size of the strip band, used to place menus off the bar.
  final double thickness;

  /// Connector this strip is on, so per-output modules (workspaces) can
  /// filter their state. Null before the output enumeration lands.
  final String? output;
  final VoidCallback onOpenPowerSettings;

  static const double _edgePadding = 8;
  static const double _cardMargin = 5;
  static const double _cardGap = 8;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsBloc>().state;
    final accent = resolveAccent(
      settings: settings.accent,
      session: context.select((SessionBloc bloc) => bloc.state.accent),
    );
    // The cluster is always laid out horizontally; a vertical strip rotates
    // the whole cluster into place, so every module keeps one layout.
    const horizontal = true;
    final vertical = !side.isHorizontal;

    // One builder per module; the strip walks settings.modules so the
    // configured order is the rendered order.
    final builders = <String, Widget Function(int position)>{
      'tray': (position) => BlocBuilder<TrayBloc, TrayState>(
        builder: (context, state) {
          if (state.items.isEmpty) {
            return const SizedBox.shrink();
          }
          return SystemBarEntrance(
            index: position,
            horizontal: horizontal,
            child: Padding(
              padding: const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(
                child: TrayPill(
                  accent: accent,
                  items: state.items,
                  side: side,
                  thickness: thickness,
                  onActivate: (item, position2) => unawaited(
                    context.read<TrayBloc>().invoke(
                      item,
                      SystemTrayAction.activate,
                      position2,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      'media': (position) => Builder(
        builder: (context) {
          final available = context.select(
            (MediaBloc bloc) => bloc.state.available,
          );
          if (!available) {
            return const SizedBox.shrink();
          }
          return SystemBarEntrance(
            index: position,
            horizontal: horizontal,
            child: Padding(
              padding: const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(child: MediaPill(accent: accent)),
            ),
          );
        },
      ),
      'workspaces': (position) => BlocBuilder<WorkspacesBloc, WorkspacesState>(
        builder: (context, state) {
          final options = context.select(
            (SettingsBloc bloc) => bloc.state.workspaces,
          );
          var workspaces = workspacesForOutput(state.workspaces, output);
          if (!options.showEmpty) {
            workspaces = [
              for (final workspace in workspaces)
                if (workspace.occupied || workspace.focused) workspace,
            ];
          }
          if (workspaces.length > options.max) {
            workspaces = workspaces.take(options.max).toList(growable: false);
          }
          if (workspaces.isEmpty) {
            return const SizedBox.shrink();
          }
          return SystemBarEntrance(
            index: position,
            horizontal: horizontal,
            child: Padding(
              padding: const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(
                child: WorkspacesPill(
                  accent: accent,
                  workspaces: workspaces,
                  horizontal: horizontal,
                  onPressed: (workspace) => context.read<WorkspacesBloc>().add(
                    WorkspacesFocusRequested(workspace),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      'gpu': (position) => BlocBuilder<GpuBloc, GpuState>(
        builder: (context, state) {
          if (state.loads.isEmpty) {
            return const SizedBox.shrink();
          }
          return Flex(
            direction: Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < state.loads.length; i += 1)
                SystemBarEntrance(
                  key: ValueKey<String>('system-bar-gpu-${state.loads[i].id}'),
                  index: position,
                  horizontal: horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(right: _cardGap),
                    child: RepaintBoundary(
                      child: GpuPill(
                        accent: accent,
                        load: state.loads[i],
                        captionSource: settings.meter.captionSource,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      'cpu': (position) => BlocBuilder<CpuBloc, CpuSample>(
        builder: (context, sample) {
          if (sample.current == null) {
            return const SizedBox.shrink();
          }
          return SystemBarEntrance(
            index: position,
            horizontal: horizontal,
            child: Padding(
              padding: const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(
                child: CpuPill(
                  accent: accent,
                  sample: sample,
                  warn: settings.cpu.warn,
                  critical: settings.cpu.critical,
                  captionSource: settings.meter.captionSource,
                ),
              ),
            ),
          );
        },
      ),
      'battery': (position) => BlocBuilder<BatteryBloc, BatteryStatus>(
        builder: (context, status) {
          if (status.capacity == null) {
            return const SizedBox.shrink();
          }
          return SystemBarEntrance(
            index: position,
            horizontal: horizontal,
            child: Padding(
              padding: const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(
                child: BatteryPill(
                  accent: accent,
                  status: status,
                  onPressed: onOpenPowerSettings,
                  warn: settings.battery.warn,
                  critical: settings.battery.critical,
                ),
              ),
            ),
          );
        },
      ),
      'clock': (position) => SystemBarEntrance(
        index: position,
        horizontal: horizontal,
        child: RepaintBoundary(
          child: ClockPill(accent: accent, format: settings.clock.format),
        ),
      ),
    };

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _edgePadding,
        vertical: _cardMargin,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Flex(
          direction: Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (
              var position = 0;
              position < settings.modules.length;
              position++
            )
              builders[settings.modules[position]]?.call(position) ??
                  const SizedBox.shrink(),
          ],
        ),
      ),
    );
    if (!vertical) {
      return content;
    }
    // Rotating clockwise puts the trailing cluster at the bottom for both
    // side edges; the strip's cross axis becomes the cluster's height.
    return RotatedBox(quarterTurns: 1, child: content);
  }
}

class TricksterBar {
  const TricksterBar({
    required this.side,
    required this.thickness,
    required this.settings,
    required this.accent,
  });

  final SystemBarSide side;
  final double thickness;
  final BarSettings settings;
  final WallpaperAccent accent;
}

void _noop() {}
