import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/media.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

class _FakeMediaPlayerService extends MediaPlayerService {
  final calls = <String>[];

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> playPause() async => calls.add('playPause');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');
}

MprisPlaybackState _state({
  MprisPlaybackStatus status = MprisPlaybackStatus.playing,
  bool canGoNext = true,
  bool canGoPrevious = true,
}) {
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
    status: status,
    canGoNext: canGoNext,
    canGoPrevious: canGoPrevious,
    canPlay: true,
    canPause: true,
  );
}

Future<void> _pump(
  WidgetTester tester,
  MprisPlaybackState state,
  _FakeMediaPlayerService service,
) async {
  final bloc = MediaBloc(service: service, initial: state);
  addTearDown(bloc.close);
  await tester.pumpWidget(
    BlocProvider<MediaBloc>.value(
      value: bloc,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: MediaPill(accent: _accent)),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the now-playing text and taps reveal controls', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    await _pump(tester, _state(), service);

    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Media, Test Song, Test Artist'));
    await tester.pump();

    expect(find.bySemanticsLabel('Previous track'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next track'));
    await tester.pump();
    expect(service.calls, <String>['next']);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Media, Test Song, Test Artist'));
    await tester.pump();
    expect(find.bySemanticsLabel('Next track'), findsNothing);
  });

  testWidgets('paused playback shows play and drives the player', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    await _pump(tester, _state(status: MprisPlaybackStatus.paused), service);

    await tester.tap(find.bySemanticsLabel('Media, Test Song, Test Artist'));
    await tester.pump();
    expect(find.bySemanticsLabel('Pause'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(service.calls, <String>['playPause']);
  });

  testWidgets('unavailable capabilities absorb taps without collapsing', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    await _pump(tester, _state(canGoNext: false), service);

    await tester.tap(find.bySemanticsLabel('Media, Test Song, Test Artist'));
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Next track'));
    await tester.pump();
    expect(service.calls, isEmpty);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
  });
}
