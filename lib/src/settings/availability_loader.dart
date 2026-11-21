import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/settings/availability.dart';

/// Refreshes the synchronous probe with live answers from the running bar.
///
/// The bar owns keyboard-layout availability: it knows whether a compositor
/// backend actually serves a layout, while the settings process only has the
/// ambient environment. An unreachable bar keeps the probe result.
Future<List<ModuleAvailability>> loadModuleAvailability({
  required BarSettings settings,
  Future<Map<String, Object?>> Function()? request,
  List<ModuleAvailability> Function(BarSettings settings)? probe,
}) async {
  final base = probe != null
      ? probe(settings)
      : probeModuleAvailability(settings: settings);
  Map<String, Object?>? reply;
  try {
    reply =
        await (request ??
            () =>
                controlRequest(const <String, Object?>{'command': 'status'}))();
  } on Object {
    return base;
  }
  return applyBarAvailability(base, reply);
}

/// Overlays the bar's reported module state on [base]. Pure so the control
/// payload shapes can be tested without a socket.
List<ModuleAvailability> applyBarAvailability(
  List<ModuleAvailability> base,
  Map<String, Object?>? reply,
) {
  if (reply == null || reply['ok'] != true) {
    return base;
  }
  final rawState = reply['state'];
  if (rawState is! Map) {
    return base;
  }
  final state = rawState.cast<String, Object?>();
  final keyboard = state['keyboard_layout'];
  if (keyboard is! Map) {
    return base;
  }
  final available = keyboard['available'] == true;
  final next = <ModuleAvailability>[
    for (final entry in base)
      if (entry.module != 'keyboard_layout') entry,
  ];
  if (!available) {
    next.add(
      const ModuleAvailability(
        module: 'keyboard_layout',
        reason: ModuleUnavailableReason.noKeyboardLayoutBackend,
      ),
    );
  }
  next.sort((a, b) {
    final left = BarSettings.knownModules.indexOf(a.module);
    final right = BarSettings.knownModules.indexOf(b.module);
    return (left < 0 ? 1 << 20 : left).compareTo(right < 0 ? 1 << 20 : right);
  });
  return next;
}
