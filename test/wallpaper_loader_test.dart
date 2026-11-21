import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/settings/wallpaper_loader.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';

void main() {
  const red = Color(0xffe03040);
  const wallpaper = WallpaperAccentState(
    enabled: true,
    color: red,
    accents: <String, Color?>{'HDMI-A-1': red},
    candidates: <String, List<Color>>{
      'HDMI-A-1': <Color>[red],
    },
  );

  test('parses a usable wallpaper slice from a status reply', () {
    final parsed = wallpaperAccentFromStatus(<String, Object?>{
      'ok': true,
      'state': <String, Object?>{'wallpaper': wallpaper.toJson()},
    });
    expect(parsed, isNotNull);
    expect(parsed!.candidatesFor('HDMI-A-1'), const <Color>[red]);
  });

  test('rejects missing, disabled, empty, and malformed replies', () {
    expect(wallpaperAccentFromStatus(null), isNull);
    expect(wallpaperAccentFromStatus(<String, Object?>{'ok': false}), isNull);
    expect(
      wallpaperAccentFromStatus(<String, Object?>{'ok': true, 'state': 1}),
      isNull,
    );
    expect(
      wallpaperAccentFromStatus(<String, Object?>{
        'ok': true,
        'state': <String, Object?>{'wallpaper': 1},
      }),
      isNull,
    );
    expect(
      wallpaperAccentFromStatus(<String, Object?>{
        'ok': true,
        'state': <String, Object?>{
          'wallpaper': const WallpaperAccentState(enabled: true).toJson(),
        },
      }),
      isNull,
    );
    expect(
      wallpaperAccentFromStatus(<String, Object?>{
        'ok': true,
        'state': <String, Object?>{
          'wallpaper': const WallpaperAccentState(
            enabled: false,
            color: red,
            candidates: <String, List<Color>>{
              'HDMI-A-1': <Color>[red],
            },
          ).toJson(),
        },
      }),
      isNull,
    );
  });

  test('an unreachable bar resolves to null for the local fallback', () async {
    expect(
      await loadBarWallpaperAccent(
        request: () async => throw StateError('no bar'),
      ),
      isNull,
    );
  });

  test('a status request is parsed once', () async {
    var calls = 0;
    final parsed = await loadBarWallpaperAccent(
      request: () async {
        calls += 1;
        return <String, Object?>{
          'ok': true,
          'state': <String, Object?>{'wallpaper': wallpaper.toJson()},
        };
      },
    );
    expect(calls, 1);
    expect(parsed, isNotNull);
  });
}
