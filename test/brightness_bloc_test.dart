import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/brightness.dart';
import 'package:trickster/src/state/brightness_bloc.dart';

class FakeBrightnessSampler extends BrightnessSampler {
  FakeBrightnessSampler() : super(interval: const Duration(days: 1));

  final controller = StreamController<BrightnessSample>.broadcast();

  var disposed = false;
  var disposes = 0;
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  var refreshes = 0;
  bool? startedPaused;

  @override
  Stream<BrightnessSample> get snapshots => controller.stream;

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
  void refresh() {
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
  late FakeBrightnessSampler fake;

  test('started then sampled emits the sample', () async {
    fake = FakeBrightnessSampler();
    final bloc = BrightnessBloc(sampler: fake);
    const sample = BrightnessSample(
      current: 63,
      max: 100,
      actual: 63,
      device: 'intel_backlight',
      type: 'firmware',
      scale: 'linear',
    );
    try {
      bloc.add(const BrightnessStarted());
      await pumpEventQueue();
      fake.controller.add(sample);
      await expectLater(bloc.stream, emits(sample));
    } finally {
      await bloc.close();
    }
    expect(fake.disposed, isTrue);
  });

  test('stopped is terminal and close does not dispose twice', () async {
    fake = FakeBrightnessSampler();
    final bloc = BrightnessBloc(sampler: fake);
    final seen = <BrightnessSample>[];
    final subscription = bloc.stream.listen(seen.add);

    bloc.add(const BrightnessStarted());
    await pumpEventQueue();
    bloc.add(const BrightnessStopped());
    await pumpEventQueue();

    expect(fake.disposes, 1);
    expect(fake.controller.isClosed, isTrue);

    bloc.add(
      const BrightnessSampled(
        BrightnessSample(current: 70, max: 100, device: 'panel'),
      ),
    );
    bloc.add(const BrightnessStarted(paused: true));
    bloc.add(const BrightnessPaused());
    bloc.add(const BrightnessResumed());
    bloc.add(const BrightnessRefreshed());
    await pumpEventQueue();

    expect(seen, isEmpty);
    expect(fake.starts, 1);
    expect(fake.pauses, 0);
    expect(fake.resumes, 0);
    expect(fake.refreshes, 0);
    expect(fake.disposes, 1);

    await bloc.close();
    expect(fake.disposes, 1);
    await subscription.cancel();
  });

  blocTest<BrightnessBloc, BrightnessSample>(
    'seat pauses and resumes the sampler without emitting',
    build: () {
      fake = FakeBrightnessSampler();
      return BrightnessBloc(sampler: fake);
    },
    act: (bloc) async {
      bloc.add(const BrightnessStarted());
      await pumpEventQueue();
      bloc.add(const BrightnessPaused());
      await pumpEventQueue();
      bloc.add(const BrightnessResumed());
      await pumpEventQueue();
    },
    expect: () => const <BrightnessSample>[],
    verify: (_) {
      expect(fake.pauses, 1);
      expect(fake.resumes, 1);
    },
  );

  blocTest<BrightnessBloc, BrightnessSample>(
    'a settings reload refreshes the sampler',
    build: () {
      fake = FakeBrightnessSampler();
      return BrightnessBloc(sampler: fake);
    },
    act: (bloc) async {
      bloc.add(const BrightnessStarted());
      await pumpEventQueue();
      bloc.add(const BrightnessRefreshed());
      await pumpEventQueue();
    },
    expect: () => const <BrightnessSample>[],
    verify: (_) => expect(fake.refreshes, 1),
  );

  blocTest<BrightnessBloc, BrightnessSample>(
    'a module started while idle seeds a paused sampler',
    build: () {
      fake = FakeBrightnessSampler();
      return BrightnessBloc(sampler: fake);
    },
    act: (bloc) async {
      bloc.add(const BrightnessStarted(paused: true));
      await pumpEventQueue();
    },
    expect: () => const <BrightnessSample>[],
    verify: (_) => expect(fake.startedPaused, isTrue),
  );
}
