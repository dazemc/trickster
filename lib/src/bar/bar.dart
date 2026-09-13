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
    final horizontal = side.isHorizontal;
    final cpuVisible =
        settings.includes('cpu') &&
        context.select((CpuBloc bloc) => bloc.state.current != null);
    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(
              horizontal: _edgePadding,
              vertical: _cardMargin,
            )
          : const EdgeInsets.symmetric(
              horizontal: _cardMargin,
              vertical: _edgePadding,
            ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Flex(
          direction: horizontal ? Axis.horizontal : Axis.vertical,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (settings.includes('tray'))
              BlocBuilder<TrayBloc, TrayState>(
                builder: (context, state) {
                  if (state.items.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return SystemBarEntrance(
                    index: 3,
                    horizontal: horizontal,
                    child: Padding(
                      padding: horizontal
                          ? const EdgeInsets.only(right: _cardGap)
                          : const EdgeInsets.only(bottom: _cardGap),
                      child: RepaintBoundary(
                        child: TrayPill(
                          accent: accent,
                          items: state.items,
                          side: side,
                          thickness: thickness,
                          onActivate: (item, position) => unawaited(
                            context.read<TrayBloc>().invoke(
                              item,
                              SystemTrayAction.activate,
                              position,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (settings.includes('media'))
              Builder(
                builder: (context) {
                  final available = context.select(
                    (MediaBloc bloc) => bloc.state.available,
                  );
                  if (!available) {
                    return const SizedBox.shrink();
                  }
                  return SystemBarEntrance(
                    index: 4,
                    horizontal: horizontal,
                    child: Padding(
                      padding: horizontal
                          ? const EdgeInsets.only(right: _cardGap)
                          : const EdgeInsets.only(bottom: _cardGap),
                      child: RepaintBoundary(child: MediaPill(accent: accent)),
                    ),
                  );
                },
              ),
            if (settings.includes('workspaces'))
              BlocBuilder<WorkspacesBloc, WorkspacesState>(
                builder: (context, state) {
                  final options = context.select(
                    (SettingsBloc bloc) => bloc.state.workspaces,
                  );
                  var workspaces = workspacesForOutput(
                    state.workspaces,
                    output,
                  );
                  if (!options.showEmpty) {
                    workspaces = [
                      for (final workspace in workspaces)
                        if (workspace.occupied || workspace.focused) workspace,
                    ];
                  }
                  if (workspaces.length > options.max) {
                    workspaces = workspaces
                        .take(options.max)
                        .toList(growable: false);
                  }
                  if (workspaces.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return SystemBarEntrance(
                    index: 2,
                    horizontal: horizontal,
                    child: Padding(
                      padding: horizontal
                          ? const EdgeInsets.only(right: _cardGap)
                          : const EdgeInsets.only(bottom: _cardGap),
                      child: RepaintBoundary(
                        child: WorkspacesPill(
                          accent: accent,
                          workspaces: workspaces,
                          horizontal: horizontal,
                          onPressed: (workspace) => context
                              .read<WorkspacesBloc>()
                              .add(WorkspacesFocusRequested(workspace)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (settings.includes('gpu'))
              BlocBuilder<GpuBloc, GpuState>(
                builder: (context, state) {
                  if (state.loads.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Flex(
                    direction: horizontal ? Axis.horizontal : Axis.vertical,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < state.loads.length; i += 1)
                        SystemBarEntrance(
                          key: ValueKey<String>(
                            'system-bar-gpu-${state.loads[i].id}',
                          ),
                          index:
                              (cpuVisible ? 1 : 0) + (state.loads.length - i),
                          horizontal: horizontal,
                          child: Padding(
                            padding: horizontal
                                ? const EdgeInsets.only(right: _cardGap)
                                : const EdgeInsets.only(bottom: _cardGap),
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
            if (settings.includes('cpu'))
              BlocBuilder<CpuBloc, CpuSample>(
                builder: (context, sample) {
                  if (sample.current == null) {
                    return const SizedBox.shrink();
                  }
                  return SystemBarEntrance(
                    index: 1,
                    horizontal: horizontal,
                    child: Padding(
                      padding: horizontal
                          ? const EdgeInsets.only(right: _cardGap)
                          : const EdgeInsets.only(bottom: _cardGap),
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
            if (settings.includes('battery'))
              BlocBuilder<BatteryBloc, BatteryStatus>(
                builder: (context, status) {
                  if (status.capacity == null) {
                    return const SizedBox.shrink();
                  }
                  return SystemBarEntrance(
                    index: 1,
                    horizontal: horizontal,
                    child: Padding(
                      padding: horizontal
                          ? const EdgeInsets.only(right: _cardGap)
                          : const EdgeInsets.only(bottom: _cardGap),
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
            if (settings.includes('clock'))
              SystemBarEntrance(
                index: 0,
                horizontal: horizontal,
                child: RepaintBoundary(
                  child: ClockPill(
                    accent: accent,
                    format: settings.clock.format,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
