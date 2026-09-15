import 'dart:io';

/// One module that cannot run on this machine, with the reason why.
class ModuleAvailability {
  const ModuleAvailability({required this.module, required this.reason});

  final String module;
  final ModuleUnavailableReason reason;
}

/// Why a module cannot run here; the settings page maps this to a caption.
enum ModuleUnavailableReason { noBattery }

/// Probes the machine for hardware the bar might not find. The settings page
/// takes this as a parameter so tests (and future remote transports) can
/// substitute their own answer.
List<ModuleAvailability> probeModuleAvailability() {
  final unavailable = <ModuleAvailability>[];
  if (!_hasBattery()) {
    unavailable.add(
      const ModuleAvailability(
        module: 'battery',
        reason: ModuleUnavailableReason.noBattery,
      ),
    );
  }
  return unavailable;
}

bool _hasBattery() {
  final directory = Directory('/sys/class/power_supply');
  if (!directory.existsSync()) {
    return false;
  }
  return directory.listSync().any((entry) {
    final name = entry.path.split('/').last;
    return name.startsWith('BAT');
  });
}
