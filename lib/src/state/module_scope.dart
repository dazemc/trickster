import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'battery_bloc.dart';
import 'clock_bloc.dart';
import 'cpu_bloc.dart';
import 'gpu_bloc.dart';
import 'settings_bloc.dart';
import 'tray_bloc.dart';
import 'workspaces_bloc.dart';

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
    this.trayBuilder,
    this.batteryBuilder,
    this.workspacesBuilder,
    super.key,
  });

  final Widget child;
  final ClockBloc Function()? clockBuilder;
  final CpuBloc Function()? cpuBuilder;
  final GpuBloc Function()? gpuBuilder;
  final TrayBloc Function()? trayBuilder;
  final BatteryBloc Function()? batteryBuilder;
  final WorkspacesBloc Function()? workspacesBuilder;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsBloc>().state;
    return MultiBlocProvider(
      providers: [
        if (settings.includes('clock'))
          BlocProvider<ClockBloc>(
            create: (_) => clockBuilder?.call() ?? ClockBloc(),
          ),
        if (settings.includes('cpu'))
          BlocProvider<CpuBloc>(
            create: (_) =>
                cpuBuilder?.call() ?? (CpuBloc()..add(const CpuStarted())),
          ),
        if (settings.includes('gpu'))
          BlocProvider<GpuBloc>(
            create: (_) =>
                gpuBuilder?.call() ?? (GpuBloc()..add(const GpuStarted())),
          ),
        if (settings.includes('tray'))
          BlocProvider<TrayBloc>(
            create: (_) =>
                trayBuilder?.call() ?? (TrayBloc()..add(const TrayStarted())),
          ),
        if (settings.includes('battery'))
          BlocProvider<BatteryBloc>(
            create: (_) =>
                batteryBuilder?.call() ??
                (BatteryBloc()..add(const BatteryStarted())),
          ),
        if (settings.includes('workspaces'))
          BlocProvider<WorkspacesBloc>(
            create: (_) =>
                workspacesBuilder?.call() ??
                (WorkspacesBloc()..add(const WorkspacesStarted())),
          ),
      ],
      child: child,
    );
  }
}
