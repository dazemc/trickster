import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/module_scope.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

/// Workspaces every harnessed strip renders: one focused, one urgent.
const harnessWorkspaces = [
  Workspace(id: '1', name: '1', focused: true),
  Workspace(id: '2', name: '2', urgent: true),
];

/// Pumps the production nesting — config providers above a [ModuleScope]
/// above the real strip — with seeded module states, so no sampler starts.
///
/// The widget-test contract lives in `docs_site/content/development.md`:
/// states are seeded through constructors, providers own bloc lifecycle, and
/// nothing awaits `pumpEventQueue` under FakeAsync. The `*Builder` hooks let
/// a test swap one bloc (for example one that notes its own close) without
/// changing the shape of the tree.
Future<void> pumpBarHarness(
  WidgetTester tester, {
  BarSettings settings = const BarSettings(),
  Locale locale = const Locale('en', 'US'),
  SystemBarSide side = SystemBarSide.top,
  double thickness = 32,
  String? output,
  List<String> outputs = const [],
  WallpaperAccentController? wallpaperAccent,
  ClockBloc Function()? clockBuilder,
  CpuBloc Function()? cpuBuilder,
  GpuBloc Function()? gpuBuilder,
  TrayBloc Function()? trayBuilder,
  BatteryBloc Function()? batteryBuilder,
  WorkspacesBloc Function()? workspacesBuilder,
  MediaBloc Function()? mediaBuilder,
  Duration settle = Duration.zero,
}) async {
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SettingsBloc(settings)),
        BlocProvider(create: (_) => SessionBloc()),
        BlocProvider(create: (_) => OutputsBloc()),
      ],
      child: TricksterLocalizationScope(
        locale: locale,
        child: ModuleScope(
          clockBuilder: clockBuilder ?? ClockBloc.new,
          cpuBuilder:
              cpuBuilder ?? () => CpuBloc(initial: const CpuSample(0.42)),
          gpuBuilder: gpuBuilder ?? () => GpuBloc(initial: const GpuState()),
          trayBuilder:
              trayBuilder ?? () => TrayBloc(initial: const TrayState()),
          batteryBuilder:
              batteryBuilder ??
              () => BatteryBloc(
                initial: const BatteryStatus(capacity: 87, charging: true),
              ),
          workspacesBuilder:
              workspacesBuilder ??
              () => WorkspacesBloc(
                initial: const WorkspacesState(harnessWorkspaces),
              ),
          mediaBuilder:
              mediaBuilder ??
              () => MediaBloc(initial: MprisPlaybackState.unavailable()),
          child: wallpaperAccent == null
              ? TricksterBarStrip(
                  side: side,
                  thickness: thickness,
                  output: output,
                  outputs: outputs,
                )
              : WallpaperAccentScope(
                  notifier: wallpaperAccent,
                  child: TricksterBarStrip(
                    side: side,
                    thickness: thickness,
                    output: output,
                    outputs: outputs,
                  ),
                ),
        ),
      ),
    ),
  );
  if (settle > Duration.zero) {
    await tester.pump(settle);
  }
}
