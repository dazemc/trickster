import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/disk.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/opencode.dart';
import 'package:trickster/src/services/ram.dart';
import 'package:trickster/src/services/temperature.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/disk_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/keyboard_layout_bloc.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/opencode_bloc.dart';
import 'package:trickster/src/state/ram_bloc.dart';
import 'package:trickster/src/state/seat_idle_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/sink_volume_bloc.dart';
import 'package:trickster/src/state/temperature_bloc.dart';
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
    this.ramBuilder,
    this.temperatureBuilder,
    this.diskBuilder,
    this.keyboardLayoutBuilder,
    this.gpuBuilder,
    this.cpuSamplerBuilder,
    this.ramSamplerBuilder,
    this.temperatureSamplerBuilder,
    this.diskSamplerBuilder,
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
  final RamBloc Function()? ramBuilder;
  final TemperatureBloc Function()? temperatureBuilder;
  final DiskBloc Function()? diskBuilder;
  final KeyboardLayoutBloc Function()? keyboardLayoutBuilder;
  final GpuBloc Function({
    required bool includeUsage,
    required bool includeMemory,
  })?
  gpuBuilder;

  /// Sampler factories for tests that need the production paused-start wiring
  /// without touching `/proc/stat`, `/proc/meminfo`, hwmon, statvfs, sysfs,
  /// NVML, or the OpenCode server.
  final CpuSampler Function()? cpuSamplerBuilder;
  final RamSampler Function()? ramSamplerBuilder;
  final TemperatureSampler Function()? temperatureSamplerBuilder;
  final DiskSampler Function()? diskSamplerBuilder;
  final GpuSampler Function()? gpuSamplerBuilder;
  final BatterySampler Function()? batterySamplerBuilder;
  final OpencodeSampler Function()? opencodeSamplerBuilder;
  final MediaPlayerClient Function()? mediaServiceBuilder;

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
        settings.includes('ram') ||
        settings.includes('temperature') ||
        settings.includes('disk') ||
        settings.includes('gpu') ||
        settings.includes('vram') ||
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
        if (settings.includes('ram'))
          BlocProvider<RamBloc>(
            create: (context) =>
                ramBuilder?.call() ??
                (RamBloc(sampler: ramSamplerBuilder?.call())..add(
                  RamStarted(paused: context.read<SeatIdleBloc>().state.idle),
                )),
          ),
        if (settings.includes('temperature'))
          BlocProvider<TemperatureBloc>(
            create: (context) =>
                temperatureBuilder?.call() ??
                (TemperatureBloc(sampler: temperatureSamplerBuilder?.call())
                  ..add(
                    TemperatureStarted(
                      paused: context.read<SeatIdleBloc>().state.idle,
                    ),
                  )),
          ),
        if (settings.includes('disk'))
          BlocProvider<DiskBloc>(
            key: ValueKey<String>('disk-${settings.disk.path}'),
            create: (context) =>
                diskBuilder?.call() ??
                (DiskBloc(
                  sampler:
                      diskSamplerBuilder?.call() ??
                      DiskSampler(path: settings.disk.path),
                )..add(
                  DiskStarted(paused: context.read<SeatIdleBloc>().state.idle),
                )),
          ),
        if (settings.includes('keyboard_layout'))
          BlocProvider<KeyboardLayoutBloc>(
            create: (_) =>
                keyboardLayoutBuilder?.call() ??
                (KeyboardLayoutBloc()..add(const KeyboardLayoutStarted())),
          ),
        if (settings.includes('gpu') || settings.includes('vram'))
          BlocProvider<GpuBloc>(
            create: (context) {
              final includeUsage = settings.includes('gpu');
              final includeMemory = settings.includes('vram');
              return gpuBuilder?.call(
                    includeUsage: includeUsage,
                    includeMemory: includeMemory,
                  ) ??
                  (GpuBloc(
                    sampler: gpuSamplerBuilder?.call(),
                    includeUsage: includeUsage,
                    includeMemory: includeMemory,
                  )..add(
                    GpuStarted(paused: context.read<SeatIdleBloc>().state.idle),
                  ));
            },
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
      child: BlocListener<SettingsBloc, BarSettings>(
        // Keep the one shared GpuBloc alive, but update its sampler when the
        // gpu/vram pair changes. Recreating the provider would reset history
        // and can overlap sampler lifetimes during the swap.
        listenWhen: (previous, next) =>
            previous.includes('gpu') != next.includes('gpu') ||
            previous.includes('vram') != next.includes('vram'),
        listener: (context, settings) {
          if (!settings.includes('gpu') && !settings.includes('vram')) {
            return;
          }
          context.read<GpuBloc>().add(
            GpuConfigured(
              includeUsage: settings.includes('gpu'),
              includeMemory: settings.includes('vram'),
            ),
          );
        },
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
                  if (settings.includes('ram')) {
                    context.read<RamBloc>().add(
                      state.idle ? const RamPaused() : const RamResumed(),
                    );
                  }
                  if (settings.includes('temperature')) {
                    context.read<TemperatureBloc>().add(
                      state.idle
                          ? const TemperaturePaused()
                          : const TemperatureResumed(),
                    );
                  }
                  if (settings.includes('disk')) {
                    context.read<DiskBloc>().add(
                      state.idle ? const DiskPaused() : const DiskResumed(),
                    );
                  }
                  if (settings.includes('gpu') || settings.includes('vram')) {
                    context.read<GpuBloc>().add(
                      state.idle ? const GpuPaused() : const GpuResumed(),
                    );
                  }
                  if (settings.includes('battery')) {
                    context.read<BatteryBloc>().add(
                      state.idle
                          ? const BatteryPaused()
                          : const BatteryResumed(),
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
      ),
    );
  }
}
