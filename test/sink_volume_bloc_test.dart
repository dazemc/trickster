import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/state/sink_volume_bloc.dart';

import 'support/fake_volume.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('started watches the sink and samples land in state', () async {
    final volume = FakePipeWireVolume();
    final bloc = SinkVolumeBloc(volume: volume);
    addTearDown(bloc.close);

    bloc.add(const SinkVolumeStarted());
    await pumpEventQueue();
    expect(volume.starts, hasLength(1));
    expect(bloc.state.active, isTrue);

    volume.emit(0.42);
    final sampled = await bloc.stream.firstWhere((state) => state.volume > 0.4);
    expect(sampled.volume, closeTo(0.42, 0.0001));
    expect(sampled.muted, isFalse);

    volume.emit(0.0, muted: true);
    final muted = await bloc.stream.firstWhere((state) => state.muted);
    expect(muted.volume, 0);
    expect(muted.muted, isTrue);
  });

  test('a set request moves state and the sink', () async {
    final volume = FakePipeWireVolume();
    final bloc = SinkVolumeBloc(volume: volume);
    addTearDown(bloc.close);
    bloc.add(const SinkVolumeStarted());
    await pumpEventQueue();

    bloc.add(const SinkVolumeSetRequested(0.75));
    final state = await bloc.stream.firstWhere((state) => state.volume > 0.7);

    expect(state.volume, closeTo(0.75, 0.0001));
    expect(volume.sets, <double>[0.75]);
  });

  test('a reading arriving during start still lands', () async {
    final volume = FakePipeWireVolume(emitOnStart: 0.5);
    final bloc = SinkVolumeBloc(volume: volume);
    addTearDown(bloc.close);

    bloc.add(const SinkVolumeStarted());
    final state = await bloc.stream.firstWhere((state) => state.hasReading);

    expect(state.volume, closeTo(0.5, 0.0001));
    expect(state.active, isTrue);
  });

  test('a refused watcher stays inactive', () async {
    final volume = FakePipeWireVolume(startResult: false);
    final bloc = SinkVolumeBloc(volume: volume);
    addTearDown(bloc.close);

    bloc.add(const SinkVolumeStarted());
    await pumpEventQueue();

    expect(volume.starts, hasLength(1));
    expect(bloc.state.active, isFalse);
  });

  test('state round-trips through JSON', () {
    const state = SinkVolumeState(
      volume: 0.35,
      muted: true,
      active: true,
      hasReading: true,
    );

    final decoded = SinkVolumeState.fromJson(
      Map<String, dynamic>.from(state.toJson()),
    );

    expect(decoded.volume, closeTo(0.35, 0.0001));
    expect(decoded.muted, isTrue);
    expect(decoded.active, isTrue);
    expect(decoded.hasReading, isTrue);
  });
}
