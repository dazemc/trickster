import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/battery.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

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

class FakeMonitor extends WorkspaceMonitor {
  final controller = StreamController<List<Workspace>>.broadcast();

  var disposed = false;

  @override
  Stream<List<Workspace>> get snapshots => controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
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
      expect: () => [
        predicate<CpuSample>((sample) => sample.current == 0.5),
      ],
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
      const sample = CpuSample(0.25);
      expect(
        CpuSample.fromJson(Map<String, dynamic>.from(sample.toJson())),
        isA<CpuSample>(),
      );
      expect(
        CpuSample.fromJson(
          Map<String, dynamic>.from(sample.toJson()),
        ).current,
        0.25,
      );
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
            predicate<BatteryStatus>(
              (s) => s.capacity == 87 && s.charging,
            ),
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

  group('WorkspacesBloc', () {
    const first = Workspace(id: '1', name: '1', focused: true);

    test('started then sampled emits the list', () async {
      final monitor = FakeMonitor();
      final bloc = WorkspacesBloc(monitor: monitor);
      try {
        bloc.add(const WorkspacesStarted());
        await pumpEventQueue();
        monitor.controller.add(const [first]);
        await expectLater(
          bloc.stream,
          emits(
            predicate<List<Workspace>>(
              (list) => list.length == 1 && list.first.id == '1',
            ),
          ),
        );
      } finally {
        await bloc.close();
      }
      expect(monitor.disposed, isTrue);
    });

    test('workspace json round-trips', () {
      const workspace = Workspace(
        id: '2',
        name: 'web',
        focused: false,
        urgent: true,
      );
      final decoded = Workspace.fromJson(
        Map<String, dynamic>.from(workspace.toJson()),
      );
      expect(decoded.id, '2');
      expect(decoded.name, 'web');
      expect(decoded.urgent, isTrue);
      final list = workspacesFromJson(workspacesToJson([workspace]).toList());
      expect(list.length, 1);
      expect(list.first.id, '2');
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
            predicate<ClockState>(
              (s) => s.now == DateTime(2026, 9, 12, 20, 1),
            ),
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
}
