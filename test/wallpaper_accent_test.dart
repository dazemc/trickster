import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/wallpaper.dart';
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

    final controller = WallpaperAccentController(
      cache: WallpaperCache(root: cacheFile.parent),
    );
    addTearDown(controller.dispose);

    controller.update(enabled: true);
    await _waitFor(() => controller.color != null);

    final gray = File('${directory.path}/gray.png')
      ..writeAsBytesSync(base64Decode(_grayPng));
    // Writing the cache file is the daemon's change signal.
    cacheFile.writeAsStringSync('\u0000crop\u0000${gray.path}');
    await _waitFor(() => controller.color == null);

    controller.update(enabled: false);
    expect(controller.color, isNull);
    expect(controller.enabled, isFalse);
  });

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

      final controller = WallpaperAccentController(
        cache: WallpaperCache(root: cacheFile.parent),
      );
      addTearDown(controller.dispose);

      controller.update(enabled: true);
      await _waitFor(() => controller.color != null);

      expect(controller.accentFor('HDMI-A-1'), controller.color);
      expect(controller.accentFor('HDMI-A-2'), controller.color);
      expect(controller.candidatesFor('HDMI-A-1'), isNotEmpty);
      expect(
        controller.candidatesFor('HDMI-A-2'),
        controller.candidatesFor('HDMI-A-1'),
      );
    },
  );
}
