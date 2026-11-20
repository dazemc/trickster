import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart' show FrameCallback;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/app.dart';
import 'package:trickster/src/bootstrap.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/session.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/state/capabilities_bloc.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/seat_idle_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell() : super(channel: const MethodChannel('test/app-startup'));

  @override
  Future<List<LayerOutput>> outputs() async => const <LayerOutput>[];
}

void main() {
  testWidgets('post-frame startup creates nothing after dispose', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('trickster-startup');
    addTearDown(() => directory.delete(recursive: true));
    final paths = ConfigPaths(configHome: directory.path);
    final settings = const BarSettings(revision: 1, modules: <String>['clock']);
    final runtime = RuntimeConfig(
      paths: paths,
      session: const SessionConfig(),
      outputs: const OutputsConfig(),
      settings: settings,
    );
    FrameCallback? captured;
    var watcherCalls = 0;
    var controlCalls = 0;

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>(create: (_) => SettingsBloc(settings)),
          BlocProvider<SessionBloc>(create: (_) => SessionBloc()),
          BlocProvider<OutputsBloc>(create: (_) => OutputsBloc()),
          BlocProvider<CapabilitiesBloc>(
            create: (_) => CapabilitiesBloc(
              probe: () async => false,
              changes: () => const Stream<bool>.empty(),
            ),
          ),
          BlocProvider<SeatIdleBloc>(
            create: (_) => SeatIdleBloc(
              probe: () async => false,
              changes: () => const Stream<bool>.empty(),
            ),
          ),
        ],
        child: TricksterApp(
          initial: runtime,
          layerShell: _FakeLayerShell(),
          contentBuilder: (_) => const SizedBox.shrink(),
          postFrameScheduler: (callback) => captured = callback,
          watcherBuilder:
              ({
                required Directory directory,
                required void Function() onChanged,
              }) {
                watcherCalls += 1;
                throw StateError('watcher created after dispose');
              },
          controlServerBuilder: ({required handler}) {
            controlCalls += 1;
            throw StateError('control server created after dispose');
          },
        ),
      ),
    );
    expect(captured, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => captured!(Duration.zero), returnsNormally);
    expect(watcherCalls, 0);
    expect(controlCalls, 0);
  });

  test('startup gate stops when prepare disposes the state', () {
    var mounted = true;
    var watcherCalls = 0;
    var controlCalls = 0;
    final gate = AppStartupGate(
      isMounted: () => mounted,
      prepare: () => mounted = false,
      startWatcher: () => watcherCalls += 1,
      startControl: () => controlCalls += 1,
    );

    expect(gate.run(), isFalse);
    expect(watcherCalls, 0);
    expect(controlCalls, 0);
  });
}
