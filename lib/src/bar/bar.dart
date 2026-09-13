import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/settings.dart';
import '../layout/system_bar.dart';
import '../state/providers.dart';
import '../theme/accent.dart';
import 'battery.dart';
import 'clock.dart';
import 'cpu.dart';
import 'pill.dart';
import 'workspaces.dart';

class TricksterBarStrip extends ConsumerWidget {
  const TricksterBarStrip({required this.side, super.key});

  final SystemBarSide side;

  static const double _edgePadding = 8;
  static const double _cardMargin = 5;
  static const double _cardGap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accent = ref.watch(accentProvider);
    final cpu = ref.watch(cpuProvider);
    final battery = ref.watch(batteryProvider);
    final workspaces = ref.watch(workspacesProvider);
    final horizontal = side.isHorizontal;
    return Padding(
      padding: horizontal
          ? const EdgeInsets.symmetric(
              horizontal: _edgePadding,
              vertical: _cardMargin,
            )
          : const EdgeInsets.symmetric(
              horizontal: _cardMargin,
              vertical: _edgePadding,
            ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Flex(
          direction: horizontal ? Axis.horizontal : Axis.vertical,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (settings.includes('workspaces') && workspaces.isNotEmpty)
              SystemBarEntrance(
                index: 2,
                horizontal: horizontal,
                child: Padding(
                  padding: horizontal
                      ? const EdgeInsets.only(right: _cardGap)
                      : const EdgeInsets.only(bottom: _cardGap),
                  child: RepaintBoundary(
                    child: WorkspacesPill(
                      accent: accent,
                      workspaces: workspaces,
                    ),
                  ),
                ),
              ),
            if (settings.includes('cpu') && cpu.current != null)
              SystemBarEntrance(
                index: 1,
                horizontal: horizontal,
                child: Padding(
                  padding: horizontal
                      ? const EdgeInsets.only(right: _cardGap)
                      : const EdgeInsets.only(bottom: _cardGap),
                  child: RepaintBoundary(
                    child: CpuPill(accent: accent, sample: cpu),
                  ),
                ),
              ),
            if (settings.includes('battery') && battery.capacity != null)
              SystemBarEntrance(
                index: 1,
                horizontal: horizontal,
                child: Padding(
                  padding: horizontal
                      ? const EdgeInsets.only(right: _cardGap)
                      : const EdgeInsets.only(bottom: _cardGap),
                  child: RepaintBoundary(
                    child: BatteryPill(accent: accent, status: battery),
                  ),
                ),
              ),
            if (settings.includes('clock'))
              SystemBarEntrance(
                index: 0,
                horizontal: horizontal,
                child: const RepaintBoundary(child: _ClockHost()),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClockHost extends ConsumerWidget {
  const _ClockHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(accentProvider);
    return ClockPill(accent: accent);
  }
}

class TricksterBar {
  const TricksterBar({
    required this.side,
    required this.thickness,
    required this.settings,
    required this.accent,
  });

  final SystemBarSide side;
  final double thickness;
  final BarSettings settings;
  final WallpaperAccent accent;
}
