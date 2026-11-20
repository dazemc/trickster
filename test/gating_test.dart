import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/observer.dart';
import 'package:trickster/src/state/seat_idle_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';

import 'support/strip_harness.dart';

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

bool _created(List<String> lines, String bloc) =>
    lines.any((line) => line.startsWith('bloc+ ') && line.contains(bloc));

class _RecordingCpuSampler extends CpuSampler {
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  bool? startedPaused;

  @override
  void start({bool paused = false}) {
    starts += 1;
    startedPaused = paused;
  }

  @override
  void pause() {
    pauses += 1;
  }

  @override
  void resume() {
    resumes += 1;
  }
}

class _RecordingGpuSampler extends GpuSampler {
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  bool? startedPaused;

  @override
  void start({bool paused = false}) {
    starts += 1;
    startedPaused = paused;
  }

  @override
  void pause() {
    pauses += 1;
  }

  @override
  void resume() {
    resumes += 1;
  }
}

void main() {
  testWidgets('disabled modules build no blocs and render nothing', (
    tester,
  ) async {
    final lines = <String>[];
    final previous = Bloc.observer;
    Bloc.observer = TricksterObserver(log: lines.add);
    try {
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['clock']),
        settle: const Duration(milliseconds: 500),
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
    expect(_created(lines, 'OpencodeBloc'), isFalse);
    expect(
      lines.any(
        (line) =>
            line.contains('CpuBloc') ||
            line.contains('GpuBloc') ||
            line.contains('TrayBloc') ||
            line.contains('BatteryBloc') ||
            line.contains('WorkspacesBloc') ||
            line.contains('MediaBloc') ||
            line.contains('OpencodeBloc'),
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
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['clock']),
        cpuBuilder: () => _CloseNotingCpuBloc(
          initial: const CpuSample(0.42),
          onClosed: () => cpuClosed = true,
        ),
        settle: const Duration(milliseconds: 500),
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

  testWidgets('seat idle pauses cpu and gpu but the clock keeps ticking', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final cpu = _RecordingCpuSampler();
    final gpu = _RecordingGpuSampler();
    var clockNow = 0;
    final clock = ClockBloc(
      now: () => DateTime.fromMillisecondsSinceEpoch(clockNow++ * 1000),
      tick: const Duration(seconds: 1),
    );

    await pumpBarHarness(
      tester,
      seatIdleChanges: changes.stream,
      clockBuilder: () => clock,
      cpuBuilder: () => CpuBloc(sampler: cpu)..add(const CpuStarted()),
      gpuBuilder: () => GpuBloc(sampler: gpu)..add(const GpuStarted()),
      settle: const Duration(milliseconds: 100),
    );
    final before = clock.state.now;

    changes.add(true);
    await tester.pump();
    expect(cpu.pauses, 1);
    expect(gpu.pauses, 1);

    // A duplicate idle notification is a no-op: one pause per transition.
    changes.add(true);
    await tester.pump();
    expect(cpu.pauses, 1);
    expect(gpu.pauses, 1);

    // The clock owns its own timer and is deliberately outside the idle
    // gate. One tick proves it keeps running while the samplers are paused.
    await tester.pump(const Duration(seconds: 1));
    expect(clock.state.now, isNot(before));
    expect(cpu.pauses, 1);
    expect(gpu.pauses, 1);

    changes.add(false);
    await tester.pump();
    expect(cpu.resumes, 1);
    expect(gpu.resumes, 1);
  });

  testWidgets('idle transitions create no disabled module blocs', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final lines = <String>[];
    final previous = Bloc.observer;
    Bloc.observer = TricksterObserver(log: lines.add);
    try {
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['clock']),
        seatIdleChanges: changes.stream,
        settle: const Duration(milliseconds: 100),
      );
      changes.add(true);
      await tester.pump();
      changes.add(false);
      await tester.pump();
    } finally {
      Bloc.observer = previous;
    }

    expect(_created(lines, 'CpuBloc'), isFalse);
    expect(_created(lines, 'GpuBloc'), isFalse);
    expect(_created(lines, 'SeatIdleBloc'), isFalse);
    expect(find.byType(CpuPill), findsNothing);
  });

  testWidgets('initial idle seeds both samplers paused', (tester) async {
    final cpu = _RecordingCpuSampler();
    final gpu = _RecordingGpuSampler();
    await pumpBarHarness(
      tester,
      initialSeatIdle: const SeatIdleState(idle: true),
      cpuSamplerBuilder: () => cpu,
      gpuSamplerBuilder: () => gpu,
      settle: const Duration(milliseconds: 100),
    );

    expect(cpu.starts, 1);
    expect(gpu.starts, 1);
    expect(cpu.startedPaused, isTrue);
    expect(gpu.startedPaused, isTrue);
    expect(cpu.pauses, 0);
    expect(gpu.pauses, 0);
  });

  testWidgets('enabling a sampler module while idle starts it paused', (
    tester,
  ) async {
    final cpu = _RecordingCpuSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock']),
      initialSeatIdle: const SeatIdleState(idle: true),
      cpuSamplerBuilder: () => cpu,
      settle: const Duration(milliseconds: 100),
    );
    expect(cpu.starts, 0);

    final settingsBloc = tester
        .element(find.byType(TricksterBarStrip))
        .read<SettingsBloc>();
    settingsBloc.add(const SettingsModulesChanged(['clock', 'cpu']));
    await tester.pump();
    await tester.pump();

    expect(cpu.starts, 1);
    expect(cpu.startedPaused, isTrue);
  });

  testWidgets('removing modules while idle keeps a later resume harmless', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final cpu = _RecordingCpuSampler();
    final gpu = _RecordingGpuSampler();
    await pumpBarHarness(
      tester,
      initialSeatIdle: const SeatIdleState(idle: true),
      seatIdleChanges: changes.stream,
      cpuSamplerBuilder: () => cpu,
      gpuSamplerBuilder: () => gpu,
      settle: const Duration(milliseconds: 100),
    );

    final settingsBloc = tester
        .element(find.byType(TricksterBarStrip))
        .read<SettingsBloc>();
    settingsBloc.add(const SettingsModulesChanged(['clock']));
    await tester.pump();
    await tester.pump();

    changes.add(false);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CpuPill), findsNothing);
  });

  testWidgets('cpu-only idle dispatches only the cpu events', (tester) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final cpu = _RecordingCpuSampler();
    final gpu = _RecordingGpuSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'cpu']),
      seatIdleChanges: changes.stream,
      cpuSamplerBuilder: () => cpu,
      gpuSamplerBuilder: () => gpu,
      settle: const Duration(milliseconds: 100),
    );

    changes.add(true);
    await tester.pump();
    changes.add(false);
    await tester.pump();
    expect(cpu.pauses, 1);
    expect(cpu.resumes, 1);
    expect(gpu.pauses, 0);
    expect(gpu.resumes, 0);
  });

  testWidgets('gpu-only idle dispatches only the gpu events', (tester) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final cpu = _RecordingCpuSampler();
    final gpu = _RecordingGpuSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'gpu']),
      seatIdleChanges: changes.stream,
      cpuSamplerBuilder: () => cpu,
      gpuSamplerBuilder: () => gpu,
      settle: const Duration(milliseconds: 100),
    );

    changes.add(true);
    await tester.pump();
    changes.add(false);
    await tester.pump();
    expect(gpu.pauses, 1);
    expect(gpu.resumes, 1);
    expect(cpu.pauses, 0);
    expect(cpu.resumes, 0);
  });
}
