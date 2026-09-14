import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

void main() {
  test('resolveAccent prefers settings over session over brand', () {
    const settings = Color(0xffff0000);
    const session = Color(0xff00ff00);
    expect(
      resolveAccent(settings: settings, session: session),
      const WallpaperAccent(settings),
    );
    expect(resolveAccent(session: session), const WallpaperAccent(session));
    expect(
      resolveAccent(),
      const WallpaperAccent(ShellBrandColors.defaultAccent),
    );
  });
}
