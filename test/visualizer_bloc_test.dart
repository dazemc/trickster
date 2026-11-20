import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/state/visualizer_bloc.dart';

import 'support/fake_bands.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the analyzer runs only while playing and visible', () async {
    final analyzer = FakeBandAnalyzer();
    final bloc = VisualizerBloc(analyzer: analyzer);
    addTearDown(bloc.close);

    // Visible before any playback: nothing runs.
    bloc.add(const VisualizerVisibilityChanged(visible: true));
    await pumpEventQueue();
    expect(analyzer.starts, isEmpty);

    bloc.add(const VisualizerPlaybackChanged(playing: true));
    await pumpEventQueue();
    expect(analyzer.starts, hasLength(1));
    expect(bloc.state.active, isTrue);

    bloc.add(const VisualizerVisibilityChanged(visible: false));
    await pumpEventQueue();
    expect(analyzer.stops, hasLength(1));
    expect(bloc.state.active, isFalse);
    expect(bloc.state.levels, isEmpty);

    // Already stopped: pausing adds no second stop.
    bloc.add(const VisualizerPlaybackChanged(playing: false));
    await pumpEventQueue();
    expect(analyzer.stops, hasLength(1));
  });

  test('levels land in state and rest on stop', () async {
    final analyzer = FakeBandAnalyzer();
    final bloc = VisualizerBloc(analyzer: analyzer);
    addTearDown(bloc.close);
    bloc.add(const VisualizerVisibilityChanged(visible: true));
    bloc.add(const VisualizerPlaybackChanged(playing: true));
    await pumpEventQueue();

    analyzer.emit(const <double>[0.2, 0.6, 0.1]);
    final sampled = await bloc.stream.firstWhere(
      (state) => state.levels.isNotEmpty,
    );
    expect(sampled.levels, const <double>[0.2, 0.6, 0.1]);

    bloc.add(const VisualizerVisibilityChanged(visible: false));
    final rested = await bloc.stream.firstWhere((state) => !state.active);
    expect(rested.levels, isEmpty);
  });

  test('a refused start leaves the bars at rest', () async {
    final analyzer = FakeBandAnalyzer(startResult: false);
    final bloc = VisualizerBloc(analyzer: analyzer);
    addTearDown(bloc.close);

    bloc.add(const VisualizerVisibilityChanged(visible: true));
    bloc.add(const VisualizerPlaybackChanged(playing: true));
    await pumpEventQueue();

    expect(analyzer.starts, hasLength(1));
    expect(bloc.state.active, isFalse);
    expect(bloc.state.levels, isEmpty);
  });

  test('a failure rests the bars and restarts while visible', () async {
    final analyzer = FakeBandAnalyzer();
    final bloc = VisualizerBloc(
      analyzer: analyzer,
      retryBase: const Duration(milliseconds: 10),
      retryMax: const Duration(milliseconds: 40),
    );
    addTearDown(bloc.close);

    bloc.add(const VisualizerVisibilityChanged(visible: true));
    bloc.add(const VisualizerPlaybackChanged(playing: true));
    await pumpEventQueue();
    expect(analyzer.starts, hasLength(1));
    expect(bloc.state.active, isTrue);

    analyzer.emit(const <double>[0.2, 0.4]);
    await pumpEventQueue();
    expect(bloc.state.levels, const <double>[0.2, 0.4]);

    analyzer.fail();
    await pumpEventQueue();
    expect(bloc.state.active, isFalse);
    expect(bloc.state.levels, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 15));
    await pumpEventQueue();
    expect(analyzer.starts, hasLength(2));
    expect(bloc.state.active, isTrue);
  });

  test('a failure does not restart while hidden', () async {
    final analyzer = FakeBandAnalyzer();
    final bloc = VisualizerBloc(
      analyzer: analyzer,
      retryBase: const Duration(milliseconds: 10),
      retryMax: const Duration(milliseconds: 40),
    );
    addTearDown(bloc.close);

    bloc.add(const VisualizerVisibilityChanged(visible: true));
    bloc.add(const VisualizerPlaybackChanged(playing: true));
    await pumpEventQueue();

    analyzer.fail();
    await pumpEventQueue();
    bloc.add(const VisualizerVisibilityChanged(visible: false));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(analyzer.starts, hasLength(1));
  });

  test('a failure does not restart while stopped', () async {
    final analyzer = FakeBandAnalyzer();
    final bloc = VisualizerBloc(
      analyzer: analyzer,
      retryBase: const Duration(milliseconds: 10),
      retryMax: const Duration(milliseconds: 40),
    );
    addTearDown(bloc.close);

    bloc.add(const VisualizerVisibilityChanged(visible: true));
    bloc.add(const VisualizerPlaybackChanged(playing: true));
    await pumpEventQueue();

    analyzer.fail();
    await pumpEventQueue();
    bloc.add(const VisualizerPlaybackChanged(playing: false));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(analyzer.starts, hasLength(1));
  });

  test(
    'restart backoff doubles to its cap and resets on real levels',
    () async {
      final analyzer = FakeBandAnalyzer();
      final bloc = VisualizerBloc(
        analyzer: analyzer,
        retryBase: const Duration(milliseconds: 10),
        retryMax: const Duration(milliseconds: 40),
      );
      addTearDown(bloc.close);

      bloc.add(const VisualizerVisibilityChanged(visible: true));
      bloc.add(const VisualizerPlaybackChanged(playing: true));
      await pumpEventQueue();
      expect(bloc.retryDelay, const Duration(milliseconds: 10));

      analyzer.fail();
      await pumpEventQueue();
      expect(bloc.retryDelay, const Duration(milliseconds: 20));

      await Future<void>.delayed(const Duration(milliseconds: 15));
      await pumpEventQueue();
      expect(analyzer.starts, hasLength(2));
      expect(bloc.retryDelay, const Duration(milliseconds: 20));

      analyzer.fail();
      await pumpEventQueue();
      expect(bloc.retryDelay, const Duration(milliseconds: 40));

      await Future<void>.delayed(const Duration(milliseconds: 25));
      await pumpEventQueue();
      expect(analyzer.starts, hasLength(3));
      analyzer.fail();
      await pumpEventQueue();
      expect(bloc.retryDelay, const Duration(milliseconds: 40));

      await Future<void>.delayed(const Duration(milliseconds: 45));
      await pumpEventQueue();
      expect(analyzer.starts, hasLength(4));
      analyzer.emit(const <double>[0.1, 0.3]);
      await pumpEventQueue();
      expect(bloc.retryDelay, const Duration(milliseconds: 10));
    },
  );

  test('dispose cancels a pending restart', () async {
    final analyzer = FakeBandAnalyzer();
    final bloc = VisualizerBloc(
      analyzer: analyzer,
      retryBase: const Duration(milliseconds: 20),
      retryMax: const Duration(milliseconds: 40),
    );
    bloc.add(const VisualizerVisibilityChanged(visible: true));
    bloc.add(const VisualizerPlaybackChanged(playing: true));
    await pumpEventQueue();

    analyzer.fail();
    await pumpEventQueue();
    await bloc.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(analyzer.starts, hasLength(1));
  });

  test('late levels from an old generation are ignored', () async {
    final analyzer = FakeBandAnalyzer();
    final bloc = VisualizerBloc(analyzer: analyzer);
    addTearDown(bloc.close);

    bloc.add(const VisualizerVisibilityChanged(visible: true));
    bloc.add(const VisualizerPlaybackChanged(playing: true));
    await pumpEventQueue();
    analyzer.emit(const <double>[0.2, 0.4]);
    await pumpEventQueue();
    expect(bloc.state.levels, const <double>[0.2, 0.4]);

    // Generation 0 never belongs to the live analyzer subscription.
    bloc.add(const VisualizerLevelsSampled(<double>[0.9, 0.9], generation: 0));
    await pumpEventQueue();
    expect(bloc.state.levels, const <double>[0.2, 0.4]);
  });

  test('state round-trips through JSON', () {
    const state = VisualizerState(levels: <double>[0.1, 0.5], active: true);

    final decoded = VisualizerState.fromJson(
      Map<String, dynamic>.from(state.toJson()),
    );

    expect(decoded.levels, <double>[0.1, 0.5]);
    expect(decoded.active, isTrue);
  });
}
