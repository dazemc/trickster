import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/l10n/generated/app_localizations_en.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/layout/shell_keys.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/pages/appearance.dart';
import 'package:trickster/src/settings/pages/displays.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/theme/tokens.dart';

void main() {
  late Directory directory;
  late File settingsFile;
  late File outputsFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('trickster-displays-ui');
    settingsFile = File('${directory.path}/settings.json');
    outputsFile = File('${directory.path}/outputs.conf');
  });

  tearDown(() => directory.delete(recursive: true));

  testWidgets('Tab reaches an output row; Enter and Space toggle it', (
    tester,
  ) async {
    _useKeyboardHighlight();
    final bloc = _bloc(
      settingsFile: settingsFile,
      outputsFile: outputsFile,
      reported: const <LayerOutput>[
        LayerOutput(name: 'eDP-1', width: 1920, height: 1080),
        LayerOutput(name: 'HDMI-A-1', width: 2560, height: 1440),
      ],
    );
    addTearDown(bloc.close);
    await _load(bloc);
    await _pumpDisplays(tester, bloc);

    final row = find.byKey(const ValueKey<String>('output-eDP-1'));
    final rowFocus = _focusNodeIn(tester, row);
    expect(rowFocus.hasFocus, isFalse);

    // Tab through the page's controls until traversal reaches the row. The
    // bound is generous; failing it means the row never joined the order.
    var reached = false;
    for (var press = 0; press < 30 && !reached; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      reached = rowFocus.hasFocus;
    }
    expect(reached, isTrue);

    final ring = tester.widget<AnimatedContainer>(
      find.descendant(of: row, matching: find.byType(AnimatedContainer)),
    );
    expect(
      (ring.decoration! as BoxDecoration).border!.top.color,
      ShellBrandColors.defaultAccent,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(bloc.state.outputs.connectors, const <String>['HDMI-A-1']);

    // The other row is now the last selected output and locks, but this row
    // keeps focus and turns back on with Space.
    expect(rowFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(bloc.state.outputs.connectors, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last selected output is locked on with an explanation', (
    tester,
  ) async {
    final bloc = _bloc(
      settingsFile: settingsFile,
      outputsFile: outputsFile,
      reported: const <LayerOutput>[
        LayerOutput(name: 'eDP-1', width: 1920, height: 1080),
      ],
    );
    addTearDown(bloc.close);
    await _load(bloc);
    await _pumpDisplays(tester, bloc);

    final l10n = AppLocalizationsEn();
    final row = find.byKey(const ValueKey<String>('output-eDP-1'));
    expect(find.text(l10n.settingsOutputsLastNote), findsOneWidget);

    final semantics = tester.widget<Semantics>(
      find.descendant(of: row, matching: find.byType(Semantics)).first,
    );
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.toggled, isTrue);
    expect(semantics.properties.enabled, isFalse);
    expect(semantics.properties.label, 'eDP-1 1920×1080');
    expect(semantics.properties.onTap, isNull);

    expect(
      tester
          .widget<SettingsActivatable>(
            find.descendant(
              of: row,
              matching: find.byType(SettingsActivatable),
            ),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(bloc.state.outputs.connectors, isEmpty);
    expect(outputsFile.existsSync(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every unplugged appearance override gets a clearable chip', (
    tester,
  ) async {
    settingsFile.writeAsStringSync(
      const BarSettings(
        revision: 2,
        displayAppearance: {
          'HDMI-A-1': DisplayAppearance(accent: Color(0xff8ab4ff)),
        },
      ).encode(),
    );
    final bloc = _bloc(
      settingsFile: settingsFile,
      outputsFile: outputsFile,
      reported: const <LayerOutput>[
        LayerOutput(name: 'eDP-1', width: 1920, height: 1080),
      ],
    );
    addTearDown(bloc.close);
    await _load(bloc);
    expect(bloc.state.settings.displayAppearance, contains('HDMI-A-1'));
    await _pumpAppearance(tester, bloc);

    final orphan = find.byKey(
      const ValueKey<String>('appearance-target-HDMI-A-1'),
    );
    expect(orphan, findsOneWidget);
    expect(tester.widget<SettingsChoiceChip>(orphan).label, 'HDMI-A-1');
    expect(tester.widget<SettingsChoiceChip>(orphan).selected, isFalse);

    await tester.ensureVisible(orphan);
    await tester.tap(orphan);
    await tester.pump();
    expect(tester.widget<SettingsChoiceChip>(orphan).selected, isTrue);

    final reset = find.byKey(
      const ValueKey<String>('reset-appearance-HDMI-A-1'),
    );
    expect(reset, findsOneWidget);
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(bloc.settings.displayAppearance, isEmpty);
    expect(orphan, findsNothing);
    expect(
      tester
          .widget<SettingsChoiceChip>(
            find.byKey(const ValueKey<String>('appearance-target-all')),
          )
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  test('identical output refresh results compare equal', () {
    const first = LayerOutput(
      name: 'eDP-1',
      viewId: 2,
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
    );
    const second = LayerOutput(
      name: 'eDP-1',
      viewId: 2,
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
    );
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(
      first,
      isNot(const LayerOutput(name: 'eDP-1', width: 1280, height: 720)),
    );
    expect(
      first,
      isNot(const LayerOutput(name: 'HDMI-A-1', width: 1920, height: 1080)),
    );
  });
}

SettingsAppBloc _bloc({
  required File settingsFile,
  required File outputsFile,
  required List<LayerOutput> reported,
}) {
  return SettingsAppBloc(
    socket: _NoBarSettingsTransport(),
    file: FileSettingsTransport(settingsFile, asyncLock: false),
    outputsSocket: _NoBarOutputsTransport(),
    outputsFile: FileOutputsTransport(outputsFile),
    layerShell: _FakeLayerShell(reported),
  );
}

Future<void> _load(SettingsAppBloc bloc) async {
  bloc.add(const SettingsAppLoadRequested());
  await bloc.stream.firstWhere((state) => state.loaded);
}

Future<void> _pumpDisplays(WidgetTester tester, SettingsAppBloc bloc) {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    BlocProvider.value(
      value: bloc,
      child: _keymap(
        const SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: DisplaysPage(),
        ),
      ),
    ),
  );
}

Future<void> _pumpAppearance(WidgetTester tester, SettingsAppBloc bloc) {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    BlocProvider.value(
      value: bloc,
      child: BlocProvider<WallpaperAccentBloc>(
        create: (_) => WallpaperAccentBloc(watch: false),
        child: _keymap(
          const SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: AppearancePage(),
          ),
        ),
      ),
    ),
  );
}

/// The app installs `shellShortcuts` and `FocusScope` itself; the pages need
/// the same Tab traversal and Enter/Space activation wiring in tests.
Widget _keymap(Widget child) {
  return Shortcuts(
    shortcuts: shellShortcuts,
    child: Actions(
      actions: WidgetsApp.defaultActions,
      child: FocusScope(
        autofocus: true,
        child: TricksterLocalizationScope(
          locale: const Locale('en'),
          child: child,
        ),
      ),
    ),
  );
}

/// The focus ring paints only in traditional highlight mode; these tests
/// assert it directly.
void _useKeyboardHighlight() {
  final previous = FocusManager.instance.highlightStrategy;
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = previous);
}

FocusNode _focusNodeIn(WidgetTester tester, Finder root) {
  return tester
      .widget<FocusableActionDetector>(
        find.descendant(
          of: root,
          matching: find.byType(FocusableActionDetector),
        ),
      )
      .focusNode!;
}

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell(this.reported)
    : super(channel: const MethodChannel('test/trickster'));

  final List<LayerOutput> reported;

  @override
  Future<List<LayerOutput>> outputs() async => List<LayerOutput>.of(reported);
}

class _NoBarSettingsTransport implements SettingsDocumentTransport {
  @override
  Future<SettingsDocument> read() async =>
      throw const ControlSocketException('no bar');

  @override
  Future<SettingsDocument> write({
    required int expectedRevision,
    required String document,
  }) async => throw const ControlSocketException('no bar');
}

class _NoBarOutputsTransport implements OutputsDocumentTransport {
  @override
  Future<String> read() async => throw const ControlSocketException('no bar');

  @override
  Future<String> write(String document) async =>
      throw const ControlSocketException('no bar');
}
