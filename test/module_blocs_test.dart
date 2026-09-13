import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

class FakeCpuSampler extends CpuSampler {
  final controller = StreamController<CpuSample>.broadcast();

  var disposed = false;

  @override
  Stream<CpuSample> get snapshots => controller.stream;

  @override
  void start() {}

  @override
  void dispose() {
    disposed = true;
    controller.close();
  }
}

class FakeBatterySampler extends BatterySampler {
  final controller = StreamController<BatteryStatus>.broadcast();

  var disposed = false;

  @override
  Stream<BatteryStatus> get snapshots => controller.stream;

  @override
  void start() {}

  @override
  void dispose() {
    disposed = true;
    controller.close();
  }
}

class FakeGpuSampler extends GpuSampler {
  final controller = StreamController<List<GpuLoad>>.broadcast();

  var disposed = false;

  @override
  Stream<List<GpuLoad>> get snapshots => controller.stream;

  @override
  void start() {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }
}

class FakeMonitor extends WorkspaceMonitor {
  final controller = StreamController<List<Workspace>>.broadcast();

  var disposed = false;
  var focusResult = true;
  final focused = <Workspace>[];

  @override
  Stream<List<Workspace>> get snapshots => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }

  @override
  Future<bool> focusWorkspace(Workspace workspace) async {
    focused.add(workspace);
    return focusResult;
  }
}

class FakeStatusNotifierService extends StatusNotifierService {
  final controller = StreamController<List<SystemTrayItem>>.broadcast();

  var disposed = false;
  var activateResult = true;
  final activations = <(SystemTrayItem, Offset)>[];
  List<SystemTrayMenuEntry>? menuEntries;
  final menuActivations = <(SystemTrayItem, int)>[];

  @override
  Stream<List<SystemTrayItem>> get snapshots => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
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
  final calls = <String>[];

  @override
  Stream<MprisPlaybackState> get snapshots => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }

  @override
  Future<void> playPause() async => calls.add('playPause');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');
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

    blocTest<CpuBloc, CpuSample>(
      'stopped drops later samples',
      build: () {
        fake = FakeCpuSampler();
        return CpuBloc(sampler: fake);
      },
      act: (bloc) async {
        bloc.add(const CpuStarted());
        await pumpEventQueue();
        bloc.add(const CpuStopped());
        await pumpEventQueue();
        fake.controller.add(const CpuSample(0.9));
        await pumpEventQueue();
      },
      expect: () => const <CpuSample>[],
      verify: (_) => expect(fake.disposed, isTrue),
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
}
