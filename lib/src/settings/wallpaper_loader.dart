import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';

/// The wallpaper accent from one `status` reply, or null when the bar did not
/// publish a usable wallpaper state.
///
/// Pure so the control payload shape can be tested without a socket. A state
/// that is disabled, empty, or malformed is not a substitute for the local
/// sampler; the caller falls back to it.
WallpaperAccentState? wallpaperAccentFromStatus(Object? reply) {
  final result = wallpaperAccentProbeFromStatus(reply);
  return result.usable ? result.state : null;
}

/// The same reply parser, but keeps the reason: an explicit bar error is
/// [WallpaperAccentRemoteResult.unreachable] (do not wait), while a live bar
/// with no wallpaper state yet is [WallpaperAccentRemoteResult.unusable]
/// (bounded settle before the local fallback).
WallpaperAccentRemoteResult wallpaperAccentProbeFromStatus(Object? reply) {
  if (reply is! Map) {
    return const WallpaperAccentRemoteResult.unusable();
  }
  if (reply['ok'] != true) {
    return const WallpaperAccentRemoteResult.unreachable();
  }
  final state = reply['state'];
  if (state is! Map) {
    return const WallpaperAccentRemoteResult.unusable();
  }
  final wallpaper = state['wallpaper'];
  if (wallpaper is! Map) {
    return const WallpaperAccentRemoteResult.unusable();
  }
  try {
    final parsed = WallpaperAccentState.fromJson(
      Map<String, dynamic>.from(wallpaper),
    );
    return parsed.usable
        ? WallpaperAccentRemoteResult.usable(parsed)
        : WallpaperAccentRemoteResult.unusable(parsed);
  } on Object {
    return const WallpaperAccentRemoteResult.unusable();
  }
}

/// Asks the running bar for its already-computed wallpaper accent. The
/// settings process uses this so a wallpaper-using window does not run a
/// second decode, thumbnailer, or screencopy.
///
/// A missing bar, malformed reply, or unusable state returns null. The caller
/// treats the null as the local-fallback signal.
Future<WallpaperAccentState?> loadBarWallpaperAccent({
  Future<Map<String, Object?>> Function()? request,
}) async {
  final result = await loadBarWallpaperAccentProbe(request: request);
  return result.usable ? result.state : null;
}

/// [loadBarWallpaperAccent] with the reachability reason intact. Settings uses
/// this so a bar that is still opening its wallpaper sampler gets a bounded
/// settle instead of triggering a second decoder immediately.
Future<WallpaperAccentRemoteResult> loadBarWallpaperAccentProbe({
  Future<Map<String, Object?>> Function()? request,
}) async {
  try {
    final reply =
        await (request ??
            () =>
                controlRequest(const <String, Object?>{'command': 'status'}))();
    return wallpaperAccentProbeFromStatus(reply);
  } on Object {
    return const WallpaperAccentRemoteResult.unreachable();
  }
}
