import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/media.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/visualizer_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/fake_bands.dart';
import 'support/strip_harness.dart';

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
  _FakeMediaPlayerService service, {
  bool vertical = false,
  MediaMode mode = MediaMode.semi,
  int bars = MediaOptions.defaultBars,
  FakeBandAnalyzer? analyzer,
  SettingsBloc? settings,
  bool disableAnimations = false,
}) async {
  final bloc = MediaBloc(service: service, initial: state);
  addTearDown(bloc.close);
  // The pill persists its mode cycle through the settings bloc and drives
  // the visualizer through its own; _pump owns whichever instances it uses.
  final settingsBloc = settings ?? SettingsBloc();
  addTearDown(settingsBloc.close);
  final visualizer = VisualizerBloc(analyzer: analyzer ?? FakeBandAnalyzer());
  addTearDown(visualizer.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<MediaBloc>.value(value: bloc),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
        BlocProvider<VisualizerBloc>.value(value: visualizer),
      ],
      child: withOverlayBlocs(
        TricksterLocalizationScope(
          child: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Center(
              child: MediaPill(
                accent: _accent,
                mode: mode,
                bars: bars,
                vertical: vertical,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps until [ready], so the test never guesses how many frames the
/// post-frame dispatch and the bloc's async start/stop chain need.
Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 30 && !ready(); i++) {
    await tester.pump();
  }
  expect(ready(), isTrue);
}

/// The mark's painter, read back to pin what the bars paint.
EqualizerPainter _equalizerPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(MediaPill.equalizerKey),
      matching: find.byType(CustomPaint),
    ),
  );
  return paint.painter! as EqualizerPainter;
}

/// Right-clicks the pill: the card-level cycle, wherever the pointer is.
Future<void> _cycle(WidgetTester tester) async {
  await tester.tap(
    find.byType(SystemBarCard).first,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
}

void main() {
  testWidgets('vertical shows only the controls', (tester) async {
    final service = _FakeMediaPlayerService();
    await _pump(tester, _state(), service, vertical: true);

    expect(find.text('Test Song'), findsNothing);
    expect(find.bySemanticsLabel('Previous track'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
  });

  testWidgets('full mode shows the text beside the equalizer and keys', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    await _pump(tester, _state(), service, mode: MediaMode.full);

    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.byKey(MediaPill.equalizerKey), findsOneWidget);
    expect(find.bySemanticsLabel('Previous track'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause'), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Next track'));
    await tester.pump();
    expect(service.calls, <String>['next']);
  });

  testWidgets('paused playback shows play and drives the player', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    await _pump(tester, _state(status: MprisPlaybackStatus.paused), service);

    expect(find.bySemanticsLabel('Pause'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Play'));
    await tester.pump();
    expect(service.calls, <String>['playPause']);
  });

  testWidgets('the configured mode sets what shows without a tap', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    await _pump(tester, _state(), service, mode: MediaMode.full);
    expect(find.text('Test Song'), findsOneWidget);
    expect(find.text('Test Artist'), findsOneWidget);
    expect(find.byKey(MediaPill.equalizerKey), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);

    await _pump(tester, _state(), service, mode: MediaMode.semi);
    expect(find.text('Test Song'), findsNothing);
    expect(find.byKey(MediaPill.equalizerKey), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);

    await _pump(tester, _state(), service, mode: MediaMode.compact);
    expect(find.text('Test Song'), findsNothing);
    expect(find.byKey(MediaPill.equalizerKey), findsNothing);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
  });

  testWidgets('right-clicking cycles the modes and saves the choice', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    final saved = <MediaMode>[];
    final settings = SettingsBloc(
      const BarSettings(),
      (next) async => saved.add(next.media.mode),
    );
    await _pump(
      tester,
      _state(),
      service,
      mode: MediaMode.semi,
      settings: settings,
    );
    expect(find.byKey(MediaPill.equalizerKey), findsOneWidget);
    expect(find.text('Test Song'), findsNothing);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);

    // semi -> compact: the keys alone remain.
    await _cycle(tester);
    expect(find.byKey(MediaPill.equalizerKey), findsNothing);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
    expect(settings.state.media.mode, MediaMode.compact);

    // compact -> full: keys, equalizer, and text together.
    await _cycle(tester);
    expect(find.byKey(MediaPill.equalizerKey), findsOneWidget);
    expect(find.text('Test Song'), findsOneWidget);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
    expect(settings.state.media.mode, MediaMode.full);

    // full -> semi: the text drops again.
    await _cycle(tester);
    expect(find.byKey(MediaPill.equalizerKey), findsOneWidget);
    expect(find.text('Test Song'), findsNothing);
    expect(settings.state.media.mode, MediaMode.semi);
    expect(saved, [MediaMode.compact, MediaMode.full, MediaMode.semi]);
  });

  testWidgets('the capture follows the visualizer through the mode cycle', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    final analyzer = FakeBandAnalyzer();
    await _pump(tester, _state(), service, analyzer: analyzer);
    await _until(tester, () => analyzer.starts.length == 1);

    // semi -> compact: the equalizer hides, so the monitor closes.
    await _cycle(tester);
    await _until(tester, () => analyzer.stops.isNotEmpty);

    // compact -> full: it shows again and the monitor reopens.
    await _cycle(tester);
    await _until(tester, () => analyzer.starts.length == 2);
  });

  test('equalizer levels fold bands into bars', () {
    expect(equalizerLevels(const <double>[]), const <double>[0, 0, 0, 0]);
    expect(
      equalizerLevels(const <double>[1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      <double>[1, 0, 0, 0],
    );
    expect(equalizerLevels(const <double>[0, 0.6, 0, 0.9, 0.9, 0.9]), <double>[
      0,
      0.3,
      0.9,
      0.9,
    ]);
  });

  test('the mark width follows the bar count', () {
    expect(equalizerMarkWidth(4), closeTo(16, 0.001));
    expect(equalizerMarkWidth(8), greaterThan(equalizerMarkWidth(4)));
  });

  testWidgets('the equalizer paints the configured bar count', (tester) async {
    final service = _FakeMediaPlayerService();
    final analyzer = FakeBandAnalyzer();
    await _pump(
      tester,
      _state(),
      service,
      analyzer: analyzer,
      mode: MediaMode.full,
      bars: 8,
    );
    await _until(tester, () => analyzer.starts.length == 1);

    analyzer.emit(List<double>.filled(12, 0.5));
    await _until(tester, () => _equalizerPainter(tester).levels.first > 0.4);

    final painter = _equalizerPainter(tester);
    expect(painter.levels, hasLength(8));
    expect(painter.levels, everyElement(closeTo(0.5, 0.001)));
  });

  testWidgets('the equalizer paints the analyzer levels', (tester) async {
    final service = _FakeMediaPlayerService();
    final analyzer = FakeBandAnalyzer();
    await _pump(
      tester,
      _state(),
      service,
      analyzer: analyzer,
      mode: MediaMode.full,
    );
    await _until(tester, () => analyzer.starts.length == 1);

    analyzer.emit(const <double>[1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    await _until(tester, () => _equalizerPainter(tester).levels.first > 0.9);

    final painter = _equalizerPainter(tester);
    expect(painter.levels, hasLength(4));
    expect(painter.levels.first, closeTo(1, 0.001));
    expect(painter.levels[1], closeTo(0, 0.001));
  });

  testWidgets('reduced motion rests the bars', (tester) async {
    final service = _FakeMediaPlayerService();
    final analyzer = FakeBandAnalyzer();
    await _pump(
      tester,
      _state(),
      service,
      analyzer: analyzer,
      mode: MediaMode.full,
      disableAnimations: true,
    );
    await _until(tester, () => analyzer.starts.length == 1);

    analyzer.emit(const <double>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
    await tester.pump();
    await tester.pump();

    expect(_equalizerPainter(tester).levels, everyElement(0));
  });

  testWidgets('an unavailable capture keeps the static rest', (tester) async {
    final service = _FakeMediaPlayerService();
    final analyzer = FakeBandAnalyzer(startResult: false);
    await _pump(
      tester,
      _state(),
      service,
      analyzer: analyzer,
      mode: MediaMode.full,
    );
    await _until(tester, () => analyzer.starts.isNotEmpty);

    expect(_equalizerPainter(tester).levels, everyElement(0));
  });

  testWidgets('unavailable capabilities absorb taps without collapsing', (
    tester,
  ) async {
    final service = _FakeMediaPlayerService();
    await _pump(tester, _state(canGoNext: false), service);

    await tester.tap(find.bySemanticsLabel('Next track'));
    await tester.pump();
    expect(service.calls, isEmpty);
    expect(find.bySemanticsLabel('Next track'), findsOneWidget);
  });
}
