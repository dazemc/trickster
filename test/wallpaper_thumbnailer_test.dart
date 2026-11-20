import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/wallpaper_thumbnailer.dart';

ProcessResult _result(int exitCode, [List<int> stdout = const <int>[]]) {
  return ProcessResult(1, exitCode, stdout, '');
}

void main() {
  test('prefers magick and asks for the first frame at 64 px', () async {
    final commands = <List<String>>[];
    final thumbnailer = ProcessWallpaperThumbnailer(
      magickAvailable: true,
      ffmpegAvailable: true,
      run: (executable, args) async {
        commands.add(<String>[executable, ...args]);
        return _result(0, <int>[1, 2, 3, 4]);
      },
    );

    final bytes = await thumbnailer.thumbnail('/home/example/night city.gif');

    expect(bytes, <int>[1, 2, 3, 4]);
    expect(commands, hasLength(1));
    expect(commands.single.first, 'magick');
    expect(commands.single, contains('/home/example/night city.gif[0]'));
    expect(commands.single, containsAllInOrder(<String>['-resize', '64x64']));
    expect(commands.single, containsAllInOrder(<String>['-limit', 'memory']));
  });

  test('falls back to ffmpeg when magick cannot decode the source', () async {
    final commands = <List<String>>[];
    final thumbnailer = ProcessWallpaperThumbnailer(
      magickAvailable: true,
      ffmpegAvailable: true,
      run: (executable, args) async {
        commands.add(<String>[executable, ...args]);
        if (executable == 'magick') {
          return _result(1);
        }
        return _result(0, <int>[9, 8, 7]);
      },
    );

    final bytes = await thumbnailer.thumbnail('/tmp/clip.gif');

    expect(bytes, <int>[9, 8, 7]);
    expect(commands.map((command) => command.first), <String>[
      'magick',
      'ffmpeg',
    ]);
    expect(commands.last, containsAllInOrder(<String>['-frames:v', '1']));
    expect(
      commands.last,
      contains('scale=64:64:force_original_aspect_ratio=decrease'),
    );
  });

  test('a missing decoder runs nothing and yields no thumbnail', () async {
    var runs = 0;
    final thumbnailer = ProcessWallpaperThumbnailer(
      magickAvailable: false,
      ffmpegAvailable: false,
      run: (executable, args) async {
        runs++;
        return _result(0, <int>[1]);
      },
    );

    expect(await thumbnailer.thumbnail('/tmp/wall.gif'), isNull);
    expect(runs, 0);
  });

  test('oversized or empty decoder output is rejected', () async {
    final oversized = ProcessWallpaperThumbnailer(
      magickAvailable: true,
      maxOutputBytes: 2,
      run: (executable, args) async => _result(0, <int>[1, 2, 3]),
    );
    expect(await oversized.thumbnail('/tmp/wall.gif'), isNull);

    final empty = ProcessWallpaperThumbnailer(
      magickAvailable: true,
      run: (executable, args) async => _result(0),
    );
    expect(await empty.thumbnail('/tmp/wall.gif'), isNull);
  });

  test('a hung decoder times out without retaining output', () async {
    final thumbnailer = ProcessWallpaperThumbnailer(
      magickAvailable: true,
      timeout: const Duration(milliseconds: 5),
      run: (executable, args) => Future<ProcessResult>.delayed(
        const Duration(milliseconds: 50),
        () => _result(0, <int>[1, 2, 3]),
      ),
    );

    expect(await thumbnailer.thumbnail('/tmp/wall.gif'), isNull);
  });
}
