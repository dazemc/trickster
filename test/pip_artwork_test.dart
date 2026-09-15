import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/pip_artwork.dart';

const _svg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 20">'
    '<rect width="10" height="20" fill="#ffffff"/></svg>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes a browsed svg file at the pip size', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-pip');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/pip.svg');
    await file.writeAsString(_svg);

    final cache = PipArtworkCache(dimension: 14);
    addTearDown(cache.dispose);
    final artwork = await cache.load(file.path);
    expect(artwork, isNotNull);
    expect(artwork!.vector, isTrue);
    // The longest side is the pip dimension; the aspect ratio is kept.
    expect(artwork.image.width, 7);
    expect(artwork.image.height, 14);
    expect(cache.length, 1);

    final again = await cache.load(file.path);
    expect(again, same(artwork));
  });

  test('decodes a browsed raster file scaled into the pip size', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-pip');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/pip.png');
    final source = await createTestImage(width: 28, height: 14);
    final encoded = await source.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    await file.writeAsBytes(encoded!.buffer.asUint8List());

    final cache = PipArtworkCache(dimension: 14);
    addTearDown(cache.dispose);
    final artwork = await cache.load(file.path);
    expect(artwork, isNotNull);
    expect(artwork!.vector, isFalse);
    expect(artwork.image.width, 14);
    expect(artwork.image.height, 7);
  });

  test('svg artwork scales whole instead of cropping a corner', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-pip');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/corner.svg');
    await file.writeAsString(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 40">'
      '<rect x="16" y="36" width="4" height="4" fill="#ffffff"/></svg>',
    );

    final cache = PipArtworkCache(dimension: 14);
    addTearDown(cache.dispose);
    final artwork = await cache.load(file.path);
    expect(artwork, isNotNull);
    // 20x40 scales into the 14px square corner of the pip.
    expect(artwork!.image.width, 7);
    expect(artwork.image.height, 14);
    final data = await artwork.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final rgba = data!.buffer.asUint8List();
    int alphaAt(int x, int y) => rgba[(y * 7 + x) * 4 + 3];
    // The mark sits at the viewBox's bottom-right; a cropped raster would
    // have lost it and kept the empty top-left instead.
    expect(alphaAt(0, 0), 0);
    expect(alphaAt(6, 13), greaterThan(0));
  });

  test('missing, empty, and oversized files resolve to null', () async {
    final cache = PipArtworkCache(read: (_) async => Uint8List(0));
    addTearDown(cache.dispose);
    expect(await cache.load(''), isNull);
    expect(await cache.load('/nope/missing.png'), isNull);
    expect(await cache.load('/nope/missing.svg'), isNull);

    final huge = PipArtworkCache(
      read: (_) async => Uint8List(2048),
      maxBytes: 1024,
    );
    addTearDown(huge.dispose);
    expect(await huge.load('/tmp/huge.png'), isNull);
  });

  test('the cache evicts the oldest entries past its cap', () async {
    var reads = 0;
    final cache = PipArtworkCache(
      read: (_) async {
        reads++;
        return Uint8List.fromList(_svg.codeUnits);
      },
      maxEntries: 2,
    );
    addTearDown(cache.dispose);

    await cache.load('/tmp/a.svg');
    await cache.load('/tmp/b.svg');
    await cache.load('/tmp/c.svg');
    expect(cache.length, 2);
    expect(reads, 3);
  });
}
