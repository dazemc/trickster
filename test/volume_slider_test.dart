import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/volume_slider.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/state/capabilities_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/sink_volume_bloc.dart';
import 'package:trickster/src/state/volume_slider_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/fake_volume.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

class _RecordingLayerShell extends LayerShell {
  _RecordingLayerShell()
    : super(channel: const MethodChannel('test/trickster'));

  final opened = <int>[];
  final shown = <int>[];
  final closed = <int>[];
  var nextViewId = 100;

  @override
  Future<int?> openMenuSurface({
    required int barViewId,
    required String side,
  }) async {
    opened.add(barViewId);
    return nextViewId++;
  }

  @override
  Future<void> showMenuSurface({required int viewId}) async {
    shown.add(viewId);
  }

  @override
  Future<void> closeMenuSurface({required int viewId}) async {
    closed.add(viewId);
  }
}

VolumeSliderRequested _request() {
  return const VolumeSliderRequested(
    barViewId: 0,
    accent: _accent,
    click: Offset(120, 10),
    side: SystemBarSide.top,
    thickness: 32,
  );
}

/// Pumps the surface the way the app's overlay entry does, with the shared
/// sink volume bloc the track writes through.
Future<void> _pumpSurface(
  WidgetTester tester,
  VolumeSliderBloc slider,
  SinkVolumeBloc volume, {
  int volumeStep = MediaOptions.defaultVolumeStep,
}) async {
  slider.add(_request());
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => SettingsBloc(
            BarSettings(
              appearance: const AppearanceOptions(blur: true),
              media: MediaOptions(volumeStep: volumeStep),
            ),
          ),
        ),
        BlocProvider(
          create: (_) =>
              CapabilitiesBloc(initial: const Capabilities(blur: true)),
        ),
        BlocProvider<VolumeSliderBloc>.value(value: slider),
        BlocProvider<SinkVolumeBloc>.value(value: volume),
      ],
      child: TricksterLocalizationScope(
        locale: const Locale('en', 'US'),
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: BlocBuilder<VolumeSliderBloc, VolumeSliderState>(
            builder: (context, state) {
              final session = state.session;
              if (session == null) {
                return const SizedBox.shrink();
              }
              return VolumeSliderSurface(session: session);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('opening creates and shows an overlay surface', () async {
    final shell = _RecordingLayerShell();
    final slider = VolumeSliderBloc(layerShell: shell);
    addTearDown(slider.close);

    slider.add(_request());
    final open = await slider.stream.firstWhere((state) => state.isOpen);

    expect(shell.opened, [0]);
    expect(shell.shown, [100]);
    expect(open.session!.viewId, 100);
    expect(open.isSliderView(100), isTrue);
  });

  test('dismissing closes the surface', () async {
    final shell = _RecordingLayerShell();
    final slider = VolumeSliderBloc(layerShell: shell);
    addTearDown(slider.close);
    slider.add(_request());
    await slider.stream.firstWhere((state) => state.isOpen);

    slider.add(const VolumeSliderDismissed());
    final closed = await slider.stream.firstWhere((state) => !state.isOpen);

    expect(shell.closed, [100]);
    expect(closed.session, isNull);
  });

  test('retaining views drops the ids the engine no longer owns', () async {
    final shell = _RecordingLayerShell();
    final slider = VolumeSliderBloc(layerShell: shell);
    addTearDown(slider.close);
    slider.add(_request());
    await slider.stream.firstWhere((state) => state.isOpen);

    slider.add(const VolumeSliderViewsRetained(<int>{7}));
    final retained = await slider.stream.firstWhere(
      (state) => !state.isSliderView(100),
    );

    expect(retained.session, isNotNull);
  });

  test('the track position maps to a clamped level', () {
    expect(volumeSliderValue(Offset.zero, 200), 0);
    expect(volumeSliderValue(const Offset(100, 0), 200), closeTo(0.5, 0.0001));
    expect(volumeSliderValue(const Offset(250, 0), 200), 1);
    expect(volumeSliderValue(const Offset(-10, 0), 200), 0);
  });

  testWidgets('dragging the track writes the sink', (tester) async {
    final slider = VolumeSliderBloc(layerShell: _RecordingLayerShell());
    addTearDown(slider.close);
    final fake = FakePipeWireVolume();
    final volume = SinkVolumeBloc(volume: fake)..add(const SinkVolumeStarted());
    addTearDown(volume.close);
    await _pumpSurface(tester, slider, volume);
    fake.emit(0.5);
    await tester.pump();
    await tester.pump();

    final track = find.byKey(const ValueKey<String>('volume-slider-track'));
    expect(track, findsOneWidget);
    // From the track's center (0.5) drag right by a quarter of its width.
    final width = tester.getSize(track).width;
    await tester.drag(track, Offset(width / 4, 0));
    await tester.pump();

    expect(fake.sets, isNotEmpty);
    expect(fake.sets.last, closeTo(0.75, 0.02));
  });

  testWidgets('scrolling the open panel steps the sink', (tester) async {
    final slider = VolumeSliderBloc(layerShell: _RecordingLayerShell());
    addTearDown(slider.close);
    final fake = FakePipeWireVolume();
    final volume = SinkVolumeBloc(volume: fake)..add(const SinkVolumeStarted());
    addTearDown(volume.close);
    await _pumpSurface(tester, slider, volume, volumeStep: 10);
    fake.emit(0.5);
    await tester.pump();
    await tester.pump();

    final panel = find.byKey(const ValueKey<String>('volume-slider-panel'));
    final pointer = TestPointer(4, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(panel)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -40)));
    await tester.pump();

    expect(fake.sets.single, closeTo(0.6, 0.0001));
  });

  testWidgets('tapping outside dismisses the slider', (tester) async {
    final slider = VolumeSliderBloc(layerShell: _RecordingLayerShell());
    addTearDown(slider.close);
    final volume = SinkVolumeBloc(volume: FakePipeWireVolume());
    addTearDown(volume.close);
    await _pumpSurface(tester, slider, volume);
    expect(
      find.byKey(const ValueKey<String>('volume-slider-panel')),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('volume-slider-panel')),
      findsNothing,
    );
    expect(slider.state.session, isNull);
  });

  testWidgets('escape dismisses the slider', (tester) async {
    final slider = VolumeSliderBloc(layerShell: _RecordingLayerShell());
    addTearDown(slider.close);
    final volume = SinkVolumeBloc(volume: FakePipeWireVolume());
    addTearDown(volume.close);
    await _pumpSurface(tester, slider, volume);
    expect(
      find.byKey(const ValueKey<String>('volume-slider-panel')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('volume-slider-panel')),
      findsNothing,
    );
  });
}
