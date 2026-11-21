import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/settings/app.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';

void main() {
  const custom = BarSettings(revision: 1);
  const wallpaper = BarSettings(
    revision: 1,
    accentSource: AccentSource.wallpaper,
  );

  test('a source transition enables or disables the sampler', () {
    final enable = wallpaperAccentEventFor(
      const SettingsAppState(settings: custom),
      const SettingsAppState(settings: wallpaper),
    );
    expect(enable, isA<WallpaperAccentEnabled>());
    expect((enable! as WallpaperAccentEnabled).enabled, isTrue);

    final disable = wallpaperAccentEventFor(
      const SettingsAppState(settings: wallpaper),
      const SettingsAppState(settings: custom),
    );
    expect(disable, isA<WallpaperAccentEnabled>());
    expect((disable! as WallpaperAccentEnabled).enabled, isFalse);
  });

  test('a wallpaper save revision refreshes without a new enable', () {
    final refresh = wallpaperAccentEventFor(
      const SettingsAppState(settings: wallpaper),
      const SettingsAppState(
        settings: BarSettings(
          revision: 2,
          accentSource: AccentSource.wallpaper,
        ),
      ),
    );
    expect(refresh, isA<WallpaperAccentRefreshRequested>());
  });

  test('preview and busy emissions do not refresh', () {
    final state = SettingsAppState(settings: wallpaper);
    expect(wallpaperAccentEventFor(state, state.copyWith(busy: true)), isNull);
    expect(
      wallpaperAccentEventFor(
        state,
        state.copyWith(
          settings: wallpaper.copyWith(accent: const Color(0xFF000001)),
        ),
      ),
      isNull,
    );
  });

  test('a custom-source revision change does not refresh', () {
    expect(
      wallpaperAccentEventFor(
        const SettingsAppState(settings: custom),
        const SettingsAppState(settings: BarSettings(revision: 2)),
      ),
      isNull,
    );
  });
}
