import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
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
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/tray_menu.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

/// A layer shell whose surfaces live only inside the test binding.
class SilentLayerShell extends LayerShell {
  SilentLayerShell() : super(channel: const MethodChannel('test/trickster'));

  @override
  Future<int?> openMenuSurface({
    required int barViewId,
    required String side,
  }) async => 1;

  @override
  Future<void> showMenuSurface({required int viewId}) async {}

  @override
  Future<void> closeMenuSurface({required int viewId}) async {}

  @override
  Future<int?> openTooltipSurface({
    required int barViewId,
    required String side,
  }) async => 1;

  @override
  Future<void> showTooltipSurface({required int viewId}) async {}

  @override
  Future<void> closeTooltipSurface({required int viewId}) async {}
}

/// The strip's production band: the layer surface is exactly one strip tall
/// (or wide on a side bar), so pills lay out against the configured
/// thickness rather than the test viewport.
Widget _band(SystemBarSide side, double thickness, String? output) {
  return Align(
    alignment: side.isHorizontal ? Alignment.topCenter : Alignment.centerLeft,
    child: SizedBox(
      width: side.isHorizontal ? double.infinity : thickness,
      height: side.isHorizontal ? thickness : double.infinity,
      child: TricksterBarStrip(
        side: side,
        thickness: thickness,
        output: output,
      ),
    ),
  );
}

/// Wraps [child] in the overlay host blocs the strip always carries, for
/// tests that pump one pill instead of the whole strip.
Widget withOverlayBlocs(Widget child) {
  final shell = SilentLayerShell();
  return BlocProvider<TrayMenuBloc>(
    create: (_) => TrayMenuBloc(layerShell: shell),
    child: BlocProvider<OverlayTooltipBloc>(
      create: (_) => OverlayTooltipBloc(layerShell: shell),
      child: child,
    ),
  );
}

/// Workspaces every harnessed strip renders: one focused, one urgent.
const harnessWorkspaces = [
  Workspace(id: '1', name: '1', output: 'HDMI-A-1', focused: true),
  Workspace(id: '2', name: '2', output: 'HDMI-A-1', urgent: true),
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
  WallpaperAccentBloc? wallpaperAccent,
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
      child: withOverlayBlocs(
        TricksterLocalizationScope(
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
                ? BlocProvider<WallpaperAccentBloc>(
                    create: (_) => WallpaperAccentBloc(watch: false),
                    child: _band(side, thickness, output),
                  )
                : BlocProvider<WallpaperAccentBloc>.value(
                    value: wallpaperAccent,
                    child: _band(side, thickness, output),
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
