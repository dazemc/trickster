import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/battery.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/cpu.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/observer.dart';
import 'package:trickster/src/state/settings_bloc.dart';

import 'support/strip_harness.dart';

/// Records that [close] was invoked without awaiting it: provider disposal
/// calls `close()` unawaited, and awaiting a bloc close inside FakeAsync
/// hangs on the bloc's internal event pipeline. The flag proves disposal
/// ran; unit tests prove disposal releases samplers.
class _CloseNotingCpuBloc extends CpuBloc {
  _CloseNotingCpuBloc({required super.initial, required this.onClosed});

  final void Function() onClosed;

  @override
  Future<void> close() {
    onClosed();
    return super.close();
  }
}

bool _created(List<String> lines, String bloc) =>
    lines.any((line) => line.startsWith('bloc+ ') && line.contains(bloc));

void main() {
  testWidgets('disabled modules build no blocs and render nothing', (
    tester,
  ) async {
    final lines = <String>[];
    final previous = Bloc.observer;
    Bloc.observer = TricksterObserver(log: lines.add);
    try {
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['clock']),
        settle: const Duration(milliseconds: 500),
      );
    } finally {
      Bloc.observer = previous;
    }

    expect(find.byType(ClockPill), findsOneWidget);
    expect(find.byType(CpuPill), findsNothing);
    expect(find.byType(BatteryPill), findsNothing);
    expect(find.byType(WorkspacesPill), findsNothing);

    // The transcript is the silence instrument: no bloc, hence no
    // subscription and no timer, for anything not configured.
    expect(_created(lines, 'ClockBloc'), isTrue);
    expect(_created(lines, 'CpuBloc'), isFalse);
    expect(_created(lines, 'GpuBloc'), isFalse);
    expect(_created(lines, 'TrayBloc'), isFalse);
    expect(_created(lines, 'BatteryBloc'), isFalse);
    expect(_created(lines, 'WorkspacesBloc'), isFalse);
    expect(_created(lines, 'MediaBloc'), isFalse);
    expect(
      lines.any(
        (line) =>
            line.contains('CpuBloc') ||
            line.contains('GpuBloc') ||
            line.contains('TrayBloc') ||
            line.contains('BatteryBloc') ||
            line.contains('WorkspacesBloc') ||
            line.contains('MediaBloc'),
      ),
      isFalse,
    );
  });

  testWidgets('enabling a module creates its bloc; disabling closes it', (
    tester,
  ) async {
    final lines = <String>[];
    final previous = Bloc.observer;
    Bloc.observer = TricksterObserver(log: lines.add);
    var cpuClosed = false;
    try {
      await pumpBarHarness(
        tester,
        settings: const BarSettings(modules: ['clock']),
        cpuBuilder: () => _CloseNotingCpuBloc(
          initial: const CpuSample(0.42),
          onClosed: () => cpuClosed = true,
        ),
        settle: const Duration(milliseconds: 500),
      );
      expect(find.byType(CpuPill), findsNothing);

      final settingsBloc = tester
          .element(find.byType(TricksterBarStrip))
          .read<SettingsBloc>();
      lines.clear();
      settingsBloc.add(const SettingsModulesChanged(['clock', 'cpu']));
      await tester.pump();
      await tester.pump();

      expect(_created(lines, 'CpuBloc'), isTrue);
      expect(find.byType(CpuPill), findsOneWidget);

      lines.clear();
      settingsBloc.add(const SettingsModulesChanged(['clock']));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Removal from the tree is the disposal: the provider closed the
      // bloc (flag), the pill is gone, and no new bloc was created.
      // (`bloc-` itself is unassertable here — the close future only
      // completes on a real event loop, which FakeAsync never gives.)
      expect(cpuClosed, isTrue);
      expect(find.byType(CpuPill), findsNothing);
      expect(_created(lines, 'CpuBloc'), isFalse);
    } finally {
      Bloc.observer = previous;
    }
  });
}
