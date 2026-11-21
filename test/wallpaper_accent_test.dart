import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/grim_sampler.dart';
import 'package:trickster/src/services/wallpaper.dart';
import 'package:trickster/src/services/wallpaper_thumbnailer.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/theme/wallpaper_accent.dart';

const _redPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAEAQMAAACTPww9AAAAIGNIUk0AAHomAACAhAAA'
    '+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAADUExUReAwQKcCmhkAAAAHdElNRQfq'
    'CQ4CJSavvgZyAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI2LTA5LTE0VDAyOjM3OjM4KzAw'
    'OjAwVbun3AAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNi0wOS0xNFQwMjozNzozOCswMDow'
    'MCTmH2AAAAAodEVYdGRhdGU6dGltZXN0YW1wADIwMjYtMDktMTRUMDI6Mzc6MzgrMDA6'
    'MDBz8z6/AAAAC0lEQVQI12NggAAAAAgAAS8g3TEAAAAASUVORK5CYII=';

const _redGif = 'R0lGODlhBAAEAPAAAOAwQAAAACH5BAAAAAAALAAAAAAEAAQAAAIEhI8JBQA7';

/// Two frames: #e03040 first, #2030e0 second.
const _redBlueGif =
    'R0lGODlhBAAEAPAAAOAwQAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQAAAAAACwAAAAA'
    'BAAEAAACBISPCQUAIfkEAAAAAAAsAAAAAAQABACAIDDgAAAAAgSEjwkFADs=';

const _grayPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAAAAACMmsGiAAAAIGNIUk0AAHomAACAhAAA'
    '+gAAAIDoAAB1MAAA6mAAADqYAAAXcJy6UTwAAAACYktHRAD/h4/MvwAAAAd0SU1FB+oJ'
    'DgIoDi+l0MUAAAAldEVYdGRhdGU6Y3JlYXRlADIwMjYtMDktMTRUMDI6NDA6MTQrMDA6'
    'MDAb2cQvAAAAJXRFWHRkYXRlOm1vZGlmeQAyMDI2LTA5LTE0VDAyOjQwOjE0KzAwOjAw'
    'aoR8kwAAACh0RVh0ZGF0ZTp0aW1lc3RhbXAAMjAyNi0wOS0xNFQwMjo0MDoxNCswMDow'
    'MD2RXUwAAAAQSURBVAjXY2xgYGBgYkAhAAnkAIiZfyDFAAAAAElFTkSuQmCC';

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

ByteData _solid(int r, int g, int b, {int pixels = 100}) {
  final bytes = Uint8List(pixels * 4);
  for (var i = 0; i < pixels; i += 1) {
    bytes[i * 4] = r;
    bytes[i * 4 + 1] = g;
    bytes[i * 4 + 2] = b;
    bytes[i * 4 + 3] = 255;
  }
  return ByteData.sublistView(bytes);
}

class _FakeThumbnailer implements WallpaperThumbnailer {
  _FakeThumbnailer(this.bytes);

  final Uint8List? bytes;
  var calls = 0;

  @override
  Future<Uint8List?> thumbnail(String path) async {
    calls += 1;
    return bytes;
  }
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const Color(0xffff0000),
  );
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  group('dominantVibrantColor', () {
    test('votes a vivid color into a canonical seed', () {
      final color = dominantVibrantColor(_solid(224, 48, 64));
      expect(color, isNotNull);
      final hsv = HSVColor.fromColor(color!);
      expect(hsv.hue, anyOf(closeTo(354, 6), closeTo(0, 6)));
      expect(hsv.saturation, inInclusiveRange(0.35, 0.75));
      expect(hsv.value, closeTo(0.65, 0.01));
    });

    test('returns null for monochrome images', () {
      expect(dominantVibrantColor(_solid(128, 128, 128)), isNull);
      expect(dominantVibrantColor(_solid(8, 8, 8)), isNull);
    });

    test('ignores a handful of stray colored pixels', () {
      final bytes = Uint8List(1000 * 4);
      for (var i = 0; i < 1000; i += 1) {
        bytes[i * 4] = 128;
        bytes[i * 4 + 1] = 128;
        bytes[i * 4 + 2] = 128;
        bytes[i * 4 + 3] = 255;
      }
      bytes[0] = 255;
      bytes[1] = 0;
      bytes[2] = 0;
      expect(dominantVibrantColor(ByteData.sublistView(bytes)), isNull);
    });
  });

  test('extracts from GIF wallpapers', () async {
    final color = await extractWallpaperAccent(base64Decode(_redGif));
    expect(color, isNotNull);
    final hsv = HSVColor.fromColor(color!);
    expect(hsv.hue, anyOf(closeTo(354, 8), closeTo(0, 8)));
  });

  test('distinct hues become separate candidates', () async {
    // Half red, half blue: two hue buckets, both above the vote threshold.
    final bytes = Uint8List(400 * 4);
    for (var i = 0; i < 400; i += 1) {
      final red = i < 200;
      bytes[i * 4] = red ? 224 : 32;
      bytes[i * 4 + 1] = 32;
      bytes[i * 4 + 2] = red ? 32 : 224;
      bytes[i * 4 + 3] = 255;
    }
    final candidates = vibrantCandidates(ByteData.sublistView(bytes));
    expect(candidates, hasLength(2));
    final hues = [
      for (final candidate in candidates) HSVColor.fromColor(candidate).hue,
    ];
    expect(hues.any((hue) => hue < 30 || hue > 330), isTrue);
    expect(hues.any((hue) => hue > 200 && hue < 260), isTrue);
  });

  group('parseWallpaperPath', () {
    test('reads the last path token from the daemon arguments', () {
      expect(
        parseWallpaperPath('\u0000crop\u0000Lanczos3\u0000/tmp/wall.png'),
        '/tmp/wall.png',
      );
      expect(
        parseWallpaperPath('crop\u0000file:///tmp/wall.png'),
        '/tmp/wall.png',
      );
      expect(parseWallpaperPath('\u0000color\u0000000000'), isNull);
      expect(parseWallpaperPath(''), isNull);
    });
  });

  test('samples the cache and follows wallpaper changes', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final red = File('${directory.path}/red.png')
      ..writeAsBytesSync(base64Decode(_redPng));
    final cacheFile = File('${directory.path}/awww/HDMI-A-1');
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsStringSync('\u0000crop\u0000${red.path}');

    final controller = WallpaperAccentBloc(
      cache: WallpaperCache(root: cacheFile.parent),
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.color != null);

    final gray = File('${directory.path}/gray.png')
      ..writeAsBytesSync(base64Decode(_grayPng));
    // Writing the cache file is the daemon's change signal.
    cacheFile.writeAsStringSync('\u0000crop\u0000${gray.path}');
    await _waitFor(() => controller.state.color == null);

    controller.add(const WallpaperAccentEnabled(enabled: false));
    await controller.stream.firstWhere((state) => !state.enabled);
    expect(controller.state.color, isNull);
    expect(controller.state.enabled, isFalse);
  });

  test(
    'an output with no daemon file falls back to a screencopy sample',
    () async {
      final directory = await Directory.systemTemp.createTemp('trickster-wall');
      addTearDown(() => directory.delete(recursive: true));
      final red = File('${directory.path}/red.png')
        ..writeAsBytesSync(base64Decode(_redPng));
      final cacheFile = File('${directory.path}/awww/HDMI-A-1');
      cacheFile.parent.createSync(recursive: true);
      cacheFile.writeAsStringSync('\u0000crop\u0000${red.path}');

      final captures = <List<String>>[];
      var secondOutputWidth = 2560;
      final controller = WallpaperAccentBloc(
        cache: WallpaperCache(root: cacheFile.parent),
        outputs: () => [
          const LayerOutput(name: 'HDMI-A-1', width: 1920, height: 1080),
          LayerOutput(name: 'HDMI-A-2', width: secondOutputWidth, height: 1440),
        ],
        strip: () => (side: SystemBarSide.top, thickness: 32),
        grim: GrimSampler(
          available: true,
          run: (args) async {
            captures.add(args);
            return base64Decode(_redPng);
          },
        ),
      );
      addTearDown(controller.close);

      controller.add(const WallpaperAccentEnabled(enabled: true));
      await _waitFor(
        () => controller.state.candidatesFor('HDMI-A-2').isNotEmpty,
      );
      // Only the output without a daemon image was captured.
      expect(captures.single, <String>['-g', '0,32 2560x32', '-t', 'png', '-']);
      expect(controller.state.candidatesFor('HDMI-A-1'), isNotEmpty);

      // A later sample reuses the capture; only the display geometry
      // re-captures.
      controller.add(const WallpaperAccentSampleRequested());
      await _waitFor(
        () => controller.state.candidatesFor('HDMI-A-2').isNotEmpty,
      );
      expect(captures, hasLength(1));

      // Geometry-only display change: the key changes and grim runs again.
      secondOutputWidth = 1920;
      controller.add(const WallpaperAccentSampleRequested());
      await _waitFor(() => captures.length == 2);
      expect(captures.last, <String>['-g', '0,32 1920x32', '-t', 'png', '-']);
    },
  );

  test(
    'a wallpaper change recaptures grim even when geometry is unchanged',
    () async {
      final directory = await Directory.systemTemp.createTemp('trickster-wall');
      addTearDown(() => directory.delete(recursive: true));
      final root = Directory('${directory.path}/awww')..createSync();
      final cacheFile = File('${root.path}/OTHER')
        ..writeAsStringSync('${directory.path}/wall.png');
      var captureColor = const Color(0xffe03040);
      var grimRuns = 0;
      final controller = WallpaperAccentBloc(
        cache: WallpaperCache(root: root),
        outputs: () => const [
          LayerOutput(name: 'HDMI-A-1', width: 1920, height: 1080),
        ],
        strip: () => (side: SystemBarSide.top, thickness: 32),
        grim: GrimSampler(
          available: true,
          run: (_) async {
            grimRuns += 1;
            return base64Decode(_redPng);
          },
          extract: (_) async => <Color>[captureColor],
        ),
      );
      addTearDown(controller.close);

      controller.add(const WallpaperAccentEnabled(enabled: true));
      await _waitFor(
        () => controller.state.candidatesFor('HDMI-A-1').isNotEmpty,
      );
      expect(
        controller.state.candidatesFor('HDMI-A-1').first,
        const Color(0xffe03040),
      );
      expect(grimRuns, 1);

      // The daemon writes the cache file; the wallpaper behind the strip is
      // now blue. The capture key is unchanged, so only a wallpaper-aware
      // invalidation recaptures it.
      captureColor = const Color(0xff2050e0);
      cacheFile.writeAsStringSync('${directory.path}/wall2.png');
      await _waitFor(
        () =>
            controller.state.candidatesFor('HDMI-A-1').isNotEmpty &&
            controller.state.candidatesFor('HDMI-A-1').first ==
                const Color(0xff2050e0),
      );

      expect(grimRuns, 2);
    },
  );

  test(
    'an output without a cache file falls back to the sampled one',
    () async {
      final directory = await Directory.systemTemp.createTemp('trickster-wall');
      addTearDown(() => directory.delete(recursive: true));
      final red = File('${directory.path}/red.png')
        ..writeAsBytesSync(base64Decode(_redPng));
      final cacheFile = File('${directory.path}/awww/HDMI-A-1');
      cacheFile.parent.createSync(recursive: true);
      cacheFile.writeAsStringSync('\u0000crop\u0000${red.path}');

      final controller = WallpaperAccentBloc(
        cache: WallpaperCache(root: cacheFile.parent),
      );
      addTearDown(controller.close);

      controller.add(const WallpaperAccentEnabled(enabled: true));
      await _waitFor(() => controller.state.color != null);

      expect(controller.state.accentFor('HDMI-A-1'), controller.state.color);
      expect(controller.state.accentFor('HDMI-A-2'), controller.state.color);
      expect(controller.state.candidatesFor('HDMI-A-1'), isNotEmpty);
      expect(
        controller.state.candidatesFor('HDMI-A-2'),
        controller.state.candidatesFor('HDMI-A-1'),
      );
    },
  );

  test('a usable bar state replaces local sampling entirely', () async {
    const red = Color(0xffe03040);
    const remote = WallpaperAccentState(
      enabled: true,
      color: red,
      accents: <String, Color?>{'HDMI-A-1': red},
      candidates: <String, List<Color>>{
        'HDMI-A-1': <Color>[red],
      },
    );
    var localSamples = 0;
    var grimRuns = 0;
    final thumbnailer = _FakeThumbnailer(null);
    final controller = WallpaperAccentBloc(
      remote: () async => remote,
      sampleCandidates: (_) async {
        localSamples += 1;
        return const <Color>[red];
      },
      thumbnailer: thumbnailer,
      grim: GrimSampler(
        available: true,
        run: (_) async {
          grimRuns += 1;
          return base64Decode(_redPng);
        },
      ),
      watch: false,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.hasCandidates);

    expect(controller.state.candidatesFor('HDMI-A-1'), const <Color>[red]);
    expect(localSamples, 0);
    expect(thumbnailer.calls, 0);
    expect(grimRuns, 0);
  });

  test('an unavailable remote falls back to local sampling', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final red = File('${directory.path}/red.png')
      ..writeAsBytesSync(base64Decode(_redPng));
    final cacheFile = File('${directory.path}/awww/HDMI-A-1');
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsStringSync('\u0000crop\u0000${red.path}');

    var localSamples = 0;
    final controller = WallpaperAccentBloc(
      remote: () async => null,
      cache: WallpaperCache(root: cacheFile.parent),
      sampleCandidates: (_) async {
        localSamples += 1;
        return const <Color>[Color(0xffe03040)];
      },
      watch: false,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.hasCandidates);

    expect(localSamples, 1);
    expect(controller.state.enabled, isTrue);
  });

  test('an empty remote state falls back to local sampling', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final red = File('${directory.path}/red.png')
      ..writeAsBytesSync(base64Decode(_redPng));
    final cacheFile = File('${directory.path}/awww/HDMI-A-1');
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsStringSync('\u0000crop\u0000${red.path}');

    var localSamples = 0;
    final controller = WallpaperAccentBloc(
      remote: () async => const WallpaperAccentState(enabled: true),
      cache: WallpaperCache(root: cacheFile.parent),
      sampleCandidates: (_) async {
        localSamples += 1;
        return const <Color>[Color(0xffe03040)];
      },
      watch: false,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.hasCandidates);

    expect(localSamples, 1);
  });

  test('repeated enable events single-flight the remote request', () async {
    const red = Color(0xffe03040);
    var calls = 0;
    final controller = WallpaperAccentBloc(
      remote: () async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const WallpaperAccentState(
          enabled: true,
          color: red,
          candidates: <String, List<Color>>{
            'HDMI-A-1': <Color>[red],
          },
        );
      },
      watch: false,
    );
    addTearDown(controller.close);

    controller
      ..add(const WallpaperAccentEnabled(enabled: true))
      ..add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.hasCandidates);
    expect(calls, 1);
  });

  test(
    'a reachable empty bar is retried until its sampler is usable',
    () async {
      var remoteCalls = 0;
      var localSamples = 0;
      final controller = WallpaperAccentBloc(
        remoteProbe: () async {
          remoteCalls += 1;
          // The bar has received the saved source but has not enabled its
          // sampler yet on the first request.
          if (remoteCalls == 1) {
            return const WallpaperAccentRemoteResult.unusable();
          }
          return const WallpaperAccentRemoteResult.usable(
            WallpaperAccentState(
              enabled: true,
              color: Color(0xffe03040),
              candidates: <String, List<Color>>{
                'HDMI-A-1': <Color>[Color(0xffe03040)],
              },
            ),
          );
        },
        remoteSettleDelays: const <Duration>[
          Duration(milliseconds: 10),
          Duration(milliseconds: 10),
        ],
        sampleCandidates: (_) async {
          localSamples += 1;
          return const <Color>[Color(0xffe03040)];
        },
        watch: false,
      );
      addTearDown(controller.close);

      controller.add(const WallpaperAccentEnabled(enabled: true));
      await _waitFor(() => controller.state.hasCandidates);

      expect(remoteCalls, 2);
      expect(localSamples, 0);
      expect(controller.state.candidatesFor('HDMI-A-1'), const <Color>[
        Color(0xffe03040),
      ]);
    },
  );

  test('an unreachable bar falls back to local sampling immediately', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final root = Directory('${directory.path}/awww')..createSync();
    File(
      '${root.path}/HDMI-A-1',
    ).writeAsStringSync('${directory.path}/wall.png');
    var remoteCalls = 0;
    var localSamples = 0;
    final controller = WallpaperAccentBloc(
      cache: WallpaperCache(root: root),
      remoteProbe: () async {
        remoteCalls += 1;
        return const WallpaperAccentRemoteResult.unreachable();
      },
      sampleCandidates: (_) async {
        localSamples += 1;
        return const <Color>[Color(0xffe03040)];
      },
      watch: false,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => localSamples == 1 && controller.state.hasCandidates);

    expect(remoteCalls, 1);
    expect(controller.state.enabled, isTrue);
  });

  test(
    'a focus or save refresh replaces remote candidates without local work',
    () async {
      var remoteCalls = 0;
      var localSamples = 0;
      final controller = WallpaperAccentBloc(
        remoteProbe: () async {
          remoteCalls += 1;
          return WallpaperAccentRemoteResult.usable(
            WallpaperAccentState(
              enabled: true,
              color: Color(remoteCalls == 1 ? 0xffe03040 : 0xff2050e0),
              candidates: <String, List<Color>>{
                'HDMI-A-1': <Color>[
                  Color(remoteCalls == 1 ? 0xffe03040 : 0xff2050e0),
                ],
              },
            ),
          );
        },
        sampleCandidates: (_) async {
          localSamples += 1;
          return const <Color>[Color(0xffe03040)];
        },
        watch: false,
      );
      addTearDown(controller.close);

      controller.add(const WallpaperAccentEnabled(enabled: true));
      await _waitFor(() {
        final values = controller.state.candidatesFor('HDMI-A-1');
        return values.isNotEmpty && values.first == const Color(0xffe03040);
      });
      controller.add(const WallpaperAccentRefreshRequested());
      await _waitFor(() {
        final values = controller.state.candidatesFor('HDMI-A-1');
        return values.isNotEmpty && values.first == const Color(0xff2050e0);
      });

      expect(remoteCalls, 2);
      expect(localSamples, 0);
    },
  );

  test('a wallpaper cache event refreshes remote candidates', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final root = Directory('${directory.path}/awww')..createSync();
    final cacheFile = File('${root.path}/HDMI-A-1')
      ..writeAsStringSync('/tmp/red.png');
    var remoteCalls = 0;
    var localSamples = 0;
    final controller = WallpaperAccentBloc(
      cache: WallpaperCache(root: root),
      remoteProbe: () async {
        remoteCalls += 1;
        return WallpaperAccentRemoteResult.usable(
          WallpaperAccentState(
            enabled: true,
            color: Color(remoteCalls == 1 ? 0xffe03040 : 0xff2050e0),
            candidates: <String, List<Color>>{
              'HDMI-A-1': <Color>[
                Color(remoteCalls == 1 ? 0xffe03040 : 0xff2050e0),
              ],
            },
          ),
        );
      },
      sampleCandidates: (_) async {
        localSamples += 1;
        return const <Color>[Color(0xffe03040)];
      },
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() {
      final values = controller.state.candidatesFor('HDMI-A-1');
      return values.isNotEmpty && values.first == const Color(0xffe03040);
    });

    // The daemon writing the cache file is the only signal; no interval poll.
    cacheFile.writeAsStringSync('/tmp/blue.png');
    await _waitFor(() {
      final values = controller.state.candidatesFor('HDMI-A-1');
      return values.isNotEmpty && values.first == const Color(0xff2050e0);
    });

    expect(remoteCalls, 2);
    expect(localSamples, 0);
  });

  test('overlapping local sample requests never decode concurrently', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final root = Directory('${directory.path}/awww')..createSync();
    File(
      '${root.path}/HDMI-A-1',
    ).writeAsStringSync('${directory.path}/wall.png');
    var calls = 0;
    var active = 0;
    var maxActive = 0;
    final controller = WallpaperAccentBloc(
      cache: WallpaperCache(root: root),
      remoteProbe: () async => const WallpaperAccentRemoteResult.unreachable(),
      sampleCandidates: (_) async {
        calls += 1;
        active += 1;
        if (active > maxActive) {
          maxActive = active;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
        active -= 1;
        return const <Color>[Color(0xffe03040)];
      },
      watch: false,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => active == 1);
    controller
      ..add(const WallpaperAccentSampleRequested())
      ..add(const WallpaperAccentSampleRequested());
    await _waitFor(() => calls == 2 && active == 0);

    expect(maxActive, 1);
    expect(calls, 2);
  });

  test('disabling stops an in-flight multi-entry local sample', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final root = Directory('${directory.path}/awww')..createSync();
    for (var index = 0; index < 3; index += 1) {
      File(
        '${root.path}/OUT-$index',
      ).writeAsStringSync('${directory.path}/wall.png');
    }
    File('${directory.path}/wall.png').writeAsBytesSync(<int>[1]);
    var samples = 0;
    final controller = WallpaperAccentBloc(
      cache: WallpaperCache(root: root),
      remoteProbe: () async => const WallpaperAccentRemoteResult.unreachable(),
      sampleCandidates: (_) async {
        samples += 1;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return const <Color>[Color(0xffe03040)];
      },
      watch: false,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => samples == 1);
    controller.add(const WallpaperAccentEnabled(enabled: false));
    await _waitFor(() => !controller.state.enabled);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(samples, 1);
    expect(controller.state.enabled, isFalse);
  });

  test('remote status requests single-flight during a refresh', () async {
    var remoteCalls = 0;
    final controller = WallpaperAccentBloc(
      remoteProbe: () async {
        remoteCalls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return const WallpaperAccentRemoteResult.usable(
          WallpaperAccentState(
            enabled: true,
            color: Color(0xffe03040),
            candidates: <String, List<Color>>{
              'HDMI-A-1': <Color>[Color(0xffe03040)],
            },
          ),
        );
      },
      watch: false,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    controller
      ..add(const WallpaperAccentRefreshRequested())
      ..add(const WallpaperAccentRefreshRequested());
    await _waitFor(() => controller.state.hasCandidates);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(remoteCalls, 1);
  });

  test('a usable remote state never starts local decode or grim', () async {
    var localSamples = 0;
    var grimRuns = 0;
    final thumbnailer = _FakeThumbnailer(null);
    final controller = WallpaperAccentBloc(
      remoteProbe: () async => const WallpaperAccentRemoteResult.usable(
        WallpaperAccentState(
          enabled: true,
          color: Color(0xffe03040),
          candidates: <String, List<Color>>{
            'HDMI-A-1': <Color>[Color(0xffe03040)],
          },
        ),
      ),
      sampleCandidates: (_) async {
        localSamples += 1;
        return const <Color>[Color(0xffe03040)];
      },
      thumbnailer: thumbnailer,
      grim: GrimSampler(
        available: true,
        run: (_) async {
          grimRuns += 1;
          return base64Decode(_redPng);
        },
      ),
      outputs: () => const [
        LayerOutput(name: 'HDMI-A-1', width: 1920, height: 1080),
      ],
      strip: () => (side: SystemBarSide.top, thickness: 32),
      watch: false,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.hasCandidates);
    controller
      ..add(const WallpaperAccentRefreshRequested())
      ..add(const WallpaperAccentSampleRequested());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(localSamples, 0);
    expect(thumbnailer.calls, 0);
    expect(grimRuns, 0);
  });

  test('source limits accept 8K and reject extreme sizes', () {
    const limits = WallpaperSourceLimits();
    expect(limits.allowsSource(7680, 4320), isTrue);
    expect(limits.allowsSource(8192, 8192), isFalse);
    expect(limits.allowsSource(20000, 1), isFalse);
    expect(limits.allowsSource(16385, 1), isFalse);
    expect(limits.allowsSource(16384, 1), isTrue);
  });

  test('rejects an extreme-aspect source before decode', () async {
    final bytes = await _png(20000, 1);
    expect(await extractWallpaperAccents(bytes), isEmpty);
  });

  test('decodes only the first frame of an animated source', () async {
    final color = await extractWallpaperAccent(base64Decode(_redBlueGif));
    expect(color, isNotNull);
    final hsv = HSVColor.fromColor(color!);
    expect(hsv.hue, anyOf(closeTo(354, 8), closeTo(0, 8)));
  });

  test(
    'an oversized source is rejected before read and falls back to grim',
    () async {
      final directory = await Directory.systemTemp.createTemp('trickster-wall');
      addTearDown(() => directory.delete(recursive: true));
      final huge = File('${directory.path}/huge.gif');
      final handle = await huge.open(mode: FileMode.write);
      await handle.setPosition(const WallpaperSourceLimits().maxBytes + 1);
      await handle.writeByte(0);
      await handle.close();

      final cacheFile = File('${directory.path}/awww/HDMI-A-1');
      cacheFile.parent.createSync(recursive: true);
      cacheFile.writeAsStringSync('\u0000crop\u0000${huge.path}');

      final commands = <List<String>>[];
      final controller = WallpaperAccentBloc(
        cache: WallpaperCache(root: cacheFile.parent),
        thumbnailer: _FakeThumbnailer(null),
        outputs: () => const [
          LayerOutput(name: 'HDMI-A-1', width: 1920, height: 1080),
        ],
        strip: () => (side: SystemBarSide.top, thickness: 32),
        grim: GrimSampler(
          available: true,
          run: (args) async {
            commands.add(args);
            return base64Decode(_redPng);
          },
        ),
      );
      addTearDown(controller.close);

      controller.add(const WallpaperAccentEnabled(enabled: true));
      await _waitFor(
        () => controller.state.candidatesFor('HDMI-A-1').isNotEmpty,
      );

      expect(commands.single, <String>['-g', '0,32 1920x32', '-t', 'png', '-']);
      expect(commands.single, isNot(contains('-o')));
      expect(await readWallpaperSource(huge.path), isNull);
      expect(
        await huge.length(),
        greaterThan(const WallpaperSourceLimits().maxBytes),
      );
    },
  );

  test('an oversized source samples through the thumbnailer', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final huge = File('${directory.path}/huge.gif');
    final handle = await huge.open(mode: FileMode.write);
    await handle.setPosition(const WallpaperSourceLimits().maxBytes + 1);
    await handle.writeByte(0);
    await handle.close();
    final cacheFile = File('${directory.path}/awww/HDMI-A-1');
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsStringSync('\u0000crop\u0000${huge.path}');

    final thumbnailer = _FakeThumbnailer(base64Decode(_redPng));
    final controller = WallpaperAccentBloc(
      cache: WallpaperCache(root: cacheFile.parent),
      thumbnailer: thumbnailer,
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.color != null);

    expect(thumbnailer.calls, 1);
    expect(controller.state.color, isNotNull);
    expect(await readWallpaperSource(huge.path), isNull);
  });

  test('invalid thumbnail bytes fall through to grim', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final huge = File('${directory.path}/huge.gif');
    final handle = await huge.open(mode: FileMode.write);
    await handle.setPosition(const WallpaperSourceLimits().maxBytes + 1);
    await handle.writeByte(0);
    await handle.close();
    final cacheFile = File('${directory.path}/awww/HDMI-A-1');
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsStringSync('\u0000crop\u0000${huge.path}');

    final thumbnailer = _FakeThumbnailer(Uint8List.fromList(<int>[1, 2, 3]));
    var captures = 0;
    final controller = WallpaperAccentBloc(
      cache: WallpaperCache(root: cacheFile.parent),
      thumbnailer: thumbnailer,
      outputs: () => const [
        LayerOutput(name: 'HDMI-A-1', width: 1920, height: 1080),
      ],
      strip: () => (side: SystemBarSide.top, thickness: 32),
      grim: GrimSampler(
        available: true,
        run: (_) async {
          captures += 1;
          return base64Decode(_redPng);
        },
      ),
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.candidatesFor('HDMI-A-1').isNotEmpty);

    expect(thumbnailer.calls, 1);
    expect(captures, 1);
  });

  test('oversized thumbnail bytes fall through to grim', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final huge = File('${directory.path}/huge.gif');
    final handle = await huge.open(mode: FileMode.write);
    await handle.setPosition(const WallpaperSourceLimits().maxBytes + 1);
    await handle.writeByte(0);
    await handle.close();
    final cacheFile = File('${directory.path}/awww/HDMI-A-1');
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsStringSync('\u0000crop\u0000${huge.path}');

    final thumbnailer = _FakeThumbnailer(Uint8List(8 * 1024 * 1024 + 1));
    var captures = 0;
    final controller = WallpaperAccentBloc(
      cache: WallpaperCache(root: cacheFile.parent),
      thumbnailer: thumbnailer,
      outputs: () => const [
        LayerOutput(name: 'HDMI-A-1', width: 1920, height: 1080),
      ],
      strip: () => (side: SystemBarSide.top, thickness: 32),
      grim: GrimSampler(
        available: true,
        run: (_) async {
          captures += 1;
          return base64Decode(_redPng);
        },
      ),
    );
    addTearDown(controller.close);

    controller.add(const WallpaperAccentEnabled(enabled: true));
    await _waitFor(() => controller.state.candidatesFor('HDMI-A-1').isNotEmpty);

    expect(thumbnailer.calls, 1);
    expect(captures, 1);
  });
}
