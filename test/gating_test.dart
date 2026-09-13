import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/module_scope.dart';
import 'package:trickster/src/state/observer.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

const _workspaces = [
  Workspace(id: '1', name: '1', focused: true),
  Workspace(id: '2', name: '2', urgent: true),
];

/// Records that [close] was invoked without awaiting it: provider disposal
/// calls `close()` unawaited, and awaiting a bloc close inside FakeAsync
/// hangs on the bloc's internal event pipeline. The flag proves disposal
/// ran; unit tests prove disposal releases samplers.
class _CloseNotingCpuBloc extends CpuBloc {
  _CloseNotingCpuBloc({required super.initial, required this.onClosed});

  final void Function() onClosed;

  @override
  Future<void> close() {
    onClosed();
    return super.close();
  }
}

/// Pumps the real production nesting — config providers above a
/// [ModuleScope] above the strip — with seeded module states so no real
/// sampler starts. Seeded builders stand in for the production `Started`
/// path; gating (which providers exist) is identical either way.
Future<void> _pumpGated(
  WidgetTester tester, {
  BarSettings settings = const BarSettings(),
  CpuBloc Function()? cpuBuilder,
}) async {
  // States are seeded via constructors, never via events: awaiting the
  // real event loop (pumpEventQueue) inside FakeAsync hangs forever.
  // Providers own their blocs (create, not value): provider disposal closes
  // blocs unawaited, while awaiting close() in a widget test deadlocks on
  // the bloc's internal event pipeline.
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SettingsBloc(settings)),
        BlocProvider(create: (_) => SessionBloc()),
        BlocProvider(create: (_) => OutputsBloc()),
      ],
      child: Localizations(
        locale: const Locale('en', 'US'),
        delegates: const [GlobalWidgetsLocalizations.delegate],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ModuleScope(
            cpuBuilder:
                cpuBuilder ?? () => CpuBloc(initial: const CpuSample(0.42)),
            gpuBuilder: () => GpuBloc(initial: const GpuState()),
            trayBuilder: () => TrayBloc(initial: const TrayState()),
            batteryBuilder: () => BatteryBloc(
              initial: const BatteryStatus(capacity: 87, charging: true),
            ),
            workspacesBuilder: () => WorkspacesBloc(
              initial: const WorkspacesState(_workspaces),
            ),
            mediaBuilder: () => MediaBloc(
              initial: MprisPlaybackState.unavailable(),
            ),
            child: const TricksterBarStrip(side: SystemBarSide.top),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

bool _created(List<String> lines, String bloc) => lines.any(
  (line) => line.startsWith('bloc+ ') && line.contains(bloc),
);

void main() {
  testWidgets('disabled modules build no blocs and render nothing', (
    tester,
  ) async {
    final lines = <String>[];
    final previous = Bloc.observer;
    Bloc.observer = TricksterObserver(log: lines.add);
    try {
      await _pumpGated(
        tester,
        settings: const BarSettings(modules: ['clock']),
      );
    } finally {
      Bloc.observer = previous;
    }

    expect(find.byType(ClockPill), findsOneWidget);
    expect(find.byType(CpuPill), findsNothing);
    expect(find.byType(BatteryPill), findsNothing);
    expect(find.byType(WorkspacesPill), findsNothing);

    // The transcript is the silence instrument: no bloc, hence no
    // subscription and no timer, for anything not configured.
    expect(_created(lines, 'ClockBloc'), isTrue);
    expect(_created(lines, 'CpuBloc'), isFalse);
    expect(_created(lines, 'GpuBloc'), isFalse);
    expect(_created(lines, 'TrayBloc'), isFalse);
    expect(_created(lines, 'BatteryBloc'), isFalse);
    expect(_created(lines, 'WorkspacesBloc'), isFalse);
    expect(_created(lines, 'MediaBloc'), isFalse);
    expect(
      lines.any(
        (line) =>
            line.contains('CpuBloc') ||
            line.contains('GpuBloc') ||
            line.contains('TrayBloc') ||
            line.contains('BatteryBloc') ||
            line.contains('WorkspacesBloc') ||
            line.contains('MediaBloc'),
      ),
      isFalse,
    );
  });

  testWidgets('enabling a module creates its bloc; disabling closes it', (
    tester,
  ) async {
    final lines = <String>[];
    final previous = Bloc.observer;
    Bloc.observer = TricksterObserver(log: lines.add);
    var cpuClosed = false;
    try {
      await _pumpGated(
        tester,
        settings: const BarSettings(modules: ['clock']),
        cpuBuilder: () => _CloseNotingCpuBloc(
          initial: const CpuSample(0.42),
          onClosed: () => cpuClosed = true,
        ),
      );
      expect(find.byType(CpuPill), findsNothing);

      final settingsBloc = tester
          .element(find.byType(TricksterBarStrip))
          .read<SettingsBloc>();
      lines.clear();
      settingsBloc.add(const SettingsModulesChanged(['clock', 'cpu']));
      await tester.pump();
      await tester.pump();

      expect(_created(lines, 'CpuBloc'), isTrue);
      expect(find.byType(CpuPill), findsOneWidget);

      lines.clear();
      settingsBloc.add(const SettingsModulesChanged(['clock']));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Removal from the tree is the disposal: the provider closed the
      // bloc (flag), the pill is gone, and no new bloc was created.
      // (`bloc-` itself is unassertable here — the close future only
      // completes on a real event loop, which FakeAsync never gives.)
      expect(cpuClosed, isTrue);
      expect(find.byType(CpuPill), findsNothing);
      expect(_created(lines, 'CpuBloc'), isFalse);
    } finally {
      Bloc.observer = previous;
    }
  });
}
