import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/observer.dart';



class _FakeCpuSampler extends CpuSampler {
  final controller = StreamController<CpuSample>.broadcast();

  @override
  Stream<CpuSample> get snapshots => controller.stream;

  @override
  void start() {}

  @override
  void dispose() {
    controller.close();
  }
}

void main() {
  test('observer transcripts lifecycle, events, transitions, errors', () async {
    final lines = <String>[];
    final previous = Bloc.observer;
    final observer = TricksterObserver(log: lines.add);
    Bloc.observer = observer;
    try {
      final sampler = _FakeCpuSampler();
      final bloc = CpuBloc(sampler: sampler);
      bloc.add(const CpuStarted());
      await pumpEventQueue();
      sampler.controller.add(const CpuSample(0.5));
      await pumpEventQueue();
      // Handler errors escape as unhandled async errors, so route one
      // directly: this is exactly what bloc calls on handler failure.
      observer.onError(bloc, Exception('boom'), StackTrace.empty);
      await bloc.close();
    } finally {
      Bloc.observer = previous;
    }
    expect(
      lines.any((line) => line.startsWith('bloc+ CpuBloc initial=')),
      isTrue,
    );
    expect(
      lines.any((line) => line.startsWith('evt   CpuBloc CpuStarted')),
      isTrue,
    );
    expect(
      lines.any(
        (line) =>
            line.contains('CpuSampled') &&
            line.contains('µs') &&
            !line.contains('[?]'),
      ),
      isTrue,
    );
    expect(lines.any((line) => line.startsWith('err   CpuBloc')), isTrue);
    expect(lines.any((line) => line.startsWith('bloc- CpuBloc')), isTrue);
  });
}
