import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';

/// The wallpaper accent from one `status` reply, or null when the bar did not
/// publish a usable wallpaper state.
///
/// Pure so the control payload shape can be tested without a socket. A state
/// that is disabled, empty, or malformed is not a substitute for the local
/// sampler; the caller falls back to it.
WallpaperAccentState? wallpaperAccentFromStatus(Object? reply) {
  if (reply is! Map || reply['ok'] != true) {
    return null;
  }
  final state = reply['state'];
  if (state is! Map) {
    return null;
  }
  final wallpaper = state['wallpaper'];
  if (wallpaper is! Map) {
    return null;
  }
  try {
    final parsed = WallpaperAccentState.fromJson(
      Map<String, dynamic>.from(wallpaper),
    );
    return parsed.usable ? parsed : null;
  } on Object {
    return null;
  }
}

/// Asks the running bar for its already-computed wallpaper accent. The
/// settings process uses this so a wallpaper-using window does not run a
/// second decode, thumbnailer, screencopy, or cache watcher.
///
/// A missing bar, malformed reply, or unusable state returns null; the caller
/// starts the local sampler as the fallback.
Future<WallpaperAccentState?> loadBarWallpaperAccent({
  Future<Map<String, Object?>> Function()? request,
}) async {
  try {
    final reply =
        await (request ??
            () =>
                controlRequest(const <String, Object?>{'command': 'status'}))();
    return wallpaperAccentFromStatus(reply);
  } on Object {
    return null;
  }
}
