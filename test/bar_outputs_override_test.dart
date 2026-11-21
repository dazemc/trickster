import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/control/control_handler.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';

/// Records the settings application's write and returns the same document,
/// like the file transport does after a successful atomic replace.
class _RecordingOutputsTransport implements OutputsDocumentTransport {
  _RecordingOutputsTransport(this.document);

  String document;
  var writes = 0;

  @override
  Future<String> read() async => document;

  @override
  Future<String> write(String next) async {
    writes += 1;
    document = next;
    return next;
  }
}

void main() {
  testWidgets(
    'a settings-app outputs save applies through the control handler',
    (tester) async {
      final outputs = _RecordingOutputsTransport(
        const OutputsConfig(side: SystemBarSide.top, thickness: 32).encode(),
      );
      final outputsBloc = OutputsBloc(OutputsConfig.parse(outputs.document));
      final settingsBloc = SettingsBloc(const BarSettings());
      final sessionBloc = SessionBloc();
      var reloads = 0;
      late BuildContext context;

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<SessionBloc>.value(value: sessionBloc),
            BlocProvider<OutputsBloc>.value(value: outputsBloc),
          ],
          child: Builder(
            builder: (captured) {
              context = captured;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final reply = await handleControlRequest(
        context: context,
        settings: FileSettingsTransport(
          File('/unused/settings.json'),
          asyncLock: false,
        ),
        outputs: outputs,
        reload: () {
          // The bar's reload path applies the parsed document it just wrote.
          outputsBloc.add(OutputsLoaded(OutputsConfig.parse(outputs.document)));
          reloads += 1;
          return null;
        },
        request: <String, Object?>{
          'command': 'outputs.write',
          'document': const OutputsConfig(
            side: SystemBarSide.bottom,
            thickness: 41,
          ).encode(),
        },
      );

      expect(reply['ok'], isTrue);
      expect(outputs.writes, 1);
      expect(reloads, 1);
      expect(reply['document'], outputs.document);
      await tester.pump();
      expect(outputsBloc.state.side, SystemBarSide.bottom);
      expect(outputsBloc.state.thickness, 41);
    },
  );
}
