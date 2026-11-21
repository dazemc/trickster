import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/services/opencode.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/capabilities_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/opencode_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

class FakeCpuSampler extends CpuSampler {
  final controller = StreamController<CpuSample>.broadcast();

  var disposed = false;
  var disposes = 0;
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  bool? startedPaused;

  @override
  Stream<CpuSample> get snapshots => controller.stream;

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

  @override
  void dispose() {
    disposed = true;
    disposes += 1;
    controller.close();
  }
}

class FakeBatterySampler extends BatterySampler {
  final controller = StreamController<BatteryStatus>.broadcast();

  var disposed = false;
  var disposes = 0;
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  bool? startedPaused;

  @override
  Stream<BatteryStatus> get snapshots => controller.stream;

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

  @override
  void dispose() {
    disposed = true;
    disposes += 1;
    controller.close();
  }
}

class FakeGpuSampler extends GpuSampler {
  final controller = StreamController<List<GpuLoad>>.broadcast();

  var disposed = false;
  var disposes = 0;
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  bool? startedPaused;

  @override
  Stream<List<GpuLoad>> get snapshots => controller.stream;

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

  @override
  Future<void> dispose() async {
    disposed = true;
    disposes += 1;
    await controller.close();
  }
}

class FakeMonitor extends WorkspaceMonitor {
  final controller = StreamController<List<Workspace>>.broadcast();

  var disposed = false;
  var disposes = 0;
  var starts = 0;
  var focusResult = true;
  final focused = <Workspace>[];

  @override
  Stream<List<Workspace>> get snapshots => controller.stream;

  @override
  Future<void> start() async {
    starts += 1;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    disposes += 1;
    await controller.close();
  }

  @override
  Future<bool> focusWorkspace(Workspace workspace) async {
    focused.add(workspace);
    return focusResult;
  }
}

class FakeStatusNotifierService implements StatusNotifierClient {
  final controller = StreamController<List<SystemTrayItem>>.broadcast();

  var disposed = false;
  var disposes = 0;
  var starts = 0;
  var activateResult = true;
  final activations = <(SystemTrayItem, Offset)>[];
  List<SystemTrayMenuEntry>? menuEntries;
  final menuActivations = <(SystemTrayItem, int)>[];

  @override
  Stream<List<SystemTrayItem>> get snapshots => controller.stream;

  @override
  List<SystemTrayItem> get current => const <SystemTrayItem>[];

  @override
  Future<void> start() async {
    starts += 1;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    disposes += 1;
    await controller.close();
  }

  @override
  Future<bool> invoke(
    SystemTrayItem item,
    SystemTrayAction action,
    Offset position,
  ) async {
    activations.add((item, position));
    return activateResult;
  }

  @override
  Future<List<SystemTrayMenuEntry>?> loadMenu(SystemTrayItem item) async =>
      menuEntries;

  @override
  Future<bool> activateMenuEntry(SystemTrayItem item, int entryId) async {
    menuActivations.add((item, entryId));
    return true;
  }
}

class FakeMediaPlayerService extends MediaPlayerService {
  final controller = StreamController<MprisPlaybackState>.broadcast();

  var disposed = false;
  var disposes = 0;
  var starts = 0;
  var recoveryPauses = 0;
  var recoveryResumes = 0;
  bool? startedPaused;
  final calls = <String>[];

  @override
  Stream<MprisPlaybackState> get snapshots => controller.stream;

  @override
  Future<void> start({bool paused = false}) async {
    starts += 1;
    startedPaused = paused;
  }

  @override
  void pauseRecovery() {
    recoveryPauses += 1;
  }

  @override
  Future<void> resumeRecovery() async {
    recoveryResumes += 1;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    disposes += 1;
    await controller.close();
  }

  @override
  Future<void> playPause() async => calls.add('playPause');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');
}

class FakeOpencodeSampler extends OpencodeSampler {
  FakeOpencodeSampler() : super(statePath: '/nonexistent/trickster-oc.json');

  final controller = StreamController<OpencodeUsage>.broadcast();

  var disposed = false;
  var disposes = 0;
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  var refreshes = 0;
  bool? startedPaused;

  @override
  Stream<OpencodeUsage> get snapshots => controller.stream;

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

  @override
  Future<void> refresh() async {
    refreshes += 1;
  }

  @override
  void dispose() {
    disposed = true;
    disposes += 1;
    controller.close();
  }
}

void main() {
  group('CpuBloc', () {
    late FakeCpuSampler fake;

    blocTest<CpuBloc, CpuSample>(
      'started then sampled emits the sample',
      build: () {
        fake = FakeCpuSampler();
        return CpuBloc(sampler: fake);
      },
      act: (bloc) async {
        bloc.add(const CpuStarted());
        await pumpEventQueue();
        fake.controller.add(const CpuSample(0.5));
      },
      expect: () => const [CpuSample(0.5)],
    );

    test('stopped is terminal and close does not dispose twice', () async {
      final fake = FakeCpuSampler();
      final bloc = CpuBloc(sampler: fake);
      final seen = <CpuSample>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const CpuStarted());
      await pumpEventQueue();
      bloc.add(const CpuStopped());
      await pumpEventQueue();

      expect(fake.disposes, 1);
      expect(fake.controller.isClosed, isTrue);

      bloc.add(const CpuSampled(CpuSample(0.9)));
      bloc.add(const CpuStarted(paused: true));
      bloc.add(const CpuPaused());
      bloc.add(const CpuResumed());
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(fake.starts, 1);
      expect(fake.pauses, 0);
      expect(fake.resumes, 0);
      expect(fake.disposes, 1);

      await bloc.close();
      expect(fake.disposes, 1);
      await subscription.cancel();
    });

    blocTest<CpuBloc, CpuSample>(
      'seat pauses and resumes the sampler without emitting',
      build: () {
        fake = FakeCpuSampler();
        return CpuBloc(sampler: fake);
      },
      act: (bloc) async {
        bloc.add(const CpuStarted());
        await pumpEventQueue();
        bloc.add(const CpuPaused());
        await pumpEventQueue();
        bloc.add(const CpuResumed());
        await pumpEventQueue();
      },
      expect: () => const <CpuSample>[],
      verify: (_) {
        expect(fake.pauses, 1);
        expect(fake.resumes, 1);
      },
    );

    blocTest<CpuBloc, CpuSample>(
      'a module started while idle seeds a paused sampler',
      build: () {
        fake = FakeCpuSampler();
        return CpuBloc(sampler: fake);
      },
      act: (bloc) async {
        bloc.add(const CpuStarted(paused: true));
        await pumpEventQueue();
      },
      expect: () => const <CpuSample>[],
      verify: (_) => expect(fake.startedPaused, isTrue),
    );

    test('cpu json round-trips', () {
      const sample = CpuSample(0.25, name: 'AMD Ryzen 9 5950X');
      final decoded = CpuSample.fromJson(
        Map<String, dynamic>.from(sample.toJson()),
      );
      expect(decoded.current, 0.25);
      expect(decoded.name, 'AMD Ryzen 9 5950X');
      final series = const CpuSample(null).append(0.25).append(0.75);
      final decodedSeries = CpuSample.fromJson(
        Map<String, dynamic>.from(series.toJson()),
      );
      expect(decodedSeries.current, 0.75);
      expect(decodedSeries.history, [0.25, 0.75]);
    });

    test('cpu name parses from cpuinfo with a null fallback', () {
      const cpuInfo = '''
processor\t: 0
vendor_id\t: AuthenticAMD
model name\t: AMD Ryzen 9 5950X 16-Core Processor
cpu MHz\t\t: 3400.000
''';
      expect(parseCpuModelName(cpuInfo), 'AMD Ryzen 9 5950X 16-Core Processor');
      expect(parseCpuModelName('processor\t: 0\n'), isNull);
      expect(parseCpuModelName('model name\t: \n'), isNull);
    });

    test('cpu series preserves the device name', () {
      final sample = const CpuSample(
        null,
        name: 'AMD Ryzen 9 5950X',
      ).append(0.5).append(0.75);
      expect(sample.name, 'AMD Ryzen 9 5950X');
    });

    test('cpu series keeps the cap and appends newest last', () {
      var sample = const CpuSample(null);
      for (var i = 0; i < CpuSample.capacity + 5; i++) {
        sample = sample.append(i / 100);
      }
      expect(sample.history.length, CpuSample.capacity);
      expect(sample.history.first, closeTo(0.05, 1e-9));
      expect(
        sample.history.last,
        closeTo((CpuSample.capacity + 4) / 100, 1e-9),
      );
      expect(sample.current, sample.history.last);
    });
  });

  group('BatteryBloc', () {
    test('started then sampled emits the status', () async {
      final sampler = FakeBatterySampler();
      final bloc = BatteryBloc(sampler: sampler);
      try {
        bloc.add(const BatteryStarted());
        await pumpEventQueue();
        sampler.controller.add(
          const BatteryStatus(capacity: 87, charging: true),
        );
        await expectLater(
          bloc.stream,
          emits(
            predicate<BatteryStatus>((s) => s.capacity == 87 && s.charging),
          ),
        );
      } finally {
        await bloc.close();
      }
      expect(sampler.disposed, isTrue);
    });

    test('stopped is terminal and close does not dispose twice', () async {
      final sampler = FakeBatterySampler();
      final bloc = BatteryBloc(sampler: sampler);
      final seen = <BatteryStatus>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const BatteryStarted());
      await pumpEventQueue();
      bloc.add(const BatteryStopped());
      await pumpEventQueue();

      expect(sampler.disposes, 1);
      expect(sampler.controller.isClosed, isTrue);

      bloc.add(const BatterySampled(BatteryStatus(capacity: 90)));
      bloc.add(const BatteryStarted(paused: true));
      bloc.add(const BatteryPaused());
      bloc.add(const BatteryResumed());
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(sampler.starts, 1);
      expect(sampler.pauses, 0);
      expect(sampler.resumes, 0);
      expect(sampler.disposes, 1);

      await bloc.close();
      expect(sampler.disposes, 1);
      await subscription.cancel();
    });

    test('battery json round-trips', () {
      const status = BatteryStatus(capacity: 50, charging: false);
      final decoded = BatteryStatus.fromJson(
        Map<String, dynamic>.from(status.toJson()),
      );
      expect(decoded.capacity, 50);
      expect(decoded.charging, isFalse);
    });
  });

  group('GpuBloc', () {
    const load = GpuLoad(id: 'card0', label: 'AMD0', usage: 0.4);

    test('started then sampled emits the loads', () async {
      final sampler = FakeGpuSampler();
      final bloc = GpuBloc(sampler: sampler);
      try {
        bloc.add(const GpuStarted());
        await pumpEventQueue();
        sampler.controller.add(const [load]);
        await expectLater(bloc.stream, emits(const GpuState([load])));
      } finally {
        await bloc.close();
      }
      expect(sampler.disposed, isTrue);
    });

    test('seat pauses and resumes the gpu sampler without emitting', () async {
      final sampler = FakeGpuSampler();
      final bloc = GpuBloc(sampler: sampler);
      try {
        bloc.add(const GpuStarted());
        await pumpEventQueue();
        bloc.add(const GpuPaused());
        await pumpEventQueue();
        bloc.add(const GpuResumed());
        await pumpEventQueue();
        expect(sampler.pauses, 1);
        expect(sampler.resumes, 1);
      } finally {
        await bloc.close();
      }
    });

    test('stopped is terminal and close does not dispose twice', () async {
      final sampler = FakeGpuSampler();
      final bloc = GpuBloc(sampler: sampler);
      final seen = <GpuState>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const GpuStarted());
      await pumpEventQueue();
      bloc.add(const GpuStopped());
      await pumpEventQueue();

      expect(sampler.disposes, 1);
      expect(sampler.controller.isClosed, isTrue);

      bloc.add(const GpuSampled(<GpuLoad>[load]));
      bloc.add(const GpuStarted(paused: true));
      bloc.add(const GpuPaused());
      bloc.add(const GpuResumed());
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(sampler.starts, 1);
      expect(sampler.pauses, 0);
      expect(sampler.resumes, 0);
      expect(sampler.disposes, 1);

      await bloc.close();
      expect(sampler.disposes, 1);
      await subscription.cancel();
    });

    test('gpu state json round-trips', () {
      final state = GpuState([
        const GpuLoad(id: 'card0', label: 'AMD0').append(0.4).append(0.5),
      ]);
      final decoded = GpuState.fromJson(
        Map<String, dynamic>.from(state.toJson()),
      );
      expect(decoded, state);
      expect(decoded.loads.single.history, [0.4, 0.5]);
    });
  });

  group('WorkspacesBloc', () {
    const first = Workspace(id: '1', name: '1', focused: true);

    late FakeMonitor monitor;
    late List<String> lines;

    test('started then sampled emits the list', () async {
      final monitor = FakeMonitor();
      final bloc = WorkspacesBloc(monitor: monitor);
      try {
        bloc.add(const WorkspacesStarted());
        await pumpEventQueue();
        monitor.controller.add(const [first]);
        await expectLater(bloc.stream, emits(const WorkspacesState([first])));
      } finally {
        await bloc.close();
      }
      expect(monitor.disposed, isTrue);
    });

    test('stopped is terminal and close does not dispose twice', () async {
      final monitor = FakeMonitor();
      final bloc = WorkspacesBloc(monitor: monitor);
      final seen = <WorkspacesState>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const WorkspacesStarted());
      await pumpEventQueue();
      bloc.add(const WorkspacesStopped());
      await pumpEventQueue();

      expect(monitor.disposes, 1);
      expect(monitor.controller.isClosed, isTrue);

      bloc.add(const WorkspacesSampled(<Workspace>[first]));
      bloc.add(const WorkspacesStarted());
      bloc.add(const WorkspacesFocusRequested(Workspace(id: '2', name: 'web')));
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(monitor.starts, 1);
      expect(monitor.focused, isEmpty);
      expect(monitor.disposes, 1);

      await bloc.close();
      expect(monitor.disposes, 1);
      await subscription.cancel();
    });

    test('workspaces sort numerically, then by name', () {
      final sorted = sortedWorkspaces(const [
        Workspace(id: '10', name: '10'),
        Workspace(id: 'web', name: 'web'),
        Workspace(id: '2', name: '2'),
        Workspace(id: '1', name: '1'),
      ]);
      expect(sorted.map((workspace) => workspace.id), ['1', '2', '10', 'web']);
    });

    test('sampled workspaces are ordered before emitting', () async {
      final monitor = FakeMonitor();
      final bloc = WorkspacesBloc(monitor: monitor);
      try {
        bloc.add(const WorkspacesStarted());
        await pumpEventQueue();
        monitor.controller.add(const [
          Workspace(id: '10', name: '10'),
          Workspace(id: '2', name: '2'),
        ]);
        await expectLater(
          bloc.stream,
          emits(
            const WorkspacesState([
              Workspace(id: '2', name: '2'),
              Workspace(id: '10', name: '10'),
            ]),
          ),
        );
      } finally {
        await bloc.close();
      }
    });

    blocTest<WorkspacesBloc, WorkspacesState>(
      'focus success forwards to the monitor and emits nothing',
      build: () {
        monitor = FakeMonitor();
        lines = <String>[];
        return WorkspacesBloc(monitor: monitor, log: lines.add);
      },
      act: (bloc) => bloc.add(
        const WorkspacesFocusRequested(Workspace(id: '2', name: 'web')),
      ),
      expect: () => const <WorkspacesState>[],
      verify: (_) {
        expect(monitor.focused.single.id, '2');
        expect(lines, isEmpty);
      },
    );

    blocTest<WorkspacesBloc, WorkspacesState>(
      'focus failure logs and keeps state',
      build: () {
        monitor = FakeMonitor()..focusResult = false;
        lines = <String>[];
        return WorkspacesBloc(monitor: monitor, log: lines.add);
      },
      act: (bloc) => bloc.add(
        const WorkspacesFocusRequested(Workspace(id: '2', name: 'web')),
      ),
      expect: () => const <WorkspacesState>[],
      verify: (_) {
        expect(monitor.focused.single.id, '2');
        expect(lines.single, contains('web'));
      },
    );

    test('workspace json round-trips', () {
      const workspace = Workspace(
        id: '2',
        name: 'web',
        focused: false,
        urgent: true,
        occupied: true,
      );
      final decoded = Workspace.fromJson(
        Map<String, dynamic>.from(workspace.toJson()),
      );
      expect(decoded.id, '2');
      expect(decoded.name, 'web');
      expect(decoded.urgent, isTrue);
      expect(decoded.occupied, isTrue);
      final list = workspacesFromJson(workspacesToJson([workspace]).toList());
      expect(list.length, 1);
      expect(list.first.id, '2');
    });
  });

  group('TrayBloc', () {
    const item = SystemTrayItem(
      id: 'status-notifier:org.example.Tray:/StatusNotifierItem',
      title: 'Test Item',
      status: SystemTrayStatus.active,
      iconName: 'test-icon',
      iconThemePath: '',
      iconPixmap: null,
      menuAvailable: false,
      primaryOpensMenu: false,
    );

    test('started then sampled emits the items', () async {
      final service = FakeStatusNotifierService();
      final bloc = TrayBloc(service: service);
      try {
        bloc.add(const TrayStarted());
        await pumpEventQueue();
        service.controller.add(const [item]);
        await expectLater(bloc.stream, emits(const TrayState([item])));
      } finally {
        await bloc.close();
      }
      expect(service.disposed, isTrue);
    });

    test('stopped is terminal and close does not dispose twice', () async {
      final service = FakeStatusNotifierService();
      final bloc = TrayBloc(service: service);
      final seen = <TrayState>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const TrayStarted());
      await pumpEventQueue();
      bloc.add(const TrayStopped());
      await pumpEventQueue();

      expect(service.disposes, 1);
      expect(service.controller.isClosed, isTrue);

      bloc.add(const TraySampled(<SystemTrayItem>[item]));
      bloc.add(const TrayStarted());
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(service.starts, 1);
      expect(service.disposes, 1);

      await bloc.close();
      expect(service.disposes, 1);
      await subscription.cancel();
    });

    test('activation forwards the item and pointer position', () async {
      final service = FakeStatusNotifierService();
      final bloc = TrayBloc(service: service);
      try {
        final invoked = await bloc.invoke(
          item,
          SystemTrayAction.activate,
          const Offset(12, 34),
        );
        expect(invoked, isTrue);
        expect(service.activations.single.$1, item);
        expect(service.activations.single.$2, const Offset(12, 34));
      } finally {
        await bloc.close();
      }
    });

    test('menu loading and entry activation pass through', () async {
      const entry = SystemTrayMenuEntry(
        id: 7,
        label: 'Open',
        enabled: true,
        visible: true,
        separator: false,
        toggleType: SystemTrayMenuToggleType.none,
        toggleState: 0,
        destructive: false,
        children: [],
      );
      final service = FakeStatusNotifierService()..menuEntries = const [entry];
      final bloc = TrayBloc(service: service);
      try {
        final entries = await bloc.loadMenu(item);
        expect(entries!.single, entry);
        expect(await bloc.activateMenuEntry(item, 7), isTrue);
        expect(service.menuActivations.single.$1, item);
        expect(service.menuActivations.single.$2, 7);
      } finally {
        await bloc.close();
      }
    });

    test('tray state json round-trips', () {
      const state = TrayState([item]);
      final decoded = TrayState.fromJson(
        Map<String, dynamic>.from(state.toJson()),
      );
      expect(decoded, state);
      expect(decoded.items.single.title, 'Test Item');
      expect(decoded.items.single.status, SystemTrayStatus.active);
    });
  });

  group('ClockBloc', () {
    test('ticks with the injected clock', () async {
      var tick = DateTime(2026, 9, 12, 20, 0);
      final bloc = ClockBloc(
        now: () => tick,
        tick: const Duration(milliseconds: 10),
      );
      try {
        expect(bloc.state.now, DateTime(2026, 9, 12, 20, 0));
        tick = DateTime(2026, 9, 12, 20, 1);
        await expectLater(
          bloc.stream,
          emits(
            predicate<ClockState>((s) => s.now == DateTime(2026, 9, 12, 20, 1)),
          ),
        );
      } finally {
        await bloc.close();
      }
    });

    test('clock json round-trips', () {
      final state = ClockState(DateTime(2026, 9, 12, 20, 30));
      final decoded = ClockState.fromJson(
        Map<String, dynamic>.from(state.toJson()),
      );
      expect(decoded.now, state.now);
    });
  });

  group('MediaBloc', () {
    final playback = MprisPlaybackState(
      serviceName: 'org.mpris.MediaPlayer2.fake',
      identity: 'Fake Player',
      title: 'Test Song',
      artists: <String>['Test Artist'],
      album: 'Test Album',
      artUrl: '',
      length: Duration(seconds: 180),
      position: Duration(seconds: 42),
      observedAt: _epoch,
      status: MprisPlaybackStatus.playing,
      canGoNext: true,
      canGoPrevious: true,
      canPlay: true,
      canPause: true,
    );

    test('started then sampled emits playback state', () async {
      final service = FakeMediaPlayerService();
      final bloc = MediaBloc(service: service);
      try {
        bloc.add(const MediaStarted());
        await pumpEventQueue();
        service.controller.add(playback);
        await expectLater(bloc.stream, emits(playback));
      } finally {
        await bloc.close();
      }
      expect(service.disposed, isTrue);
    });

    test('stopped is terminal and close does not dispose twice', () async {
      final service = FakeMediaPlayerService();
      final bloc = MediaBloc(service: service);
      final seen = <MprisPlaybackState>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const MediaStarted());
      await pumpEventQueue();
      bloc.add(const MediaStopped());
      await pumpEventQueue();

      expect(service.disposes, 1);
      expect(service.controller.isClosed, isTrue);

      bloc.add(MediaSampled(playback));
      bloc.add(const MediaStarted(paused: true));
      bloc.add(const MediaIdleChanged(false));
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(service.starts, 1);
      expect(service.recoveryResumes, 0);
      expect(service.recoveryPauses, 0);
      expect(service.disposes, 1);

      await bloc.close();
      expect(service.disposes, 1);
      await subscription.cancel();
    });

    test('idle changes gate recovery without stopping snapshots', () async {
      final service = FakeMediaPlayerService();
      final bloc = MediaBloc(service: service);
      try {
        bloc.add(const MediaStarted(paused: true));
        await pumpEventQueue();
        expect(service.starts, 1);
        expect(service.startedPaused, isTrue);

        bloc.add(const MediaIdleChanged(false));
        await pumpEventQueue();
        expect(service.recoveryResumes, 1);

        service.controller.add(playback);
        await pumpEventQueue();
        expect(bloc.state, playback);

        bloc.add(const MediaIdleChanged(true));
        await pumpEventQueue();
        expect(service.recoveryPauses, 1);
        expect(bloc.state, playback);
      } finally {
        await bloc.close();
      }
    });

    test('controls forward to the player service', () async {
      final service = FakeMediaPlayerService();
      final bloc = MediaBloc(service: service);
      try {
        await bloc.playPause();
        await bloc.next();
        await bloc.previous();
        expect(service.calls, <String>['playPause', 'next', 'previous']);
      } finally {
        await bloc.close();
      }
    });
  });

  group('OpencodeBloc', () {
    test('stopped is terminal and close does not dispose twice', () async {
      final sampler = FakeOpencodeSampler();
      final bloc = OpencodeBloc(sampler: sampler);
      final seen = <OpencodeUsage>[];
      final subscription = bloc.stream.listen(seen.add);

      bloc.add(const OpencodeStarted());
      await pumpEventQueue();
      bloc.add(const OpencodeStopped());
      await pumpEventQueue();

      expect(sampler.disposes, 1);
      expect(sampler.controller.isClosed, isTrue);

      bloc.add(const OpencodeSampled(OpencodeUsage(available: true)));
      bloc.add(const OpencodeStarted(paused: true));
      bloc.add(const OpencodePaused());
      bloc.add(const OpencodeResumed());
      bloc.add(const OpencodeRefreshed());
      await pumpEventQueue();

      expect(seen, isEmpty);
      expect(sampler.starts, 1);
      expect(sampler.pauses, 0);
      expect(sampler.resumes, 0);
      expect(sampler.refreshes, 0);
      expect(sampler.disposes, 1);

      await bloc.close();
      expect(sampler.disposes, 1);
      await subscription.cancel();
    });
  });

  group('CapabilitiesBloc', () {
    test('probe reports blur availability both ways', () async {
      final enabled = CapabilitiesBloc(probe: () async => true);
      try {
        enabled.add(const CapabilitiesProbeRequested());
        await expectLater(
          enabled.stream,
          emits(const Capabilities(blur: true)),
        );
      } finally {
        await enabled.close();
      }

      final disabled = CapabilitiesBloc(probe: () async => false);
      try {
        disabled.add(const CapabilitiesProbeRequested());
        await expectLater(
          disabled.stream,
          emits(const Capabilities(blur: false)),
        );
      } finally {
        await disabled.close();
      }
    });

    test('a failed probe reports no blur and json round-trips', () async {
      final failing = CapabilitiesBloc(
        probe: () async => throw StateError('no'),
      );
      try {
        failing.add(const CapabilitiesProbeRequested());
        await expectLater(
          failing.stream,
          emits(const Capabilities(blur: false)),
        );
      } finally {
        await failing.close();
      }
      const state = Capabilities(blur: true);
      expect(
        Capabilities.fromJson(Map<String, dynamic>.from(state.toJson())),
        state,
      );
    });

    test('native capability changes update blur state', () async {
      final changes = StreamController<bool>.broadcast();
      final bloc = CapabilitiesBloc(
        probe: () async => true,
        changes: () => changes.stream,
      );
      try {
        bloc.add(const CapabilitiesProbeRequested());
        await expectLater(bloc.stream, emits(const Capabilities(blur: true)));
        changes.add(false);
        await expectLater(bloc.stream, emits(const Capabilities(blur: false)));
        changes.add(true);
        await expectLater(bloc.stream, emits(const Capabilities(blur: true)));
      } finally {
        await bloc.close();
        await changes.close();
      }
    });
  });

  group('SettingsBloc', () {
    test('the media mode cycle emits and persists the new document', () async {
      final saved = <BarSettings>[];
      final bloc = SettingsBloc(
        const BarSettings(),
        (next) async => saved.add(next),
      );
      addTearDown(bloc.close);

      bloc.add(const SettingsMediaModeChanged(MediaMode.full));

      final state = await bloc.stream.firstWhere(
        (state) => state.media.mode == MediaMode.full,
      );
      expect(state.media.mode, MediaMode.full);
      expect(saved.single.media.mode, MediaMode.full);
    });

    test('a failed save keeps the in-memory mode', () async {
      final bloc = SettingsBloc(
        const BarSettings(),
        (next) async => throw StateError('document is read-only'),
      );
      addTearDown(bloc.close);

      bloc.add(const SettingsMediaModeChanged(MediaMode.compact));

      final state = await bloc.stream.firstWhere(
        (state) => state.media.mode == MediaMode.compact,
      );
      expect(state.media.mode, MediaMode.compact);
    });
  });
}
