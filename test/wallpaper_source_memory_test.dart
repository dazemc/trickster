import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/theme/wallpaper_accent.dart';

void main() {
  test('bounded source read does not allocate the oversized file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'trickster-wall-rss',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/huge.gif');
    final handle = await file.open(mode: FileMode.write);
    await handle.setPosition(const WallpaperSourceLimits().maxBytes + 1);
    await handle.writeByte(0);
    await handle.close();

    final before = ProcessInfo.maxRss;
    final bytes = await readWallpaperSource(file.path);
    final after = ProcessInfo.maxRss;

    expect(bytes, isNull);
    // Reading the sparse source would allocate at least maxBytes. A separate
    // suite keeps this process's baseline stable while still leaving room for
    // the file-stat and isolate bookkeeping.
    expect(after - before, lessThan(16 * 1024 * 1024));
  });
}
