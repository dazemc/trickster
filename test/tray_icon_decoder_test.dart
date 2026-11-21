import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/tray_icon_decoder.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xffff0000),
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes SVG icon files at display size', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-svg');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/icon.svg')
      ..writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="24">'
        '<rect width="48" height="24" fill="#ff0000"/></svg>',
      );

    final pixmap = await decodeStatusNotifierIconForTesting(file.path);

    expect(pixmap, isNotNull);
    expect(pixmap!.width, 24);
    expect(pixmap.height, 12);
    expect(pixmap.rgba.length, 24 * 12 * 4);
    expect(pixmap.rgba[0], 255);
    expect(pixmap.rgba[1], 0);
    expect(pixmap.rgba[2], 0);
    expect(pixmap.rgba[3], 255);
  });

  test('SVG icon files scale whole instead of cropping a corner', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-svg');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/corner.svg')
      ..writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 40">'
        '<rect x="16" y="36" width="4" height="4" fill="#ffffff"/></svg>',
      );

    final pixmap = await decodeStatusNotifierIconForTesting(file.path);

    expect(pixmap, isNotNull);
    // 20x40 scales so the longest side is the 24px display size.
    expect(pixmap!.width, 12);
    expect(pixmap.height, 24);
    int alphaAt(int x, int y) => pixmap.rgba[(y * 12 + x) * 4 + 3];
    // The mark sits at the viewBox's bottom-right; a cropped raster would
    // have lost it and kept the empty top-left instead.
    expect(alphaAt(0, 0), 0);
    expect(alphaAt(11, 23), greaterThan(0));
  });

  test('clamps a tall raster icon to the display size', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-tall');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/tall.png')
      ..writeAsBytesSync(await _png(1, 2000));

    final pixmap = await decodeStatusNotifierIconForTesting(file.path);

    expect(pixmap, isNotNull);
    expect(pixmap!.width, 1);
    expect(pixmap.height, 24);
    expect(pixmap.rgba.length, 1 * 24 * 4);
  });

  test('rejects a raster icon over the input dimension cap', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-wide');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/wide.png')
      ..writeAsBytesSync(await _png(5000, 1));

    expect(await decodeStatusNotifierIconForTesting(file.path), isNull);
  });

  test('rejects an icon file over the byte cap before reading it', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-large');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/large.png');
    final handle = file.openSync(mode: FileMode.write);
    try {
      handle.truncateSync(TrayIconLimits.maxIconFileBytes + 1);
    } finally {
      handle.closeSync();
    }

    expect(await decodeStatusNotifierIconForTesting(file.path), isNull);
  });

  test('returns null for a missing icon file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-missing',
    );
    addTearDown(() => directory.delete(recursive: true));

    expect(
      await decodeStatusNotifierIconForTesting('${directory.path}/none.png'),
      isNull,
    );
  });

  test('decodes the PNG fixture used by the service tests', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-fixture',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/fixture.png')
      ..writeAsBytesSync(base64Decode(_pngFixture));

    final pixmap = await decodeStatusNotifierIconForTesting(file.path);

    expect(pixmap, isNotNull);
    expect(pixmap!.width, 24);
    expect(pixmap.height, 24);
    expect(pixmap.rgba.length, 24 * 24 * 4);
  });
}

/// A 4x4 opaque red PNG: small, valid, and decodable by the engine codec.
const String _pngFixture =
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGP4z8DwHxkzkC4AADxAH+HggXe0AAAAAElFTkSuQmCC';
