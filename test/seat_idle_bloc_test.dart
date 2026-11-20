import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/state/seat_idle_bloc.dart';

void main() {
  test('state json round-trips', () {
    const state = SeatIdleState(idle: true);
    final decoded = SeatIdleState.fromJson(
      Map<String, dynamic>.from(state.toJson()),
    );
    expect(decoded, state);
    expect(SeatIdleState.fromJson(const {}).idle, isFalse);
  });

  test('the startup probe adopts an already-idle seat', () async {
    final bloc = SeatIdleBloc(
      probe: () async => true,
      changes: () => const Stream<bool>.empty(),
      log: (_) {},
    );
    addTearDown(bloc.close);
    bloc.add(const SeatIdleProbeRequested());
    await pumpEventQueue();
    expect(bloc.state.idle, isTrue);
  });

  test('a failed probe leaves the seat active', () async {
    final bloc = SeatIdleBloc(
      probe: () async => throw StateError('no native channel'),
      changes: () => const Stream<bool>.empty(),
      log: (_) {},
    );
    addTearDown(bloc.close);
    bloc.add(const SeatIdleProbeRequested());
    await pumpEventQueue();
    expect(bloc.state.idle, isFalse);
  });

  test('an active probe answer keeps the seat active', () async {
    final logs = <String>[];
    final bloc = SeatIdleBloc(
      probe: () async => false,
      changes: () => const Stream<bool>.empty(),
      log: logs.add,
    );
    addTearDown(bloc.close);
    bloc.add(const SeatIdleProbeRequested());
    await pumpEventQueue();
    expect(bloc.state.idle, isFalse);
    expect(logs, isEmpty);
  });

  test('an event after the probe still wins', () async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final bloc = SeatIdleBloc(
      probe: () async => false,
      changes: () => changes.stream,
      log: (_) {},
    );
    addTearDown(bloc.close);

    bloc.add(const SeatIdleProbeRequested());
    await pumpEventQueue();
    changes.add(true);
    await pumpEventQueue();
    expect(bloc.state.idle, isTrue);
  });

  test('a probe after an event is ignored', () async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    var probes = 0;
    final logs = <String>[];
    final bloc = SeatIdleBloc(
      probe: () async {
        probes += 1;
        return false;
      },
      changes: () => changes.stream,
      log: logs.add,
    );
    addTearDown(bloc.close);

    changes.add(true);
    await pumpEventQueue();
    bloc.add(const SeatIdleProbeRequested());
    await pumpEventQueue();
    expect(probes, 0);
    expect(bloc.state.idle, isTrue);
    expect(logs, ['trickster: seat idle']);
  });

  test('stream events emit once per transition and log only changes', () async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final logs = <String>[];
    final bloc = SeatIdleBloc(changes: () => changes.stream, log: logs.add);
    addTearDown(bloc.close);

    changes.add(true);
    changes.add(true);
    await pumpEventQueue();
    expect(bloc.state.idle, isTrue);
    expect(logs, ['trickster: seat idle']);

    changes.add(false);
    await pumpEventQueue();
    expect(bloc.state.idle, isFalse);
    expect(logs, ['trickster: seat idle', 'trickster: seat resumed']);
  });

  test('a native event wins over a probe still in flight', () async {
    final changes = StreamController<bool>.broadcast();
    addTearDown(changes.close);
    final probe = Completer<bool>();
    final bloc = SeatIdleBloc(
      probe: () => probe.future,
      changes: () => changes.stream,
      log: (_) {},
    );
    addTearDown(bloc.close);

    bloc.add(const SeatIdleProbeRequested());
    changes.add(true);
    await pumpEventQueue();
    probe.complete(false);
    await pumpEventQueue();
    expect(bloc.state.idle, isTrue);
  });

  test('close cancels the native subscription', () async {
    var cancelled = false;
    final changes = StreamController<bool>(onCancel: () => cancelled = true);
    final bloc = SeatIdleBloc(changes: () => changes.stream, log: (_) {});
    await bloc.close();
    expect(cancelled, isTrue);
    await changes.close();
  });

  test('close while a probe is pending emits and logs nothing', () async {
    final probe = Completer<bool>();
    final logs = <String>[];
    final bloc = SeatIdleBloc(
      probe: () => probe.future,
      changes: () => const Stream<bool>.empty(),
      log: logs.add,
    );
    bloc.add(const SeatIdleProbeRequested());
    await bloc.close();
    probe.complete(true);
    await pumpEventQueue();
    expect(logs, isEmpty);
  });
}
