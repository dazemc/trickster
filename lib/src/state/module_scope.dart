import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/opencode.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/opencode_bloc.dart';
import 'package:trickster/src/state/seat_idle_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/sink_volume_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/visualizer_bloc.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

/// Builds one [BlocProvider] per enabled module — and nothing for disabled
/// ones.
///
/// Sits below [SettingsBloc] and above the strip. When the module list
/// changes (live reload), providers for removed modules leave the tree:
/// [BlocProvider] closes those blocs, which cancel their timers,
/// subscriptions, and samplers. Providers for added modules are created
/// with their samplers started. A disabled module therefore owns zero
/// blocs, zero subscriptions, and zero timers.
///
/// The `*Builder` hooks exist for tests to seed initial states without
/// starting real samplers; production uses the defaults, which start the
/// sampler alongside the bloc.
class ModuleScope extends StatelessWidget {
  const ModuleScope({
    required this.child,
    this.clockBuilder,
    this.cpuBuilder,
    this.gpuBuilder,
    this.cpuSamplerBuilder,
    this.gpuSamplerBuilder,
    this.batterySamplerBuilder,
    this.opencodeSamplerBuilder,
    this.mediaServiceBuilder,
    this.trayBuilder,
    this.batteryBuilder,
    this.workspacesBuilder,
    this.mediaBuilder,
    this.visualizerBuilder,
    this.volumeBuilder,
    this.opencodeBuilder,
    super.key,
  });

  final Widget child;
  final ClockBloc Function()? clockBuilder;
  final CpuBloc Function()? cpuBuilder;
  final GpuBloc Function()? gpuBuilder;

  /// Sampler factories for tests that need the production paused-start wiring
  /// without touching `/proc/stat`, sysfs, NVML, or the OpenCode server.
  final CpuSampler Function()? cpuSamplerBuilder;
  final GpuSampler Function()? gpuSamplerBuilder;
  final BatterySampler Function()? batterySamplerBuilder;
  final OpencodeSampler Function()? opencodeSamplerBuilder;
  final MediaPlayerService Function()? mediaServiceBuilder;

  final TrayBloc Function()? trayBuilder;
  final BatteryBloc Function()? batteryBuilder;
  final WorkspacesBloc Function()? workspacesBuilder;
  final MediaBloc Function()? mediaBuilder;
  final VisualizerBloc Function()? visualizerBuilder;
  final SinkVolumeBloc Function()? volumeBuilder;
  final OpencodeBloc Function()? opencodeBuilder;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsBloc>().state;
    final gatesIdleSamplers =
        settings.includes('cpu') ||
        settings.includes('gpu') ||
        settings.includes('battery') ||
        settings.includes('media') ||
        settings.includes('opencode');
    return MultiBlocProvider(
      providers: [
        if (settings.includes('clock'))
          BlocProvider<ClockBloc>(
            create: (_) => clockBuilder?.call() ?? ClockBloc(),
          ),
        if (settings.includes('cpu'))
          BlocProvider<CpuBloc>(
            create: (context) =>
                cpuBuilder?.call() ??
                (CpuBloc(sampler: cpuSamplerBuilder?.call())..add(
                  CpuStarted(paused: context.read<SeatIdleBloc>().state.idle),
                )),
          ),
        if (settings.includes('gpu'))
          BlocProvider<GpuBloc>(
            create: (context) =>
                gpuBuilder?.call() ??
                (GpuBloc(sampler: gpuSamplerBuilder?.call())..add(
                  GpuStarted(paused: context.read<SeatIdleBloc>().state.idle),
                )),
          ),
        if (settings.includes('tray'))
          BlocProvider<TrayBloc>(
            create: (_) =>
                trayBuilder?.call() ?? (TrayBloc()..add(const TrayStarted())),
          ),
        if (settings.includes('battery'))
          BlocProvider<BatteryBloc>(
            create: (context) =>
                batteryBuilder?.call() ??
                (BatteryBloc(sampler: batterySamplerBuilder?.call())..add(
                  BatteryStarted(
                    paused: context.read<SeatIdleBloc>().state.idle,
                  ),
                )),
          ),
        if (settings.includes('workspaces'))
          BlocProvider<WorkspacesBloc>(
            create: (_) =>
                workspacesBuilder?.call() ??
                (WorkspacesBloc()..add(const WorkspacesStarted())),
          ),
        if (settings.includes('media')) ...[
          BlocProvider<MediaBloc>(
            create: (context) =>
                mediaBuilder?.call() ??
                (MediaBloc(service: mediaServiceBuilder?.call())..add(
                  MediaStarted(paused: context.read<SeatIdleBloc>().state.idle),
                )),
          ),
          BlocProvider<VisualizerBloc>(
            create: (_) => visualizerBuilder?.call() ?? VisualizerBloc(),
          ),
          BlocProvider<SinkVolumeBloc>(
            // The watcher starts with the module, not with a reader: the
            // pill only shows its percentage later (24.2).
            lazy: false,
            create: (_) =>
                volumeBuilder?.call() ??
                (SinkVolumeBloc()..add(const SinkVolumeStarted())),
          ),
        ],
        if (settings.includes('opencode'))
          BlocProvider<OpencodeBloc>(
            create: (context) =>
                opencodeBuilder?.call() ??
                (OpencodeBloc(sampler: opencodeSamplerBuilder?.call())..add(
                  OpencodeStarted(
                    paused: context.read<SeatIdleBloc>().state.idle,
                  ),
                )),
          ),
      ],
      child: gatesIdleSamplers
          ? BlocListener<SeatIdleBloc, SeatIdleState>(
              listenWhen: (previous, next) => previous.idle != next.idle,
              listener: (context, state) {
                // The captured module list matches the provider tree this
                // listener was built under, so a stale idle event can never
                // read a bloc that was already removed.
                if (settings.includes('cpu')) {
                  context.read<CpuBloc>().add(
                    state.idle ? const CpuPaused() : const CpuResumed(),
                  );
                }
                if (settings.includes('gpu')) {
                  context.read<GpuBloc>().add(
                    state.idle ? const GpuPaused() : const GpuResumed(),
                  );
                }
                if (settings.includes('battery')) {
                  context.read<BatteryBloc>().add(
                    state.idle ? const BatteryPaused() : const BatteryResumed(),
                  );
                }
                if (settings.includes('media')) {
                  context.read<MediaBloc>().add(MediaIdleChanged(state.idle));
                }
                if (settings.includes('opencode')) {
                  context.read<OpencodeBloc>().add(
                    state.idle
                        ? const OpencodePaused()
                        : const OpencodeResumed(),
                  );
                }
              },
              child: child,
            )
          : child,
    );
  }
}
