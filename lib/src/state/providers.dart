import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/session.dart';
import '../config/settings.dart';
import '../layout/system_bar.dart';
import '../services/battery.dart';
import '../services/cpu.dart';
import '../services/workspaces.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';

final sessionProvider = StateProvider<SessionConfig>(
  (ref) => const SessionConfig(),
);

final outputsProvider = StateProvider<OutputsConfig>(
  (ref) => const OutputsConfig(),
);

final settingsProvider = StateProvider<BarSettings>(
  (ref) => const BarSettings(),
);

final accentProvider = Provider<WallpaperAccent>((ref) {
  final settings = ref.watch(settingsProvider);
  final session = ref.watch(sessionProvider);
  final color =
      settings.accent ?? session.accent ?? ShellBrandColors.defaultAccent;
  return WallpaperAccent(color);
});

final cpuProvider = NotifierProvider<CpuController, CpuSample>(
  CpuController.new,
);

final batteryProvider = NotifierProvider<BatteryController, BatteryStatus>(
  BatteryController.new,
);

final workspacesProvider =
    NotifierProvider<WorkspacesController, List<Workspace>>(
      WorkspacesController.new,
    );

class CpuController extends Notifier<CpuSample> {
  @override
  CpuSample build() {
    final enabled = ref.watch(settingsProvider.select((s) => s.includes('cpu')));
    if (!enabled) {
      return const CpuSample(null);
    }
    final sampler = CpuSampler();
    sampler.start();
    var alive = true;
    final sub = sampler.snapshots.listen((sample) {
      if (alive) {
        state = sample;
      }
    });
    ref.onDispose(() {
      alive = false;
      sub.cancel();
      sampler.dispose();
    });
    return const CpuSample(null);
  }
}

class BatteryController extends Notifier<BatteryStatus> {
  @override
  BatteryStatus build() {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.includes('battery')),
    );
    if (!enabled) {
      return const BatteryStatus();
    }
    final sampler = BatterySampler();
    sampler.start();
    var alive = true;
    final sub = sampler.snapshots.listen((status) {
      if (alive) {
        state = status;
      }
    });
    ref.onDispose(() {
      alive = false;
      sub.cancel();
      sampler.dispose();
    });
    return const BatteryStatus();
  }
}

class WorkspacesController extends Notifier<List<Workspace>> {
  @override
  List<Workspace> build() {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.includes('workspaces')),
    );
    if (!enabled) {
      return const [];
    }
    final monitor = WorkspaceMonitor();
    monitor.start();
    var alive = true;
    final sub = monitor.snapshots.listen((workspaces) {
      if (alive) {
        state = workspaces;
      }
    });
    ref.onDispose(() {
      alive = false;
      sub.cancel();
      monitor.dispose();
    });
    return const [];
  }
}
