import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/media.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/wallpaper_accent.dart';

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
    // The configured accent is the source unless the wallpaper is; the
    // sampled color is null until extraction lands, so the session and
    // brand colors still fall through. A stored pick selects the candidate
    // closest to it in hue. Appearance resolves per display, falling back to
    // the global keys.
    final wallpaper = context.watch<WallpaperAccentBloc>().state;
    final outputName = output;
    final source = settings.accentSourceFor(outputName);
    final picked = colorFromHex(settings.accentWallpaperPickFor(outputName));
    // Per-output sampling falls back to the first sampled output, so a
    // display sharing the wallpaper still gets candidates.
    final candidates = outputName == null
        ? wallpaper.topCandidates
        : wallpaper.candidatesFor(outputName);
    final sampledWallpaper = outputName == null
        ? wallpaper.color
        : wallpaper.accentFor(outputName) ?? wallpaper.color;
    final sampled = source == AccentSource.wallpaper
        ? picked == null
              ? sampledWallpaper
              : closestAccentCandidate(candidates, picked) ?? sampledWallpaper
        : null;
    final accent = resolveAccent(
      settings: sampled ?? settings.accentFor(outputName),
      session: context.select((SessionBloc bloc) => bloc.state.accent),
    );
    final horizontal = side.isHorizontal;
    final vertical = !horizontal;

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
              padding: vertical
                  ? const EdgeInsets.only(bottom: _cardGap)
                  : const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(
                child: TrayPill(
                  accent: accent,
                  items: state.items,
                  side: side,
                  thickness: thickness,
                  vertical: vertical,
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
              padding: vertical
                  ? const EdgeInsets.only(bottom: _cardGap)
                  : const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(
                child: MediaPill(accent: accent, vertical: vertical),
              ),
            ),
          );
        },
      ),
      'workspaces': (_) => RepaintBoundary(
        child: _WorkspacesRail(
          accent: accent,
          output: output,
          thickness: thickness,
          vertical: vertical,
          pipStyle: settings.workspaces.pipStyle,
        ),
      ),
      'gpu': (position) => BlocBuilder<GpuBloc, GpuState>(
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
                  key: ValueKey<String>('system-bar-gpu-${state.loads[i].id}'),
                  index: position,
                  horizontal: horizontal,
                  child: Padding(
                    padding: vertical
                        ? const EdgeInsets.only(bottom: _cardGap)
                        : const EdgeInsets.only(right: _cardGap),
                    child: RepaintBoundary(
                      child: GpuPill(
                        accent: accent,
                        load: state.loads[i],
                        captionSource: settings.gpu.captionSource,
                        sparkline: settings.gpu.sparkline,
                        vertical: vertical,
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
              padding: vertical
                  ? const EdgeInsets.only(bottom: _cardGap)
                  : const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(
                child: CpuPill(
                  accent: accent,
                  sample: sample,
                  warn: settings.cpu.warn,
                  critical: settings.cpu.critical,
                  captionSource: settings.cpu.captionSource,
                  sparkline: settings.cpu.sparkline,
                  vertical: vertical,
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
              padding: vertical
                  ? const EdgeInsets.only(bottom: _cardGap)
                  : const EdgeInsets.only(right: _cardGap),
              child: RepaintBoundary(
                child: BatteryPill(
                  accent: accent,
                  status: status,
                  onPressed: onOpenPowerSettings,
                  warn: settings.battery.warn,
                  critical: settings.battery.critical,
                  vertical: vertical,
                ),
              ),
            ),
          );
        },
      ),
      'clock': (position) => SystemBarEntrance(
        index: position,
        horizontal: horizontal,
        child: Padding(
          padding: vertical
              ? const EdgeInsets.only(bottom: _cardGap)
              : const EdgeInsets.only(right: _cardGap),
          child: RepaintBoundary(
            child: ClockPill(
              accent: accent,
              format: settings.clock.format,
              showDate: settings.clock.showDate,
              vertical: vertical,
            ),
          ),
        ),
      ),
    };

    return StripGeometry(
      side: side,
      thickness: thickness,
      child: Padding(
        padding: horizontal
            ? const EdgeInsets.symmetric(
                horizontal: _edgePadding,
                vertical: _cardMargin,
              )
            : const EdgeInsets.symmetric(
                horizontal: _cardMargin,
                vertical: _edgePadding,
              ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _moduleZone(
              settings: settings,
              builders: builders,
              zone: ModuleZone.leading,
              alignment: horizontal
                  ? Alignment.centerLeft
                  : Alignment.topCenter,
              horizontal: horizontal,
            ),
            _moduleZone(
              settings: settings,
              builders: builders,
              zone: ModuleZone.center,
              alignment: Alignment.center,
              horizontal: horizontal,
            ),
            _moduleZone(
              settings: settings,
              builders: builders,
              zone: ModuleZone.trailing,
              alignment: horizontal
                  ? Alignment.centerRight
                  : Alignment.bottomCenter,
              horizontal: horizontal,
            ),
          ],
        ),
      ),
    );
  }
}

/// One placement zone: the modules assigned to [zone] in configured order,
/// shrink-wrapped along the main axis and pinned to [alignment].
Widget _moduleZone({
  required BarSettings settings,
  required Map<String, Widget Function(int position)> builders,
  required ModuleZone zone,
  required Alignment alignment,
  required bool horizontal,
}) {
  return Align(
    alignment: alignment,
    child: Flex(
      direction: horizontal ? Axis.horizontal : Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var position = 0; position < settings.modules.length; position++)
          if (settings.zoneFor(settings.modules[position]) == zone)
            _zoneModule(
              settings.modules[position],
              builders[settings.modules[position]]?.call(position) ??
                  const SizedBox.shrink(),
              horizontal: horizontal,
            ),
      ],
    ),
  );
}

Widget _zoneModule(String module, Widget child, {required bool horizontal}) {
  if (module != 'tray') {
    return child;
  }
  // The tray can outgrow its zone; scroll it instead of overflowing.
  return Flexible(
    child: SingleChildScrollView(
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      child: child,
    ),
  );
}

class _WorkspacesRail extends StatelessWidget {
  const _WorkspacesRail({
    required this.accent,
    required this.output,
    required this.thickness,
    required this.vertical,
    required this.pipStyle,
  });

  final WallpaperAccent accent;
  final String? output;
  final double thickness;
  final bool vertical;
  final PipStyle pipStyle;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkspacesBloc, WorkspacesState>(
      builder: (context, state) {
        final workspaces = _outputRail(state.workspaces, output);
        final pill = WorkspacesPill(
          accent: accent,
          workspaces: workspaces,
          horizontal: true,
          style: pipStyle,
          onPressed: (workspace) => context.read<WorkspacesBloc>().add(
            WorkspacesFocusRequested(workspace),
          ),
        );
        if (!vertical) {
          return pill;
        }
        // Side strips scale the rail down so a longer row of pips cannot
        // clip.
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: thickness - 2 * TricksterBarStrip._cardMargin,
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: pill),
        );
      },
    );
  }
}

/// The workspaces the compositor places on [output], ordered by id, with the
/// numeric id as the printed label (decorated names keep their number). The
/// rail mirrors the compositor; Trickster neither synthesizes numbers nor
/// moves workspaces.
List<Workspace> _outputRail(List<Workspace> workspaces, String? output) {
  if (output == null || output.isEmpty) {
    return const <Workspace>[];
  }
  final rail = <Workspace>[];
  for (final workspace in workspaces) {
    final number = int.tryParse(workspace.id);
    if (workspace.output != output || number == null || number <= 0) {
      continue;
    }
    rail.add(
      Workspace(
        id: workspace.id,
        name: '$number',
        output: workspace.output,
        focused: workspace.focused,
        occupied: workspace.occupied,
        urgent: workspace.urgent,
      ),
    );
  }
  return rail;
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
