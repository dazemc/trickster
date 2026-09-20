import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/flow.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/media.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
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

class TricksterBarStrip extends StatefulWidget {
  const TricksterBarStrip({
    required this.side,
    this.thickness = 32,
    this.output,
    this.onOpenPowerSettings = _noop,
    super.key,
  });

  final SystemBarSide side;

  /// Configured cross-axis size; the strip grows past it when its wrapped
  /// content needs more rows.
  final double thickness;

  /// Connector this strip is on, so per-output modules (workspaces) can
  /// filter their state. Null before the output enumeration lands.
  final String? output;
  final VoidCallback onOpenPowerSettings;

  static const double _edgePadding = 8;
  static const double _cardMargin = 5;
  static const double _cardGap = 8;

  @override
  State<TricksterBarStrip> createState() => _TricksterBarStripState();
}

class _TricksterBarStripState extends State<TricksterBarStrip> {
  double? _surfaceCross;
  double? _requested;

  /// The zone layout asked for a cross extent; resize the layer surface and
  /// its exclusive zone once per distinct target.
  void _requestThickness(double needed) {
    final target = needed + 2 * TricksterBarStrip._cardMargin;
    final current = _surfaceCross;
    if (current == null ||
        (target - current).abs() < 0.5 ||
        _requested == target) {
      return;
    }
    _requested = target;
    final viewId = View.of(context).viewId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        LayerShell()
            .setSurfaceThickness(viewId: viewId, thickness: target)
            .catchError((Object _) {}),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.side;
    final thickness = widget.thickness;
    final output = widget.output;
    final onOpenPowerSettings = widget.onOpenPowerSettings;
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
                  ? const EdgeInsets.only(bottom: TricksterBarStrip._cardGap)
                  : const EdgeInsets.only(right: TricksterBarStrip._cardGap),
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
                  ? const EdgeInsets.only(bottom: TricksterBarStrip._cardGap)
                  : const EdgeInsets.only(right: TricksterBarStrip._cardGap),
              child: RepaintBoundary(
                child: MediaPill(
                  accent: accent,
                  mode: settings.media.mode,
                  vertical: vertical,
                ),
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
          imageSource: settings.workspaces.imageSource,
          imageByWorkspace: settings.workspaces.imageByWorkspace,
          tintSvg: settings.workspaces.tintSvg,
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
                        ? const EdgeInsets.only(
                            bottom: TricksterBarStrip._cardGap,
                          )
                        : const EdgeInsets.only(
                            right: TricksterBarStrip._cardGap,
                          ),
                    child: RepaintBoundary(
                      child: GpuPill(
                        accent: accent,
                        load: state.loads[i],
                        warn: settings.gpu.warn,
                        critical: settings.gpu.critical,
                        captionSource: settings.gpu.captionSource,
                        captionPrefix: settings.gpu.captionPrefix,
                        warnColor: settings.gpu.warnColor,
                        criticalColor: settings.gpu.criticalColor,
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
                  ? const EdgeInsets.only(bottom: TricksterBarStrip._cardGap)
                  : const EdgeInsets.only(right: TricksterBarStrip._cardGap),
              child: RepaintBoundary(
                child: CpuPill(
                  accent: accent,
                  sample: sample,
                  warn: settings.cpu.warn,
                  critical: settings.cpu.critical,
                  captionSource: settings.cpu.captionSource,
                  captionPrefix: settings.cpu.captionPrefix,
                  warnColor: settings.cpu.warnColor,
                  criticalColor: settings.cpu.criticalColor,
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
                  ? const EdgeInsets.only(bottom: TricksterBarStrip._cardGap)
                  : const EdgeInsets.only(right: TricksterBarStrip._cardGap),
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
              ? const EdgeInsets.only(bottom: TricksterBarStrip._cardGap)
              : const EdgeInsets.only(right: TricksterBarStrip._cardGap),
          child: RepaintBoundary(
            child: ClockPill(
              accent: accent,
              format: settings.clock.format,
              showDate: settings.clock.showDate,
              showSeconds: settings.clock.showSeconds,
              dateStyle: settings.clock.dateStyle,
              vertical: vertical,
            ),
          ),
        ),
      ),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        _surfaceCross = horizontal
            ? constraints.maxHeight
            : constraints.maxWidth;
        // Rows wrap against the configured band, never the grown surface:
        // deriving the band from the current size makes every grown frame
        // demand another row and the resize never settles.
        final bandCross = thickness - 2 * TricksterBarStrip._cardMargin;
        return StripGeometry(
          side: side,
          thickness: _surfaceCross ?? thickness,
          child: Padding(
            padding: horizontal
                ? const EdgeInsets.symmetric(
                    horizontal: TricksterBarStrip._edgePadding,
                    vertical: TricksterBarStrip._cardMargin,
                  )
                : const EdgeInsets.symmetric(
                    horizontal: TricksterBarStrip._cardMargin,
                    vertical: TricksterBarStrip._edgePadding,
                  ),
            child: CustomMultiChildLayout(
              delegate: _StripZoneLayout(
                horizontal: horizontal,
                onNeeded: _requestThickness,
              ),
              children: [
                LayoutId(
                  id: _StripZoneLayout.leadingId,
                  child: _zoneWrap(
                    key: const ValueKey<String>('strip-zone-leading'),
                    horizontal: horizontal,
                    child: _moduleZone(
                      settings: settings,
                      builders: builders,
                      zone: ModuleZone.leading,
                      horizontal: horizontal,
                      bandCross: bandCross,
                    ),
                  ),
                ),
                LayoutId(
                  id: _StripZoneLayout.centerId,
                  child: _zoneWrap(
                    key: const ValueKey<String>('strip-zone-center'),
                    horizontal: horizontal,
                    child: _moduleZone(
                      settings: settings,
                      builders: builders,
                      zone: ModuleZone.center,
                      horizontal: horizontal,
                      bandCross: bandCross,
                    ),
                  ),
                ),
                LayoutId(
                  id: _StripZoneLayout.trailingId,
                  child: _zoneWrap(
                    key: const ValueKey<String>('strip-zone-trailing'),
                    horizontal: horizontal,
                    child: _moduleZone(
                      settings: settings,
                      builders: builders,
                      zone: ModuleZone.trailing,
                      horizontal: horizontal,
                      bandCross: bandCross,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One placement zone: the modules assigned to [zone] in configured order,
/// shrink-wrapped along the main axis.
Widget _moduleZone({
  required BarSettings settings,
  required Map<String, Widget Function(int position)> builders,
  required ModuleZone zone,
  required bool horizontal,
  required double bandCross,
}) {
  return BarFlow(
    horizontal: horizontal,
    alignment: switch (zone) {
      ModuleZone.leading => MainAxisAlignment.start,
      ModuleZone.center => MainAxisAlignment.center,
      ModuleZone.trailing => MainAxisAlignment.end,
    },
    crossExtent: bandCross,
    children: [
      for (var position = 0; position < settings.modules.length; position++)
        if (settings.zoneFor(settings.modules[position]) == zone)
          builders[settings.modules[position]]?.call(position) ??
              const SizedBox.shrink(),
    ],
  );
}

/// The zone's box: marked for tests, sized by the layout delegate.
Widget _zoneWrap({
  required Key key,
  required Widget child,
  required bool horizontal,
}) {
  return KeyedSubtree(key: key, child: child);
}

/// Places the three zones without overlap: the center keeps its natural size
/// up to the full span, each side clamps to the space the center leaves. The
/// delegate reports the cross extent its wrapped content needs so the strip
/// can grow past the configured thickness.
class _StripZoneLayout extends MultiChildLayoutDelegate {
  _StripZoneLayout({required this.horizontal, required this.onNeeded});

  static const Object leadingId = 'leading';
  static const Object centerId = 'center';
  static const Object trailingId = 'trailing';

  final bool horizontal;
  final ValueChanged<double> onNeeded;

  @override
  void performLayout(Size size) {
    final center = layoutChild(centerId, _zoneConstraints(size, size));
    final mainMax = horizontal ? size.width : size.height;
    final centerMain = horizontal ? center.width : center.height;
    final sideMain = ((mainMax - centerMain) / 2).clamp(0.0, mainMax);
    final sideConstraints = _zoneConstraints(size, Size(sideMain, mainMax));
    final leading = layoutChild(leadingId, sideConstraints);
    final trailing = layoutChild(trailingId, sideConstraints);

    // Content may wrap past the current surface; report what it needs so the
    // strip can resize its layer surface.
    final needed = [
      leading,
      center,
      trailing,
    ].map((size) => horizontal ? size.height : size.width).reduce(max);
    onNeeded(needed);

    double cross(double extent) =>
        ((horizontal ? size.height : size.width) - extent) / 2;

    if (horizontal) {
      positionChild(leadingId, Offset(0, cross(leading.height)));
      positionChild(
        centerId,
        Offset((size.width - center.width) / 2, cross(center.height)),
      );
      positionChild(
        trailingId,
        Offset(size.width - trailing.width, cross(trailing.height)),
      );
    } else {
      positionChild(leadingId, Offset(cross(leading.width), 0));
      positionChild(
        centerId,
        Offset(cross(center.width), (size.height - center.height) / 2),
      );
      positionChild(
        trailingId,
        Offset(cross(trailing.width), size.height - trailing.height),
      );
    }
  }

  /// Loose along the main axis (up to the clamped width) and unbounded
  /// across it, so a zone can report the taller band its wrapped rows need.
  BoxConstraints _zoneConstraints(Size size, Size main) {
    if (horizontal) {
      return BoxConstraints(maxWidth: main.width);
    }
    return BoxConstraints(maxHeight: main.height);
  }

  @override
  bool shouldRelayout(_StripZoneLayout oldDelegate) =>
      oldDelegate.horizontal != horizontal;
}

class _WorkspacesRail extends StatelessWidget {
  const _WorkspacesRail({
    required this.accent,
    required this.output,
    required this.thickness,
    required this.vertical,
    required this.pipStyle,
    required this.imageSource,
    required this.imageByWorkspace,
    required this.tintSvg,
  });

  final WallpaperAccent accent;
  final String? output;
  final double thickness;
  final bool vertical;
  final PipStyle pipStyle;
  final String? imageSource;
  final Map<String, String> imageByWorkspace;
  final bool tintSvg;

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
          imageSource: imageSource,
          imageByWorkspace: imageByWorkspace,
          tintSvg: tintSvg,
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
