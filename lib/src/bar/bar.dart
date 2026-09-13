import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../config/settings.dart';
import '../layout/system_bar.dart';
import '../services/battery.dart';
import '../services/cpu.dart';
import '../services/workspaces.dart';
import '../state/battery_bloc.dart';
import '../state/cpu_bloc.dart';
import '../state/session_bloc.dart';
import '../state/settings_bloc.dart';
import '../state/workspaces_bloc.dart';
import '../theme/accent.dart';
import 'battery.dart';
import 'clock.dart';
import 'cpu.dart';
import 'pill.dart';
import 'workspaces.dart';

class TricksterBarStrip extends StatelessWidget {
  const TricksterBarStrip({
    required this.side,
    this.onOpenPowerSettings = _noop,
    super.key,
  });

  final SystemBarSide side;
  final VoidCallback onOpenPowerSettings;

  static const double _edgePadding = 8;
  static const double _cardMargin = 5;
  static const double _cardGap = 8;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsBloc>().state;
    final accent = resolveAccent(
      settings: settings.accent,
      session: context.select((SessionBloc bloc) => bloc.state.accent),
    );
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
            if (settings.includes('workspaces'))
              BlocBuilder<WorkspacesBloc, WorkspacesState>(
                builder: (context, state) {
                  if (state.workspaces.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return SystemBarEntrance(
                    index: 2,
                    horizontal: horizontal,
                    child: Padding(
                      padding: horizontal
                          ? const EdgeInsets.only(right: _cardGap)
                          : const EdgeInsets.only(bottom: _cardGap),
                      child: RepaintBoundary(
                        child: WorkspacesPill(
                          accent: accent,
                          workspaces: state.workspaces,
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (settings.includes('cpu'))
              BlocBuilder<CpuBloc, CpuSample>(
                builder: (context, sample) {
                  if (sample.current == null) {
                    return const SizedBox.shrink();
                  }
                  return SystemBarEntrance(
                    index: 1,
                    horizontal: horizontal,
                    child: Padding(
                      padding: horizontal
                          ? const EdgeInsets.only(right: _cardGap)
                          : const EdgeInsets.only(bottom: _cardGap),
                      child: RepaintBoundary(
                        child: CpuPill(accent: accent, sample: sample),
                      ),
                    ),
                  );
                },
              ),
            if (settings.includes('battery'))
              BlocBuilder<BatteryBloc, BatteryStatus>(
                builder: (context, status) {
                  if (status.capacity == null) {
                    return const SizedBox.shrink();
                  }
                  return SystemBarEntrance(
                    index: 1,
                    horizontal: horizontal,
                    child: Padding(
                      padding: horizontal
                          ? const EdgeInsets.only(right: _cardGap)
                          : const EdgeInsets.only(bottom: _cardGap),
                      child: RepaintBoundary(
                        child: BatteryPill(
                          accent: accent,
                          status: status,
                          onPressed: onOpenPowerSettings,
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (settings.includes('clock'))
              SystemBarEntrance(
                index: 0,
                horizontal: horizontal,
                child: RepaintBoundary(child: ClockPill(accent: accent)),
              ),
          ],
        ),
      ),
    );
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

void _noop() {}
