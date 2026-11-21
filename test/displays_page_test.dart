import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/l10n/generated/app_localizations_en.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/pages/displays.dart';

void main() {
  late Directory directory;
  late File outputsFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('trickster-displays');
    outputsFile = File('${directory.path}/outputs.conf');
  });

  tearDown(() => directory.delete(recursive: true));

  testWidgets('a failed outputs write is visible and stays unapplied', (
    tester,
  ) async {
    final failing = _FailingOutputsTransport();
    final bloc = _bloc(outputsFile, outputsSocket: failing);
    addTearDown(bloc.close);
    await _load(bloc);
    await _pump(tester, bloc);

    final l10n = AppLocalizationsEn();
    expect(find.text(l10n.settingsOutputsSaveError), findsNothing);

    final failed = bloc.stream.firstWhere(
      (state) => state.outputsError != null,
    );
    await tester.tap(find.byKey(const ValueKey<String>('side-bottom')));
    final state = await failed;
    await tester.pumpAndSettle();

    expect(state.outputsError, contains('read-only'));
    expect(find.text(l10n.settingsOutputsSaveError), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(failing.writes, 1);
    // The transport never accepted the change, so the document it still
    // serves is the original placement. The banner says the bar keeps it.
    expect(OutputsConfig.parse(await failing.read()).side, SystemBarSide.top);
  });

  testWidgets('a pending slider preview is saved on direct unmount', (
    tester,
  ) async {
    final bloc = _bloc(outputsFile);
    addTearDown(bloc.close);
    await _load(bloc);
    await _pump(tester, bloc);

    final slider = find.byKey(const ValueKey<String>('thickness-slider'));
    final rect = tester.getRect(slider);
    final gesture = await tester.startGesture(rect.center);
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    final pending = bloc.outputs.thickness;
    expect(pending, isNot(32));
    // The 250ms debounce has not fired; the only way this value survives is
    // the page's dispose hook enqueueing it explicitly.
    expect(outputsFile.existsSync(), isFalse);

    await tester.pumpWidget(const SizedBox());
    await gesture.cancel();

    for (var attempt = 0; attempt < 50; attempt++) {
      if (outputsFile.existsSync()) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(outputsFile.existsSync(), isTrue);
    expect(
      OutputsConfig.parse(outputsFile.readAsStringSync()).thickness,
      pending,
    );
  });

  testWidgets('hidden ignores and discards the visible selection', (
    tester,
  ) async {
    final bloc = _bloc(outputsFile);
    addTearDown(bloc.close);
    await _load(bloc);
    await _pump(tester, bloc);

    final l10n = AppLocalizationsEn();
    await tester.tap(find.byKey(const ValueKey<String>('output-eDP-1')));
    await tester.pumpAndSettle();
    expect(
      outputsFile.readAsStringSync(),
      contains('system_bar=top,32,HDMI-A-1'),
    );

    await tester.tap(find.byKey(const ValueKey<String>('side-hidden')));
    await tester.pumpAndSettle();
    expect(outputsFile.readAsStringSync(), contains('system_bar=hidden'));
    expect(find.text(l10n.settingsHiddenNote), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('output-eDP-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('side-top')));
    await tester.pumpAndSettle();
    final parsed = OutputsConfig.parse(outputsFile.readAsStringSync());
    expect(parsed.side, SystemBarSide.top);
    expect(parsed.thickness, 32);
    expect(parsed.connectors, isEmpty);
    expect(find.text(l10n.settingsHiddenNote), findsNothing);
    expect(find.text(l10n.settingsOutputAll), findsOneWidget);
  });
}

SettingsAppBloc _bloc(
  File outputsFile, {
  OutputsDocumentTransport? outputsSocket,
}) {
  return SettingsAppBloc(
    socket: _MemorySettingsTransport(),
    file: FileSettingsTransport(
      File('${outputsFile.parent.path}/settings.json'),
    ),
    outputsSocket: outputsSocket ?? _NoBarOutputsTransport(),
    outputsFile: FileOutputsTransport(outputsFile),
    layerShell: _FakeLayerShell(),
  );
}

Future<void> _load(SettingsAppBloc bloc) async {
  bloc.add(const SettingsAppLoadRequested());
  await bloc.stream.firstWhere((state) => state.loaded);
}

Future<void> _pump(WidgetTester tester, SettingsAppBloc bloc) {
  tester.view.physicalSize = const Size(980, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    BlocProvider.value(
      value: bloc,
      child: TricksterLocalizationScope(
        locale: const Locale('en'),
        child: const SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: DisplaysPage(),
        ),
      ),
    ),
  );
}

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell() : super(channel: const MethodChannel('test/trickster'));

  @override
  Future<List<LayerOutput>> outputs() async => const <LayerOutput>[
    LayerOutput(name: 'eDP-1', width: 1920, height: 1080),
    LayerOutput(name: 'HDMI-A-1', width: 2560, height: 1440),
  ];
}

class _MemorySettingsTransport implements SettingsDocumentTransport {
  @override
  Future<SettingsDocument> read() async =>
      SettingsDocument(revision: 1, json: const BarSettings().encode());

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async => throw UnimplementedError();
}

class _NoBarOutputsTransport implements OutputsDocumentTransport {
  @override
  Future<String> read() async => throw const ControlSocketException('no bar');

  @override
  Future<String> write(String document) async =>
      throw const ControlSocketException('no bar');
}

class _FailingOutputsTransport implements OutputsDocumentTransport {
  var writes = 0;
  final _document = const OutputsConfig(
    side: SystemBarSide.top,
    thickness: 32,
  ).encode();

  @override
  Future<String> read() async => _document;

  @override
  Future<String> write(String document) async {
    writes += 1;
    throw FileSystemException('read-only file system', _document);
  }
}
