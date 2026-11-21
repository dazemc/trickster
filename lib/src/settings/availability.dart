import 'dart:io';

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/network.dart';
import 'package:trickster/src/services/temperature.dart';

/// One module that cannot run on this machine, with the reason why.
class ModuleAvailability {
  const ModuleAvailability({required this.module, required this.reason});

  final String module;
  final ModuleUnavailableReason reason;
}

/// Why a module cannot run here; the settings page maps this to a caption.
enum ModuleUnavailableReason {
  noBattery,
  noVram,
  noTemperature,
  noDisk,
  noNetwork,
  noHyprland,
}

/// Probes the machine for hardware and configured paths the bar might not
/// find. The settings page takes this as a parameter so tests (and future
/// remote transports) can substitute their own answer.
///
/// [settings] supplies the disk path and pinned network interface the bar
/// would use; the predicate seams keep the probe testable without real
/// hardware. The result is ordered like the strip catalog.
List<ModuleAvailability> probeModuleAvailability({
  BarSettings settings = const BarSettings(),
  bool Function()? hasBattery,
  bool Function()? hasVram,
  bool Function()? hasTemperature,
  bool Function()? hasDisk,
  bool Function()? hasNetwork,
  bool Function()? hasHyprland,
}) {
  final unavailable = <ModuleAvailability>[];
  if (!(hasBattery?.call() ?? _hasBattery())) {
    unavailable.add(
      const ModuleAvailability(
        module: 'battery',
        reason: ModuleUnavailableReason.noBattery,
      ),
    );
  }
  if (!(hasVram?.call() ?? hasGpuMemorySource())) {
    unavailable.add(
      const ModuleAvailability(
        module: 'vram',
        reason: ModuleUnavailableReason.noVram,
      ),
    );
  }
  if (!(hasTemperature?.call() ?? TemperatureSampler.hasReadableSensor())) {
    unavailable.add(
      const ModuleAvailability(
        module: 'temperature',
        reason: ModuleUnavailableReason.noTemperature,
      ),
    );
  }
  if (!(hasDisk?.call() ?? hasDiskMount(settings.disk.path))) {
    unavailable.add(
      const ModuleAvailability(
        module: 'disk',
        reason: ModuleUnavailableReason.noDisk,
      ),
    );
  }
  if (!(hasNetwork?.call() ??
      hasNetworkInterface(pinned: settings.network.interface))) {
    unavailable.add(
      const ModuleAvailability(
        module: 'network',
        reason: ModuleUnavailableReason.noNetwork,
      ),
    );
  }
  if (!(hasHyprland?.call() ?? _hasHyprland())) {
    unavailable.add(
      const ModuleAvailability(
        module: 'keyboard_layout',
        reason: ModuleUnavailableReason.noHyprland,
      ),
    );
  }
  unavailable.sort((a, b) {
    final left = BarSettings.knownModules.indexOf(a.module);
    final right = BarSettings.knownModules.indexOf(b.module);
    return (left < 0 ? 1 << 20 : left).compareTo(right < 0 ? 1 << 20 : right);
  });
  return unavailable;
}

/// Whether [path] currently resolves to a directory the settings process can
/// reach. The bar samples statvfs; a missing or unreadable mount is the
/// actionable settings-side signal.
bool hasDiskMount(String path) {
  if (path.isEmpty || !path.startsWith('/')) {
    return false;
  }
  try {
    return Directory(path).existsSync();
  } on FileSystemException {
    return false;
  }
}

bool _hasHyprland() {
  return Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'] != null &&
      Platform.environment['XDG_RUNTIME_DIR'] != null;
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
