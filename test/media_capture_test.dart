import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/state/media_bloc.dart';

import 'support/fake_pipewire.dart';

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

class _SilentMediaService extends MediaPlayerService {
  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> playPause() async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}
}

MprisPlaybackState _state({required bool playing}) {
  return MprisPlaybackState(
    serviceName: 'org.mpris.MediaPlayer2.fake',
    identity: 'Fake Player',
    title: 'Test Song',
    artists: const <String>['Test Artist'],
    album: 'Test Album',
    artUrl: '',
    length: const Duration(seconds: 180),
    position: const Duration(seconds: 42),
    observedAt: _epoch,
    status: playing ? MprisPlaybackStatus.playing : MprisPlaybackStatus.paused,
    canGoNext: true,
    canGoPrevious: true,
    canPlay: true,
    canPause: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'capture starts only for playing media with a visible visualizer',
    () async {
      final capture = FakePipeWireCapture();
      final bloc = MediaBloc(service: _SilentMediaService(), capture: capture);
      addTearDown(bloc.close);

      // Playing before the pill says anything: nothing runs yet.
      bloc.add(MediaSampled(_state(playing: true)));
      await pumpEventQueue();
      expect(capture.starts, isEmpty);

      bloc.add(const MediaVisualizerChanged(visible: true));
      await pumpEventQueue();
      expect(capture.starts, hasLength(1));

      bloc.add(MediaSampled(_state(playing: false)));
      await pumpEventQueue();
      expect(capture.stops, hasLength(1));

      // A hidden visualizer stays off even while playing.
      bloc.add(const MediaVisualizerChanged(visible: false));
      bloc.add(MediaSampled(_state(playing: true)));
      await pumpEventQueue();
      expect(capture.starts, hasLength(1));

      bloc.add(const MediaVisualizerChanged(visible: true));
      await pumpEventQueue();
      expect(capture.starts, hasLength(2));
    },
  );

  test('a refused monitor retries when the demand returns', () async {
    final capture = FakePipeWireCapture(startResult: false);
    final bloc = MediaBloc(service: _SilentMediaService(), capture: capture);
    addTearDown(bloc.close);

    bloc.add(const MediaVisualizerChanged(visible: true));
    bloc.add(MediaSampled(_state(playing: true)));
    await pumpEventQueue();
    expect(capture.starts, hasLength(1));

    bloc.add(MediaSampled(_state(playing: false)));
    await pumpEventQueue();
    bloc.add(MediaSampled(_state(playing: true)));
    await pumpEventQueue();
    expect(capture.starts, hasLength(2));
  });

  test('frames are consumed only while capturing', () async {
    final capture = FakePipeWireCapture();
    final bloc = MediaBloc(service: _SilentMediaService(), capture: capture);
    addTearDown(bloc.close);

    bloc.add(const MediaVisualizerChanged(visible: true));
    bloc.add(MediaSampled(_state(playing: true)));
    await pumpEventQueue();

    capture.emit(<double>[0.1, -0.1, 0.2, -0.2]);
    await pumpEventQueue();
    expect(capture.controller.hasListener, isTrue);

    bloc.add(MediaSampled(_state(playing: false)));
    await pumpEventQueue();
    expect(capture.controller.hasListener, isFalse);
  });
}
