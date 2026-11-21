import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/ram.dart';
import 'package:trickster/src/bar/vram.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/opencode.dart';
import 'package:trickster/src/services/ram.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/observer.dart';
import 'package:trickster/src/state/seat_idle_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';

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

class _RecordingRamSampler extends RamSampler {
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

class _RecordingBatterySampler extends BatterySampler {
  _RecordingBatterySampler() : super(interval: const Duration(days: 1));

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

class _RecordingOpencodeSampler extends OpencodeSampler {
  _RecordingOpencodeSampler()
    : super(
        statePath: '/nonexistent/trickster/opencode/service.json',
        interval: const Duration(days: 1),
      );

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

class _RecordingMediaService extends MediaPlayerService {
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  bool? startedPaused;

  @override
  Future<void> start({bool paused = false}) async {
    starts += 1;
    startedPaused = paused;
  }

  @override
  void pauseRecovery() {
    pauses += 1;
  }

  @override
  Future<void> resumeRecovery() async {
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
    var trayBuilds = 0;
    try {
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['clock']),
        trayBuilder: () {
          trayBuilds += 1;
          return TrayBloc(initial: const TrayState());
        },
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
    expect(trayBuilds, 0);
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

  testWidgets('vram-only idle dispatches the shared GPU events', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final gpu = _RecordingGpuSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'vram']),
      seatIdleChanges: changes.stream,
      gpuSamplerBuilder: () => gpu,
      settle: const Duration(milliseconds: 100),
    );

    changes.add(true);
    await tester.pump();
    changes.add(false);
    await tester.pump();
    expect(gpu.starts, 1);
    expect(gpu.pauses, 1);
    expect(gpu.resumes, 1);
  });

  testWidgets('gpu and vram share exactly one GpuBloc', (tester) async {
    var builds = 0;
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'gpu', 'vram']),
      gpuBuilder: () {
        builds += 1;
        return GpuBloc(
          initial: const GpuState([
            GpuLoad(
              id: 'card0',
              label: 'AMD0',
              usage: 0.4,
              memoryUsedBytes: 500,
              memoryTotalBytes: 1000,
            ),
          ]),
        );
      },
      settle: const Duration(milliseconds: 100),
    );
    expect(builds, 1);
    expect(find.byType(GpuPill), findsOneWidget);
    expect(find.byType(VramPill), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('system-bar-gpu-card0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('system-bar-vram-card0')),
      findsOneWidget,
    );
  });

  testWidgets('disabled vram alone builds no GpuBloc or sampler', (
    tester,
  ) async {
    final gpu = _RecordingGpuSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock']),
      gpuSamplerBuilder: () => gpu,
      settle: const Duration(milliseconds: 100),
    );
    expect(gpu.starts, 0);
    expect(find.byType(VramPill), findsNothing);
  });

  testWidgets('ram-only idle dispatches only the ram events', (tester) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final ram = _RecordingRamSampler();
    final cpu = _RecordingCpuSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'ram']),
      seatIdleChanges: changes.stream,
      ramSamplerBuilder: () => ram,
      cpuSamplerBuilder: () => cpu,
      settle: const Duration(milliseconds: 100),
    );

    changes.add(true);
    await tester.pump();
    changes.add(false);
    await tester.pump();
    expect(ram.pauses, 1);
    expect(ram.resumes, 1);
    expect(cpu.pauses, 0);
    expect(cpu.resumes, 0);
  });

  testWidgets('a ram module created while idle starts paused', (tester) async {
    final ram = _RecordingRamSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'ram']),
      initialSeatIdle: const SeatIdleState(idle: true),
      ramSamplerBuilder: () => ram,
      settle: const Duration(milliseconds: 100),
    );
    expect(ram.starts, 1);
    expect(ram.startedPaused, isTrue);
  });

  testWidgets('disabled ram builds no RamBloc or sampler', (tester) async {
    final lines = <String>[];
    final previous = Bloc.observer;
    Bloc.observer = TricksterObserver(log: lines.add);
    final ram = _RecordingRamSampler();
    try {
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['clock']),
        ramSamplerBuilder: () => ram,
        settle: const Duration(milliseconds: 100),
      );
      expect(_created(lines, 'RamBloc'), isFalse);
      expect(ram.starts, 0);
      expect(find.byType(RamPill), findsNothing);
    } finally {
      Bloc.observer = previous;
    }
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

  testWidgets('seat idle pauses battery and opencode once per transition', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final battery = _RecordingBatterySampler();
    final opencode = _RecordingOpencodeSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'battery', 'opencode']),
      seatIdleChanges: changes.stream,
      batterySamplerBuilder: () => battery,
      opencodeSamplerBuilder: () => opencode,
      settle: const Duration(milliseconds: 100),
    );

    changes.add(true);
    await tester.pump();
    expect(battery.pauses, 1);
    expect(opencode.pauses, 1);

    changes.add(true);
    await tester.pump();
    expect(battery.pauses, 1);
    expect(opencode.pauses, 1);

    changes.add(false);
    await tester.pump();
    expect(battery.resumes, 1);
    expect(opencode.resumes, 1);
  });

  testWidgets('seat idle pauses media recovery once per transition', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final media = _RecordingMediaService();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'media']),
      seatIdleChanges: changes.stream,
      mediaServiceBuilder: () => media,
      settle: const Duration(milliseconds: 100),
    );

    expect(media.starts, 1);
    expect(media.startedPaused, isFalse);

    changes.add(true);
    await tester.pump();
    expect(media.pauses, 1);

    changes.add(true);
    await tester.pump();
    expect(media.pauses, 1);

    changes.add(false);
    await tester.pump();
    expect(media.resumes, 1);
  });

  testWidgets('initial idle seeds media recovery paused', (tester) async {
    final media = _RecordingMediaService();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'media']),
      initialSeatIdle: const SeatIdleState(idle: true),
      mediaServiceBuilder: () => media,
      settle: const Duration(milliseconds: 100),
    );

    expect(media.starts, 1);
    expect(media.startedPaused, isTrue);
    expect(media.pauses, 0);
  });

  testWidgets('media recovery is gated only when media is configured', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final media = _RecordingMediaService();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock']),
      initialSeatIdle: const SeatIdleState(idle: true),
      seatIdleChanges: changes.stream,
      mediaServiceBuilder: () => media,
      settle: const Duration(milliseconds: 100),
    );

    changes.add(false);
    await tester.pump();
    changes.add(true);
    await tester.pump();
    expect(media.starts, 0);
    expect(media.pauses, 0);
    expect(media.resumes, 0);
  });

  testWidgets('initial idle seeds battery and opencode paused', (tester) async {
    final battery = _RecordingBatterySampler();
    final opencode = _RecordingOpencodeSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'battery', 'opencode']),
      initialSeatIdle: const SeatIdleState(idle: true),
      batterySamplerBuilder: () => battery,
      opencodeSamplerBuilder: () => opencode,
      settle: const Duration(milliseconds: 100),
    );

    expect(battery.starts, 1);
    expect(opencode.starts, 1);
    expect(battery.startedPaused, isTrue);
    expect(opencode.startedPaused, isTrue);
    expect(battery.pauses, 0);
    expect(opencode.pauses, 0);
  });

  testWidgets('cpu-only idle leaves battery and opencode untouched', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final cpu = _RecordingCpuSampler();
    final battery = _RecordingBatterySampler();
    final opencode = _RecordingOpencodeSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'cpu']),
      seatIdleChanges: changes.stream,
      cpuSamplerBuilder: () => cpu,
      batterySamplerBuilder: () => battery,
      opencodeSamplerBuilder: () => opencode,
      settle: const Duration(milliseconds: 100),
    );

    changes.add(true);
    await tester.pump();
    changes.add(false);
    await tester.pump();
    expect(cpu.pauses, 1);
    expect(cpu.resumes, 1);
    expect(battery.starts, 0);
    expect(opencode.starts, 0);
  });

  testWidgets('removing battery and opencode while idle is harmless', (
    tester,
  ) async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final battery = _RecordingBatterySampler();
    final opencode = _RecordingOpencodeSampler();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'battery', 'opencode']),
      initialSeatIdle: const SeatIdleState(idle: true),
      seatIdleChanges: changes.stream,
      batterySamplerBuilder: () => battery,
      opencodeSamplerBuilder: () => opencode,
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
    expect(battery.starts, 1);
    expect(opencode.starts, 1);
  });
}
