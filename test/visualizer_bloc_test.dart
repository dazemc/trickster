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

  test('state round-trips through JSON', () {
    const state = VisualizerState(levels: <double>[0.1, 0.5], active: true);

    final decoded = VisualizerState.fromJson(
      Map<String, dynamic>.from(state.toJson()),
    );

    expect(decoded.levels, <double>[0.1, 0.5]);
    expect(decoded.active, isTrue);
  });
}
