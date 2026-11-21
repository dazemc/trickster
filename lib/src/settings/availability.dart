import 'dart:io';

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/brightness.dart';
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
  noKeyboardLayoutBackend,
  noBacklight,
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
  bool Function()? hasKeyboardLayoutBackend,
  bool Function()? hasBacklight,
  String backlightRoot = '/sys/class/backlight',
}) {
  final unavailable = <ModuleAvailability>[];
  if (!_available(hasBattery, _hasBattery)) {
    unavailable.add(
      const ModuleAvailability(
        module: 'battery',
        reason: ModuleUnavailableReason.noBattery,
      ),
    );
  }
  if (!_available(hasVram, hasGpuMemorySource)) {
    unavailable.add(
      const ModuleAvailability(
        module: 'vram',
        reason: ModuleUnavailableReason.noVram,
      ),
    );
  }
  if (!_available(hasTemperature, TemperatureSampler.hasReadableSensor)) {
    unavailable.add(
      const ModuleAvailability(
        module: 'temperature',
        reason: ModuleUnavailableReason.noTemperature,
      ),
    );
  }
  if (!_available(hasDisk, () => hasDiskMount(settings.disk.path))) {
    unavailable.add(
      const ModuleAvailability(
        module: 'disk',
        reason: ModuleUnavailableReason.noDisk,
      ),
    );
  }
  if (!_available(
    hasNetwork,
    () => hasNetworkInterface(pinned: settings.network.interface),
  )) {
    unavailable.add(
      const ModuleAvailability(
        module: 'network',
        reason: ModuleUnavailableReason.noNetwork,
      ),
    );
  }
  if (!_available(hasKeyboardLayoutBackend, _hasKeyboardLayoutBackend)) {
    unavailable.add(
      const ModuleAvailability(
        module: 'keyboard_layout',
        reason: ModuleUnavailableReason.noKeyboardLayoutBackend,
      ),
    );
  }
  if (!_available(
    hasBacklight,
    () => BrightnessSampler.hasReadableDevice(backlightRoot: backlightRoot),
  )) {
    unavailable.add(
      const ModuleAvailability(
        module: 'brightness',
        reason: ModuleUnavailableReason.noBacklight,
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

/// Whether [path] currently resolves to an existing filesystem entry the
/// bar's statvfs sample can reach. The sampler accepts a mount directory or
/// a file inside a mount, so the settings probe must accept both; a relative
/// or missing path is the actionable settings-side signal.
bool hasDiskMount(String path) {
  if (path.isEmpty || !path.startsWith('/')) {
    return false;
  }
  try {
    return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
  } on FileSystemException {
    return false;
  }
}

/// A hardware probe is advisory: a transient sysfs/read failure means "not
/// available", never a settings-page build error.
bool _available(bool Function()? override, bool Function() fallback) {
  try {
    return (override ?? fallback)();
  } on Object {
    return false;
  }
}

bool _hasKeyboardLayoutBackend() {
  final environment = Platform.environment;
  final hyprland =
      environment['HYPRLAND_INSTANCE_SIGNATURE'] != null &&
      environment['XDG_RUNTIME_DIR'] != null;
  return hyprland ||
      environment['SWAYSOCK'] != null ||
      environment['NIRI_SOCKET'] != null;
}

bool _hasBattery() {
  try {
    final directory = Directory('/sys/class/power_supply');
    if (!directory.existsSync()) {
      return false;
    }
    return directory.listSync().any((entry) {
      final name = entry.path.split('/').last;
      return name.startsWith('BAT');
    });
  } on FileSystemException {
    return false;
  }
}
