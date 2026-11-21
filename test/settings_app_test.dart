import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Scrollbar;
import 'package:trickster/l10n/generated/app_localizations_en.dart';
import 'package:trickster/src/cli.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/wallpaper.dart';
import 'package:trickster/src/settings/app.dart';
import 'package:trickster/src/settings/availability.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/color_format.dart';
import 'package:trickster/src/settings/color_wheel.dart';
import 'package:trickster/src/settings/module_options.dart';
import 'package:trickster/src/settings/modules_bloc.dart';
import 'package:trickster/src/settings/pages/about.dart';
import 'package:trickster/src/settings/pages/modules.dart';
import 'package:trickster/src/settings/saver.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell() : super(channel: const MethodChannel('test/trickster'));

  @override
  Future<List<LayerOutput>> outputs() async => const <LayerOutput>[
    LayerOutput(name: 'eDP-1', width: 1920, height: 1080),
    // A scaled output: 1280x720 logical is a 2560x1440 mode at scale 2.
    LayerOutput(name: 'HDMI-A-1', width: 1280, height: 720, scale: 2),
  ];
}

Future<SettingsAppBloc> _bloc(File file) async {
  final directory = file.parent;
  final bloc = SettingsAppBloc(
    socket: SocketSettingsTransport(
      socketPath: '${directory.path}/no-bar.sock',
    ),
    file: FileSettingsTransport(file),
    outputsSocket: SocketOutputsTransport(
      socketPath: '${directory.path}/no-bar.sock',
    ),
    outputsFile: FileOutputsTransport(File('${directory.path}/outputs.conf')),
    layerShell: _FakeLayerShell(),
  );
  bloc.add(const SettingsAppLoadRequested());
  await bloc.stream.firstWhere((state) => state.loaded);
  return bloc;
}

Future<void> _pump(
  WidgetTester tester,
  SettingsAppBloc bloc, {
  VoidCallback? onClose,
  List<ModuleAvailability> Function()? availabilityProbe,
  Future<List<ModuleAvailability>> Function(BarSettings settings)?
  availabilityLoader,
  Future<List<String>> Function()? workspaceNames,
  bool disableAnimations = false,
  Size size = const Size(980, 720),
  double textScale = 1.0,
  Locale? locale,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    BlocProvider.value(
      value: bloc,
      child: BlocProvider<WallpaperAccentBloc>(
        create: (_) => WallpaperAccentBloc(watch: false),
        child: TricksterLocalizationScope(
          locale: locale,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              disableAnimations: disableAnimations,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (context) => SettingsHome(
                      onClose: onClose,
                      availabilityProbe:
                          availabilityProbe ??
                          () => const <ModuleAvailability>[],
                      availabilityLoader: availabilityLoader,
                      workspaceNames: workspaceNames,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _dragModuleTo(
  WidgetTester tester,
  String module,
  Finder target,
) async {
  final handle = find.byKey(ValueKey<String>('module-drag-$module'));
  await tester.ensureVisible(handle);
  await tester.pumpAndSettle();
  final start = tester.getCenter(handle);
  final initial = tester.getRect(target);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 120));
  // Cross the drag slop first so the recognizer claims the pointer.
  final slop = Offset(0, initial.center.dy >= start.dy ? 24 : -24);
  await gesture.moveBy(slop);
  await tester.pump(const Duration(milliseconds: 60));

  // Let the product's edge auto-scroll bring an off-screen target into the
  // viewport, exactly as a real pointer drag does.
  for (var step = 0; step < 40; step++) {
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final rect = tester.getRect(target);
    if (rect.bottom > viewport.top + 8 && rect.top < viewport.bottom - 8) {
      break;
    }
    final edge = rect.center.dy < viewport.center.dy
        ? viewport.top + 12
        : viewport.bottom - 12;
    await gesture.moveTo(Offset(viewport.center.dx, edge));
    await tester.pump(const Duration(milliseconds: 80));
  }

  final viewport = tester.getRect(find.byType(SingleChildScrollView));
  final rect = tester.getRect(target);
  final end = Offset(
    rect.center.dx.clamp(viewport.left + 8, viewport.right - 8),
    rect.center.dy.clamp(viewport.top + 8, viewport.bottom - 8),
  );
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 60));
  await gesture.up();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Drags [module] to just below [target]'s bottom edge, the append gesture.
Future<void> _dragModuleBelow(
  WidgetTester tester,
  String module,
  Finder target,
) async {
  final handle = find.byKey(ValueKey<String>('module-drag-$module'));
  await tester.ensureVisible(handle);
  await tester.pumpAndSettle();
  final start = tester.getCenter(handle);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 120));
  const slop = Offset(0, 24);
  await gesture.moveBy(slop);
  await tester.pump(const Duration(milliseconds: 60));

  for (var step = 0; step < 40; step++) {
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final rect = tester.getRect(target);
    if (rect.bottom > viewport.top + 8 && rect.top < viewport.bottom - 8) {
      break;
    }
    final edge = rect.center.dy < viewport.center.dy
        ? viewport.top + 12
        : viewport.bottom - 12;
    await gesture.moveTo(Offset(viewport.center.dx, edge));
    await tester.pump(const Duration(milliseconds: 80));
  }

  final viewport = tester.getRect(find.byType(SingleChildScrollView));
  final rect = tester.getRect(target);
  final end = Offset(
    rect.center.dx.clamp(viewport.left + 8, viewport.right - 8),
    (rect.bottom + 12).clamp(viewport.top + 8, viewport.bottom - 8),
  );
  await gesture.moveTo(end);
  await tester.pump(const Duration(milliseconds: 60));
  await gesture.up();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// The modules page's own vertical scroll view.
ScrollableState _pageScroll(WidgetTester tester) {
  return tester.state<ScrollableState>(_pageScrollable());
}

Finder _pageScrollable() {
  return find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
}

Future<void> _openModules(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(SettingsNav),
      matching: find.text('Modules'),
    ),
  );
  await tester.pump();
}

void _expectNoException(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

String _fieldText(WidgetTester tester, Finder field) {
  return tester
      .widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      )
      .controller
      .text;
}

void _blur(WidgetTester tester) {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.binding.scheduleFrame();
}

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('trickster-appearance');
    file = File('${directory.path}/settings.json')
      ..writeAsStringSync(const BarSettings(revision: 2).encode());
  });

  tearDown(() => directory.delete(recursive: true));

  test('placement-only preview emits a new settings state', () async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    final before = bloc.state.settings;
    final expectation = expectLater(
      bloc.stream,
      emits(
        isA<SettingsAppState>().having(
          (state) => state.settings.modulePlacement,
          'modulePlacement',
          {'clock': ModuleZone.leading},
        ),
      ),
    );
    bloc.add(
      SettingsAppPreviewed(
        before.copyWith(modulePlacement: const {'clock': ModuleZone.leading}),
      ),
    );
    await expectation.timeout(const Duration(seconds: 5));
  });

  testWidgets('settings shell shows the appearance page', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    expect(find.text('Trickster Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsWidgets);
    expect(
      find.byKey(const ValueKey<String>('accent-preset-#D0BCFF')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Accent color'), findsOneWidget);
    expect(find.text('#D0BCFF'), findsOneWidget);
  });

  testWidgets('reduced motion zeroes every settings transition', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, disableAnimations: true);

    final containers = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(containers, isNotEmpty);
    for (final container in containers) {
      expect(container.duration, Duration.zero);
    }
    final scales = tester.widgetList<AnimatedScale>(find.byType(AnimatedScale));
    expect(scales, isNotEmpty);
    for (final scale in scales) {
      expect(scale.duration, Duration.zero);
    }
    final aligns = tester.widgetList<AnimatedAlign>(find.byType(AnimatedAlign));
    expect(aligns, isNotEmpty);
    for (final align in aligns) {
      expect(align.duration, Duration.zero);
    }

    // The selected nav entry lands on its first frame: no fill tween.
    final nav = find
        .descendant(
          of: find.byType(SettingsNav),
          matching: find.byType(AnimatedContainer),
        )
        .at(1);
    Color navFill() {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: nav, matching: find.byType(DecoratedBox)).first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    expect(navFill(), SettingsColors.surface);
    await tester.tap(find.bySemanticsLabel('Modules').first);
    await tester.pump();
    expect(navFill(), SettingsColors.surfaceHigh);
  });

  testWidgets('a preset writes the accent after the debounce', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.tap(
      find.byKey(const ValueKey<String>('accent-preset-#8AB4FF')),
    );
    await tester.pump();
    expect(bloc.settings.accent, const Color(0xff8ab4ff));
    expect(file.readAsStringSync(), isNot(contains('8ab4ff')));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(file.readAsStringSync(), contains('8ab4ff'));
    expect(bloc.error, isNull);
  });

  testWidgets('a pending edit is flushed by a section switch', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.tap(
      find.byKey(const ValueKey<String>('accent-preset-#8AB4FF')),
    );
    await tester.pump();
    expect(bloc.settings.accent, const Color(0xff8ab4ff));
    expect(file.readAsStringSync(), isNot(contains('8ab4ff')));

    await tester.tap(find.bySemanticsLabel('Language'));
    await tester.pumpAndSettle();
    expect(file.readAsStringSync(), contains('8ab4ff'));
    expect(bloc.error, isNull);
  });

  testWidgets('a pending edit is flushed when its options panel collapses', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await _openModules(tester);
    await tester.pumpAndSettle();

    final gear = find.byKey(const ValueKey<String>('module-options-clock'));
    await tester.scrollUntilVisible(gear, 160, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    await tester.tap(gear);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('clock-format-24h')));
    await tester.pump();
    expect(bloc.settings.clock.format, ClockFormat.hour24);
    expect(
      BarSettings.decode(file.readAsStringSync()).clock.format,
      isNot(ClockFormat.hour24),
    );

    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(
      BarSettings.decode(file.readAsStringSync()).clock.format,
      ClockFormat.hour24,
    );
  });

  testWidgets('closing flushes the pending edit before onClose', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    var closed = 0;
    await _pump(tester, bloc, onClose: () => closed++);

    await tester.tap(
      find.byKey(const ValueKey<String>('accent-preset-#8AB4FF')),
    );
    await tester.pump();
    expect(file.readAsStringSync(), isNot(contains('8ab4ff')));

    await tester.tap(find.byType(SettingsCloseButton));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(file.readAsStringSync(), contains('8ab4ff'));
  });

  testWidgets('reset clears the accent', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    bloc.add(
      const SettingsAppSaveRequested(
        BarSettings(revision: 2, accent: Color(0xff8ab4ff)),
      ),
    );
    await bloc.stream.firstWhere((state) => !state.busy);
    await _pump(tester, bloc);
    expect(file.readAsStringSync(), contains('8ab4ff'));

    await tester.tap(find.byKey(const ValueKey<String>('reset-accent')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(bloc.settings.accent, isNull);
    expect(file.readAsStringSync(), isNot(contains('8ab4ff')));
  });

  testWidgets('the wheel reports pointer changes', (tester) async {
    final colors = <Color>[];
    await tester.pumpWidget(
      TricksterLocalizationScope(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.square(
              dimension: 160,
              child: HsvColorWheel(
                color: const Color(0xffd0bcff),
                onChanged: colors.add,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byType(HsvColorWheel)));
    await tester.pump();
    expect(colors, isNotEmpty);
    expect(colors.last, isNot(const Color(0xffd0bcff)));
  });

  testWidgets('modules page toggles and reorders the strip', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();
    expect(
      find.text('Choose which pills the bar shows and in what order.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('module-toggle-gpu')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('module-toggle-gpu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('module-toggle-gpu')));
    await tester.pump();
    expect(bloc.settings.modules, isNot(contains('gpu')));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      BarSettings.decode(file.readAsStringSync()).modules,
      isNot(contains('gpu')),
    );

    final before = List<String>.of(bloc.settings.modules);
    await _dragModuleTo(
      tester,
      'clock',
      find.byKey(const ValueKey<String>('module-battery')),
    );
    expect(
      bloc.settings.modules.indexOf('clock'),
      lessThan(before.indexOf('clock')),
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final decoded = BarSettings.decode(file.readAsStringSync());
    expect(decoded.modules.indexOf('clock'), lessThan(before.indexOf('clock')));

    await _dragModuleTo(
      tester,
      'clock',
      find.byKey(const ValueKey<String>('module-tray')),
    );
    expect(bloc.settings.zoneFor('clock'), ModuleZone.leading);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(file.readAsStringSync(), contains('"module_placement"'));
    expect(
      BarSettings.decode(file.readAsStringSync()).zoneFor('clock'),
      ModuleZone.leading,
    );
  });

  testWidgets('modules page lays out at real surfaces', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    for (final size in const [
      Size(900, 600),
      Size(1280, 800),
      Size(1920, 1080),
    ]) {
      await _pump(tester, bloc, size: size);
      await _openModules(tester);
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(SettingsHome)), size);
      expect(find.byType(Scrollbar), findsOneWidget);
      expect(
        tester.getSize(find.byType(ModulesPage)).width,
        lessThanOrEqualTo(SettingsHome.maxContentWidth),
      );
      _expectNoException(tester);

      if (size.width == 900) {
        expect(_pageScroll(tester).position.maxScrollExtent, greaterThan(0));
      }
      for (final module in BarSettings.knownModules) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey<String>('module-$module')),
          120,
          scrollable: _pageScrollable(),
        );
        await tester.pump();
        expect(find.byKey(ValueKey<String>('module-$module')), findsOneWidget);
        _expectNoException(tester);
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('module-zone-disabled')),
        120,
        scrollable: _pageScrollable(),
      );
      await tester.pump();
      expect(find.text('Drop a module here'), findsWidgets);
      _expectNoException(tester);
    }
  });

  testWidgets('opening a bottom-row gear reveals its panel', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, size: const Size(900, 600));
    await _openModules(tester);
    await tester.pumpAndSettle();

    final gear = find.byKey(const ValueKey<String>('module-options-opencode'));
    await tester.scrollUntilVisible(gear, 160, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    await tester.tap(gear);
    await tester.pumpAndSettle();

    final panel = find.byType(ModuleOptionsPanel);
    expect(panel, findsOneWidget);
    final panelRect = tester.getRect(panel);
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    expect(panelRect.top, lessThan(viewport.bottom));
    expect(panelRect.bottom, greaterThan(viewport.top));
    expect(panelRect.top, greaterThanOrEqualTo(viewport.top - 1));
    _expectNoException(tester);
  });

  testWidgets('module catalog, order, and gears stay complete', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, size: const Size(900, 600));
    await _openModules(tester);
    await tester.pumpAndSettle();

    final l10n = AppLocalizationsEn();
    for (final module in BarSettings.knownModules) {
      expect(
        find.text(moduleLabel(l10n, module)),
        findsOneWidget,
        reason: 'missing label for $module',
      );
      expect(
        find.byKey(ValueKey<String>('module-toggle-$module')),
        findsOneWidget,
        reason: 'missing toggle for $module',
      );
      final gear = find.byKey(ValueKey<String>('module-options-$module'));
      if (moduleHasOptions(module)) {
        expect(gear, findsOneWidget, reason: 'missing gear for $module');
      } else {
        expect(gear, findsNothing, reason: 'unexpected gear for $module');
      }
    }

    final groups = moduleGroups(const BarSettings(), const []);
    for (final entry in groups.entries) {
      var previous = double.negativeInfinity;
      for (final module in entry.value) {
        final y = tester
            .getTopLeft(find.byKey(ValueKey<String>('module-$module')))
            .dy;
        expect(y, greaterThan(previous), reason: '${entry.key.wire} order');
        previous = y;
      }
    }
    _expectNoException(tester);
  });

  testWidgets('disabled modules keep options and prune the expanded panel', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, size: const Size(900, 600));
    await _openModules(tester);
    await tester.pumpAndSettle();

    final gear = find.byKey(const ValueKey<String>('module-options-network'));
    await tester.scrollUntilVisible(gear, 160, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(find.byType(ModuleOptionsPanel), findsOneWidget);

    final toggle = find.byKey(const ValueKey<String>('module-toggle-network'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(bloc.settings.modules, isNot(contains('network')));
    expect(find.byType(ModuleOptionsPanel), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('module-zone-disabled')),
      160,
      scrollable: _pageScrollable(),
    );
    final disabledGear = find.byKey(
      const ValueKey<String>('module-options-network'),
    );
    await tester.scrollUntilVisible(
      disabledGear,
      160,
      scrollable: _pageScrollable(),
    );
    expect(disabledGear, findsOneWidget);
    await tester.tap(disabledGear);
    await tester.pumpAndSettle();
    expect(find.byType(ModuleOptionsPanel), findsOneWidget);
    _expectNoException(tester);
  });

  testWidgets('gear and module toggle activate from the keyboard', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, size: const Size(900, 600));
    await _openModules(tester);
    await tester.pumpAndSettle();

    final gear = find.byKey(const ValueKey<String>('module-options-network'));
    final gearAction = tester.widget<FocusableActionDetector>(
      find.descendant(of: gear, matching: find.byType(FocusableActionDetector)),
    );
    gearAction.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(ModuleOptionsPanel), findsOneWidget);

    final toggle = find.byKey(const ValueKey<String>('module-toggle-network'));
    final toggleAction = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: toggle,
        matching: find.byType(FocusableActionDetector),
      ),
    );
    toggleAction.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(bloc.settings.modules, isNot(contains('network')));
  });

  testWidgets('an availability refresh prunes a vanished options panel', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    final refresh = Completer<List<ModuleAvailability>>();
    await _pump(
      tester,
      bloc,
      size: const Size(900, 600),
      availabilityProbe: () => const <ModuleAvailability>[],
      availabilityLoader: (_) => refresh.future,
    );
    await _openModules(tester);
    await tester.pumpAndSettle();

    final gear = find.byKey(const ValueKey<String>('module-options-clock'));
    await tester.scrollUntilVisible(gear, 160, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(find.byType(ModuleOptionsPanel), findsOneWidget);

    refresh.complete(const [
      ModuleAvailability(
        module: 'clock',
        reason: ModuleUnavailableReason.noBattery,
      ),
    ]);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(ModuleOptionsPanel), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('module-unavailable-clock')),
      findsOneWidget,
    );
  });

  testWidgets('keyboard drag handle reorders and changes zone', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, size: const Size(900, 600));
    await _openModules(tester);
    await tester.pumpAndSettle();

    final handle = find.byKey(const ValueKey<String>('module-drag-clock'));
    await tester.scrollUntilVisible(handle, 120, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    await tester.tap(handle);
    await tester.pump();

    final before = List<String>.of(bloc.settings.modules);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      bloc.settings.modules.indexOf('clock'),
      lessThan(before.indexOf('clock')),
    );

    await tester.tap(handle);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(bloc.settings.zoneFor('clock'), ModuleZone.center);
  });

  testWidgets('dragging near the page edge auto-scrolls to leading', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, size: const Size(900, 600));
    await _openModules(tester);
    await tester.pumpAndSettle();

    final handle = find.byKey(const ValueKey<String>('module-drag-clock'));
    await tester.scrollUntilVisible(handle, 160, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    final scroll = _pageScroll(tester);
    final before = scroll.position.pixels;
    expect(before, greaterThan(0));

    final start = tester.getCenter(handle);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 60));
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    await gesture.moveTo(Offset(viewport.center.dx, viewport.top + 12));
    await tester.pump(const Duration(milliseconds: 500));

    expect(scroll.position.pixels, lessThan(before));
    final tray = find.byKey(const ValueKey<String>('module-tray'));
    final trayCenter = tester.getCenter(tray);
    expect(trayCenter.dy, inInclusiveRange(0, 600));
    expect(trayCenter.dx, inInclusiveRange(0, 900));

    await gesture.moveTo(trayCenter);
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(bloc.settings.zoneFor('clock'), ModuleZone.leading);
    _expectNoException(tester);
  });

  testWidgets('modules page survives text scaling with unavailable rows', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(
      tester,
      bloc,
      size: const Size(900, 600),
      textScale: 2,
      availabilityProbe: () => const [
        ModuleAvailability(
          module: 'battery',
          reason: ModuleUnavailableReason.noBattery,
        ),
        ModuleAvailability(
          module: 'vram',
          reason: ModuleUnavailableReason.noVram,
        ),
        ModuleAvailability(
          module: 'temperature',
          reason: ModuleUnavailableReason.noTemperature,
        ),
        ModuleAvailability(
          module: 'disk',
          reason: ModuleUnavailableReason.noDisk,
        ),
        ModuleAvailability(
          module: 'network',
          reason: ModuleUnavailableReason.noNetwork,
        ),
        ModuleAvailability(
          module: 'keyboard_layout',
          reason: ModuleUnavailableReason.noHyprland,
        ),
      ],
    );
    await _openModules(tester);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('module-zone-unavailable')),
      160,
      scrollable: _pageScrollable(),
    );
    await tester.pump();
    _expectNoException(tester);
    expect(find.text('No dedicated GPU memory detected'), findsOneWidget);
    expect(find.text('No temperature sensor detected'), findsOneWidget);
    expect(find.text('Configured disk path is unavailable'), findsOneWidget);
    expect(find.text('No network interface detected'), findsOneWidget);

    final gear = find.byKey(const ValueKey<String>('module-options-ram'));
    await tester.scrollUntilVisible(gear, 160, scrollable: _pageScrollable());
    await tester.pumpAndSettle();
    await tester.tap(gear);
    await tester.pumpAndSettle();
    _expectNoException(tester);
  });

  testWidgets('meter sliders announce real units', (tester) async {
    final handle = tester.ensureSemantics();
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, size: const Size(900, 600));
    await _openModules(tester);
    await tester.pumpAndSettle();

    Future<void> open(String module) async {
      final gear = find.byKey(ValueKey<String>('module-options-$module'));
      await tester.scrollUntilVisible(gear, 160, scrollable: _pageScrollable());
      await tester.pumpAndSettle();
      await tester.tap(gear);
      await tester.pumpAndSettle();
    }

    await open('ram');
    expect(
      tester.getSemantics(find.byKey(const ValueKey('options-ram-warn'))).value,
      '85%',
    );
    await open('temperature');
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('options-temperature-warn')))
          .value,
      '80°C',
    );
    handle.dispose();
  });

  testWidgets('disk and network fields reset and reject invalid text', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, size: const Size(900, 600));
    await _openModules(tester);
    await tester.pumpAndSettle();

    Future<void> open(String module) async {
      final gear = find.byKey(ValueKey<String>('module-options-$module'));
      await tester.scrollUntilVisible(gear, 160, scrollable: _pageScrollable());
      await tester.pumpAndSettle();
      await tester.tap(gear);
      await tester.pumpAndSettle();
    }

    await open('disk');
    final path = find.byKey(const ValueKey<String>('disk-path'));
    await tester.enterText(path, '/data');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(bloc.settings.disk.path, '/data');

    final resetPath = find.byKey(const ValueKey<String>('reset-disk-path'));
    await tester.ensureVisible(resetPath);
    await tester.pumpAndSettle();
    await tester.tap(resetPath);
    await tester.pumpAndSettle();
    expect(bloc.settings.disk.path, '/');
    expect(_fieldText(tester, path), '/');

    await tester.enterText(path, 'relative');
    await tester.pump();
    expect(find.text('Use an absolute mount path'), findsOneWidget);
    expect(bloc.settings.disk.path, '/');
    _blur(tester);
    await tester.pumpAndSettle();
    expect(_fieldText(tester, path), '/');

    await open('network');
    final interface = find.byKey(const ValueKey<String>('network-interface'));
    await tester.enterText(interface, 'wlan0');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(bloc.settings.network.interface, 'wlan0');
    final resetInterface = find.byKey(
      const ValueKey<String>('reset-network-interface'),
    );
    await tester.ensureVisible(resetInterface);
    await tester.pumpAndSettle();
    await tester.tap(resetInterface);
    await tester.pumpAndSettle();
    expect(bloc.settings.network.interface, isNull);

    await tester.enterText(interface, 'bad name!');
    await tester.pump();
    expect(find.text('Use a valid Linux interface name'), findsOneWidget);
    expect(bloc.settings.network.interface, isNull);
    _blur(tester);
    await tester.pumpAndSettle();
    expect(_fieldText(tester, interface), '');
  });

  testWidgets('every module option resets to its default', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    expect(find.text('Video memory'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Disk'), findsOneWidget);
    expect(find.text('Keyboard layout'), findsOneWidget);
    expect(find.text('Network'), findsOneWidget);

    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    Future<void> openOptions(String module) async {
      final gear = find.byKey(ValueKey<String>('module-options-$module'));
      await tester.ensureVisible(gear);
      await tester.pumpAndSettle();
      await tester.tap(gear);
      await tester.pumpAndSettle();
    }

    Future<void> nudgeToMax(String sliderKey) async {
      await tester.ensureVisible(find.byKey(ValueKey<String>(sliderKey)));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(ValueKey<String>(sliderKey)));
      await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
      await tester.pump();
      await settle();
    }

    Future<void> reset(String resetKey) async {
      await tester.ensureVisible(find.byKey(ValueKey<String>(resetKey)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(resetKey)));
      await tester.pump();
      await settle();
    }

    await openOptions('clock');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('clock-format-24h')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('clock-format-24h')));
    await tester.pump();
    await settle();
    expect(bloc.settings.clock.format, ClockFormat.hour24);
    await reset('reset-clock-format');
    expect(bloc.settings.clock.format, const ClockOptions().format);

    await openOptions('cpu');
    await nudgeToMax('options-cpu-warn');
    await reset('reset-cpu-warn');
    expect(bloc.settings.cpu.warn, const CpuOptions().warn);
    await reset('reset-cpu-critical');
    expect(bloc.settings.cpu.critical, const CpuOptions().critical);

    await openOptions('ram');
    await nudgeToMax('options-ram-warn');
    await reset('reset-ram-warn');
    expect(bloc.settings.ram.warn, const RamOptions().warn);
    await reset('reset-ram-critical');
    expect(bloc.settings.ram.critical, const RamOptions().critical);
    expect(
      find.byKey(const ValueKey<String>('ram-meter-caption-device')),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('ram-meter-caption-custom')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('ram-meter-caption-custom')),
    );
    await tester.pump();
    await settle();
    expect(bloc.settings.ram.captionSource, MeterCaptionSource.custom);
    await reset('reset-ram-meter-caption');
    expect(bloc.settings.ram.captionSource, MeterCaptionSource.generic);

    await openOptions('temperature');
    await nudgeToMax('options-temperature-warn');
    await reset('reset-temperature-warn');
    expect(bloc.settings.temperature.warn, const TemperatureOptions().warn);
    await reset('reset-temperature-critical');
    expect(
      bloc.settings.temperature.critical,
      const TemperatureOptions().critical,
    );
    expect(
      find.byKey(const ValueKey<String>('temperature-meter-caption-device')),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('temperature-meter-caption-custom')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('temperature-meter-caption-custom')),
    );
    await tester.pump();
    await settle();
    expect(bloc.settings.temperature.captionSource, MeterCaptionSource.custom);
    await reset('reset-temperature-meter-caption');
    expect(bloc.settings.temperature.captionSource, MeterCaptionSource.generic);

    await openOptions('disk');
    final pathField = find.byKey(const ValueKey<String>('disk-path'));
    await tester.ensureVisible(pathField);
    await tester.pumpAndSettle();
    await tester.enterText(pathField, '/data');
    await tester.pump();
    await settle();
    expect(bloc.settings.disk.path, '/data');
    await nudgeToMax('options-disk-warn');
    await reset('reset-disk-warn');
    expect(bloc.settings.disk.warn, const DiskOptions().warn);
    await reset('reset-disk-critical');
    expect(bloc.settings.disk.critical, const DiskOptions().critical);

    await openOptions('network');
    final interfaceField = find.byKey(
      const ValueKey<String>('network-interface'),
    );
    await tester.ensureVisible(interfaceField);
    await tester.pumpAndSettle();
    await tester.enterText(interfaceField, 'wlan0');
    await tester.pump();
    await settle();
    expect(bloc.settings.network.interface, 'wlan0');
    final ratesToggle = find.byKey(
      const ValueKey<String>('network-show-rates'),
    );
    await tester.ensureVisible(ratesToggle);
    await tester.pumpAndSettle();
    await tester.tap(ratesToggle);
    await tester.pump();
    await settle();
    expect(bloc.settings.network.showRates, isFalse);
    await reset('reset-network-show-rates');
    expect(bloc.settings.network.showRates, isTrue);
    await tester.enterText(interfaceField, '');
    await tester.pump();
    await settle();
    expect(bloc.settings.network.interface, isNull);

    await openOptions('vram');
    await nudgeToMax('options-vram-warn');
    await reset('reset-vram-warn');
    expect(bloc.settings.vram.warn, const VramOptions().warn);
    await reset('reset-vram-critical');
    expect(bloc.settings.vram.critical, const VramOptions().critical);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('vram-meter-caption-device')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('vram-meter-caption-device')),
    );
    await tester.pump();
    await settle();
    expect(bloc.settings.vram.captionSource, MeterCaptionSource.device);
    await reset('reset-vram-meter-caption');
    expect(bloc.settings.vram.captionSource, MeterCaptionSource.generic);

    await openOptions('battery');
    await nudgeToMax('options-battery-warn');
    await reset('reset-battery-warn');
    expect(bloc.settings.battery.warn, const BatteryOptions().warn);
    await reset('reset-battery-critical');
    expect(bloc.settings.battery.critical, const BatteryOptions().critical);

    await openOptions('gpu');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('gpu-meter-caption-device')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('gpu-meter-caption-device')),
    );
    await tester.pump();
    await settle();
    expect(bloc.settings.gpu.captionSource, MeterCaptionSource.device);
    await reset('reset-gpu-meter-caption');
    expect(bloc.settings.gpu.captionSource, const GpuOptions().captionSource);

    final decoded = BarSettings.decode(file.readAsStringSync());
    expect(decoded.clock.format, const ClockOptions().format);
    expect(decoded.cpu.warn, const CpuOptions().warn);
    expect(decoded.cpu.critical, const CpuOptions().critical);
    expect(decoded.ram.warn, const RamOptions().warn);
    expect(decoded.ram.critical, const RamOptions().critical);
    expect(decoded.temperature.warn, const TemperatureOptions().warn);
    expect(decoded.temperature.critical, const TemperatureOptions().critical);
    expect(decoded.disk.path, '/data');
    expect(decoded.disk.warn, const DiskOptions().warn);
    expect(decoded.disk.critical, const DiskOptions().critical);
    expect(decoded.network.interface, isNull);
    expect(decoded.network.showRates, isTrue);
    expect(decoded.vram.warn, const VramOptions().warn);
    expect(decoded.vram.critical, const VramOptions().critical);
    expect(decoded.battery.warn, const BatteryOptions().warn);
    expect(decoded.battery.critical, const BatteryOptions().critical);
    expect(decoded.gpu.captionSource, const GpuOptions().captionSource);

    await tester.tap(find.bySemanticsLabel('Language'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('language-zh')));
    await tester.pump();
    await settle();
    expect(bloc.settings.locale, 'zh');
    await reset('reset-locale');
    expect(bloc.settings.locale, isNull);
    expect(BarSettings.decode(file.readAsStringSync()).locale, isNull);
  });

  testWidgets('meter thresholds keep one step at the slider ends', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    Future<void> openOptions(String module) async {
      final gear = find.byKey(ValueKey<String>('module-options-$module'));
      await tester.ensureVisible(gear);
      await tester.pumpAndSettle();
      await tester.tap(gear);
      await tester.pumpAndSettle();
    }

    Future<void> tapEdge(String sliderKey, {required bool right}) async {
      final slider = find.byKey(ValueKey<String>(sliderKey));
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final rect = tester.getRect(slider);
      // Drive the endpoint itself, not a point safely inside it. This is the
      // boundary that used to collapse warn == critical.
      await tester.tapAt(
        Offset(right ? rect.right - 0.001 : rect.left + 0.001, rect.center.dy),
      );
      await tester.pump();
      await settle();
    }

    Future<void> reset(String resetKey) async {
      final button = find.byKey(ValueKey<String>(resetKey));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      await settle();
    }

    for (final module in [
      'cpu',
      'gpu',
      'disk',
      'ram',
      'vram',
      'temperature',
      'battery',
    ]) {
      bool ordered(BarSettings decoded) => switch (module) {
        'cpu' => decoded.cpu.warn < decoded.cpu.critical,
        'gpu' => decoded.gpu.warn < decoded.gpu.critical,
        'disk' => decoded.disk.warn < decoded.disk.critical,
        'ram' => decoded.ram.warn < decoded.ram.critical,
        'vram' => decoded.vram.warn < decoded.vram.critical,
        'battery' => decoded.battery.warn > decoded.battery.critical,
        _ => decoded.temperature.warn < decoded.temperature.critical,
      };

      await openOptions(module);
      await tapEdge('options-$module-warn', right: true);
      var decoded = BarSettings.decode(file.readAsStringSync());
      switch (module) {
        case 'cpu':
          expect(decoded.cpu.warn, closeTo(0.99, 1e-9));
          expect(decoded.cpu.critical, closeTo(1.0, 1e-9));
        case 'gpu':
          expect(decoded.gpu.warn, closeTo(0.99, 1e-9));
          expect(decoded.gpu.critical, closeTo(1.0, 1e-9));
        case 'disk':
          expect(decoded.disk.warn, closeTo(0.99, 1e-9));
          expect(decoded.disk.critical, closeTo(1.0, 1e-9));
        case 'ram':
          expect(decoded.ram.warn, closeTo(0.99, 1e-9));
          expect(decoded.ram.critical, closeTo(1.0, 1e-9));
        case 'vram':
          expect(decoded.vram.warn, closeTo(0.99, 1e-9));
          expect(decoded.vram.critical, closeTo(1.0, 1e-9));
        case 'temperature':
          expect(decoded.temperature.warn, 149);
          expect(decoded.temperature.critical, 150);
        case 'battery':
          expect(decoded.battery.warn, 100);
          expect(decoded.battery.critical, 10);
      }
      expect(ordered(decoded), isTrue);

      // Reset the neighbor while warning is pinned at its maximum.
      await reset('reset-$module-critical');
      decoded = BarSettings.decode(file.readAsStringSync());
      expect(ordered(decoded), isTrue);

      await tapEdge('options-$module-critical', right: false);
      decoded = BarSettings.decode(file.readAsStringSync());
      switch (module) {
        case 'cpu':
          expect(decoded.cpu.warn, 0);
          expect(decoded.cpu.critical, closeTo(0.01, 1e-9));
        case 'gpu':
          expect(decoded.gpu.warn, 0);
          expect(decoded.gpu.critical, closeTo(0.01, 1e-9));
        case 'disk':
          expect(decoded.disk.warn, 0);
          expect(decoded.disk.critical, closeTo(0.01, 1e-9));
        case 'ram':
          expect(decoded.ram.warn, 0);
          expect(decoded.ram.critical, closeTo(0.01, 1e-9));
        case 'vram':
          expect(decoded.vram.warn, 0);
          expect(decoded.vram.critical, closeTo(0.01, 1e-9));
        case 'temperature':
          expect(decoded.temperature.warn, 0);
          expect(decoded.temperature.critical, 1);
        case 'battery':
          expect(decoded.battery.warn, 100);
          expect(decoded.battery.critical, 1);
      }
      expect(ordered(decoded), isTrue);

      // Reset warning while critical is pinned at its minimum.
      await reset('reset-$module-warn');
      decoded = BarSettings.decode(file.readAsStringSync());
      expect(ordered(decoded), isTrue);
    }
  });

  testWidgets('displays page writes placement and output selection', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.tap(find.bySemanticsLabel('Displays'));
    await tester.pump();
    expect(find.text('eDP-1  1920×1080'), findsOneWidget);
    expect(find.text('HDMI-A-1  2560×1440'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('side-bottom')));
    await tester.pumpAndSettle();
    final outputs = File('${directory.path}/outputs.conf');
    expect(outputs.readAsStringSync(), contains('system_bar=bottom,32'));

    await tester.tap(find.byKey(const ValueKey<String>('output-eDP-1')));
    await tester.pumpAndSettle();
    expect(
      outputs.readAsStringSync(),
      contains('system_bar=bottom,32,HDMI-A-1'),
    );

    await tester.tap(find.byKey(const ValueKey<String>('output-eDP-1')));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), contains('system_bar=bottom,32\n'));
  });

  testWidgets('drag preview follows the hovered half of the row', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    final handle = find.byKey(const ValueKey<String>('module-drag-gpu'));
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 60));

    final battery = find.byKey(const ValueKey<String>('module-battery'));
    final preview = find.byKey(const ValueKey<String>('module-drop-preview'));

    // The lower half lands the gap below the hovered row.
    var batteryRect = tester.getRect(battery);
    await gesture.moveTo(
      batteryRect.center + Offset(0, batteryRect.height * 0.28),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(preview, findsOneWidget);
    batteryRect = tester.getRect(battery);
    expect(tester.getCenter(preview).dy, greaterThan(batteryRect.center.dy));

    // The upper half lands it above.
    batteryRect = tester.getRect(battery);
    await gesture.moveTo(
      batteryRect.center - Offset(0, batteryRect.height * 0.28),
    );
    await tester.pump(const Duration(milliseconds: 60));
    batteryRect = tester.getRect(battery);
    expect(tester.getCenter(preview).dy, lessThan(batteryRect.center.dy));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the first drag shows the proxy at segment width', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    final handle = find.byKey(const ValueKey<String>('module-drag-clock'));
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 60));

    final feedback = find.byKey(const ValueKey<String>('module-drag-feedback'));
    expect(feedback, findsOneWidget);
    expect(tester.getSize(feedback).width, greaterThan(300));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('mouse drag from the row body reorders', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    final before = List<String>.of(bloc.settings.modules);
    final row = find.byKey(const ValueKey<String>('module-clock'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    final start = tester.getCenter(row);
    final target = tester.getCenter(
      find.byKey(const ValueKey<String>('module-battery')),
    );
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveTo(target);
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      bloc.settings.modules.indexOf('clock'),
      lessThan(before.indexOf('clock')),
    );
  });

  testWidgets('dragging previews the landing slot before release', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    final before = List<String>.of(bloc.settings.modules);
    final handle = find.byKey(const ValueKey<String>('module-drag-clock'));
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    final start = tester.getCenter(handle);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey<String>('module-battery'))),
    );
    await tester.pump(const Duration(milliseconds: 60));

    // The lifted row leaves its slot and the landing slot previews.
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('module-clock'))).height,
      0,
    );
    expect(
      find.byKey(const ValueKey<String>('module-drop-preview')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('module-drop-preview')),
      findsNothing,
    );
    expect(
      bloc.settings.modules.indexOf('clock'),
      lessThan(before.indexOf('clock')),
    );
  });

  testWidgets('absent hardware lands in the unavailable segment', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(
      tester,
      bloc,
      availabilityProbe: () => const [
        ModuleAvailability(
          module: 'battery',
          reason: ModuleUnavailableReason.noBattery,
        ),
        ModuleAvailability(
          module: 'vram',
          reason: ModuleUnavailableReason.noVram,
        ),
        ModuleAvailability(
          module: 'keyboard_layout',
          reason: ModuleUnavailableReason.noHyprland,
        ),
      ],
    );
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    final unavailable = find.byKey(
      const ValueKey<String>('module-zone-unavailable'),
    );
    expect(unavailable, findsOneWidget);
    final battery = find.byKey(
      const ValueKey<String>('module-unavailable-battery'),
    );
    expect(battery, findsOneWidget);
    expect(find.text('No battery detected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('module-unavailable-vram')),
      findsOneWidget,
    );
    expect(find.text('No dedicated GPU memory detected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('module-unavailable-keyboard_layout')),
      findsOneWidget,
    );
    expect(find.text('Hyprland session not detected'), findsOneWidget);
    // The battery is not offered as a toggle in a zone segment.
    expect(
      find.byKey(const ValueKey<String>('module-toggle-battery')),
      findsNothing,
    );
    expect(
      tester.getCenter(battery).dy,
      greaterThan(tester.getCenter(unavailable).dy),
    );
  });

  testWidgets('modules group by placement zone', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    final leading = find.byKey(const ValueKey<String>('module-zone-leading'));
    final center = find.byKey(const ValueKey<String>('module-zone-center'));
    expect(leading, findsOneWidget);
    expect(center, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('module-zone-trailing')),
      findsOneWidget,
    );

    final leadingY = tester.getCenter(leading).dy;
    final centerY = tester.getCenter(center).dy;
    final trayY = tester
        .getCenter(find.byKey(const ValueKey<String>('module-tray')))
        .dy;
    expect(trayY, greaterThan(leadingY));
    expect(trayY, lessThan(centerY));

    // Dragging the tray onto the center segment re-segments it.
    await _dragModuleTo(
      tester,
      'tray',
      find.byKey(const ValueKey<String>('module-workspaces')),
    );
    final movedTray = tester
        .getCenter(find.byKey(const ValueKey<String>('module-tray')))
        .dy;
    final movedCenterY = tester.getCenter(center).dy;
    expect(movedTray, greaterThan(movedCenterY));

    // Turning a module off moves it to the Disabled segment.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('module-toggle-gpu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('module-toggle-gpu')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final disabled = find.byKey(const ValueKey<String>('module-zone-disabled'));
    expect(disabled, findsOneWidget);
    final disabledY = tester.getCenter(disabled).dy;
    final gpuY = tester
        .getCenter(find.byKey(const ValueKey<String>('module-gpu')))
        .dy;
    expect(gpuY, greaterThan(disabledY));
  });

  testWidgets('dropping below the last row appends', (tester) async {
    file.writeAsStringSync(
      '{"revision": 1, "modules": ["workspaces", "cpu", "battery"]}',
    );
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    // The empty leading zone carries the hint; populated zones do not.
    expect(find.text('Drop a module here'), findsWidgets);

    await _dragModuleBelow(
      tester,
      'workspaces',
      find.byKey(const ValueKey<String>('module-battery')),
    );
    expect(bloc.settings.zoneFor('workspaces'), ModuleZone.trailing);
    expect(bloc.settings.modules.last, 'workspaces');
  });

  testWidgets('a hidden module never shifts the drop index', (tester) async {
    file.writeAsStringSync(
      '{"revision": 1, "modules": ["battery", "cpu", "gpu"]}',
    );
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(
      tester,
      bloc,
      availabilityProbe: () => const [
        ModuleAvailability(
          module: 'battery',
          reason: ModuleUnavailableReason.noBattery,
        ),
      ],
    );
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    // Battery is hidden in the unavailable segment; cpu is the first visible
    // trailing row. Dropping below the last visible row must append after
    // gpu, not land one row early because battery still sits in the document.
    await _dragModuleBelow(
      tester,
      'cpu',
      find.byKey(const ValueKey<String>('module-gpu')),
    );
    expect(
      bloc.settings.modules.indexOf('cpu'),
      greaterThan(bloc.settings.modules.indexOf('gpu')),
    );
  });

  testWidgets('a disabled module drags to the end of trailing', (tester) async {
    file.writeAsStringSync(
      '{"revision": 1, "modules": ["workspaces", "cpu", "battery"]}',
    );
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();
    expect(bloc.settings.modules, isNot(contains('gpu')));

    await _dragModuleBelow(
      tester,
      'gpu',
      find.byKey(const ValueKey<String>('module-battery')),
    );
    expect(bloc.settings.modules, contains('gpu'));
    expect(bloc.settings.modules.last, 'gpu');
    expect(bloc.settings.zoneFor('gpu'), ModuleZone.trailing);
  });

  testWidgets('a module appends to the end of its own zone', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    // Trailing holds media, cpu, gpu, battery, clock, opencode; media goes
    // last.
    await _dragModuleBelow(
      tester,
      'media',
      find.byKey(const ValueKey<String>('module-opencode')),
    );
    expect(bloc.settings.zoneFor('media'), ModuleZone.trailing);
    expect(bloc.settings.modules.last, 'media');
  });

  testWidgets('the disabled section stays visible and accepts a drop', (
    tester,
  ) async {
    file.writeAsStringSync(
      '{"revision": 1, "modules": ["workspaces", "cpu", "battery"]}',
    );
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    // Present with the hint while everything is enabled.
    expect(
      find.byKey(const ValueKey<String>('module-zone-disabled')),
      findsOneWidget,
    );
    expect(find.text('Drop a module here'), findsWidgets);

    // Dragging the battery onto it turns the module off.
    await _dragModuleTo(
      tester,
      'battery',
      find.byKey(const ValueKey<String>('module-zone-disabled-drop')),
    );
    expect(bloc.settings.modules, isNot(contains('battery')));
    expect(
      find.byKey(const ValueKey<String>('module-battery')),
      findsOneWidget,
    );
  });

  testWidgets('a disabled module drags out to a zone', (tester) async {
    file.writeAsStringSync(
      '{"revision": 1, "modules": ["workspaces", "cpu", "battery"]}',
    );
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();
    expect(bloc.settings.modules, isNot(contains('gpu')));

    // Drag the disabled GPU row to the empty leading zone.
    await _dragModuleTo(
      tester,
      'gpu',
      find.byKey(const ValueKey<String>('module-zone-leading')),
    );
    expect(bloc.settings.modules, contains('gpu'));
    expect(bloc.settings.zoneFor('gpu'), ModuleZone.leading);
  });

  testWidgets('appearance resets restore the accent defaults', (tester) async {
    file.writeAsStringSync(
      '{"revision": 1, "accent_source": "wallpaper", '
      '"accent_wallpaper_pick": "#2050E0"}',
    );
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    Future<void> reset(String key) async {
      await tester.ensureVisible(find.byKey(ValueKey<String>(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await tester.pump();
      await settle();
    }

    expect(bloc.settings.accentWallpaperPick, '#2050E0');
    await reset('reset-wallpaper-pick');
    expect(bloc.settings.accentWallpaperPick, isNull);

    await reset('reset-accent-source');
    expect(bloc.settings.accentSource, AccentSource.custom);

    final preset = ValueKey<String>(
      'accent-preset-${formatOpaqueColorHex(const Color(0xff8ab4ff))}',
    );
    await tester.ensureVisible(find.byKey(preset));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(preset));
    await settle();
    expect(bloc.settings.accent, const Color(0xff8ab4ff));
    await reset('reset-accent');
    expect(bloc.settings.accent, isNull);

    final decoded = BarSettings.decode(file.readAsStringSync());
    expect(decoded.accent, isNull);
    expect(decoded.accentSource, AccentSource.custom);
    expect(decoded.accentWallpaperPick, isNull);
  });

  testWidgets('module resets restore order and placement', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    Future<void> settle() async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }

    Future<void> reset(String key) async {
      await tester.ensureVisible(find.byKey(ValueKey<String>(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await tester.pump();
      await settle();
    }

    await _dragModuleTo(
      tester,
      'clock',
      find.byKey(const ValueKey<String>('module-battery')),
    );
    await _dragModuleTo(
      tester,
      'tray',
      find.byKey(const ValueKey<String>('module-workspaces')),
    );
    expect(bloc.settings.modules, isNot(BarSettings.knownModules));
    expect(bloc.settings.zoneFor('tray'), ModuleZone.center);

    await reset('reset-modules');
    expect(bloc.settings.modules, BarSettings.knownModules);
    expect(bloc.settings.zoneFor('tray'), ModuleZone.leading);

    final decoded = BarSettings.decode(file.readAsStringSync());
    expect(decoded.modules, BarSettings.knownModules);
    expect(decoded.modulePlacement, isEmpty);
  });

  testWidgets('display resets restore edge, thickness, and outputs', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Displays'));
    await tester.pump();

    final outputs = File('${directory.path}/outputs.conf');
    await tester.tap(find.byKey(const ValueKey<String>('side-bottom')));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), contains('system_bar=bottom,32'));

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('reset-side')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reset-side')));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), contains('system_bar=top,32'));

    final slider = find.byKey(const ValueKey<String>('thickness-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), isNot(contains('system_bar=top,32\n')));

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('reset-thickness')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reset-thickness')));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), contains('system_bar=top,32\n'));

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('output-eDP-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('output-eDP-1')));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), contains('HDMI-A-1'));

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('reset-outputs')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('reset-outputs')));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), isNot(contains('HDMI-A-1')));
  });

  testWidgets('each orientation keeps its own thickness', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Displays'));
    await tester.pump();

    final outputs = File('${directory.path}/outputs.conf');
    await tester.tap(find.byKey(const ValueKey<String>('side-left')));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), contains('system_bar=left,72'));
    expect(
      tester
          .widget<SettingsSlider>(
            find.byKey(const ValueKey<String>('thickness-slider')),
          )
          .min,
      72,
    );

    await tester.tap(find.byKey(const ValueKey<String>('side-bottom')));
    await tester.pumpAndSettle();
    expect(outputs.readAsStringSync(), contains('system_bar=bottom,32'));
  });

  testWidgets('module gears round-trip typed options', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc, workspaceNames: () async => ['1', '2', 'web']);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    Future<void> openOptions(String module) async {
      final gear = find.byKey(ValueKey<String>('module-options-$module'));
      await tester.ensureVisible(gear);
      await tester.pumpAndSettle();
      await tester.tap(gear);
      await tester.pumpAndSettle();
    }

    await openOptions('clock');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('clock-format-24h')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('clock-format-24h')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.clock.format, ClockFormat.hour24);

    final seconds = find.byKey(const ValueKey<String>('clock-show-seconds'));
    await tester.ensureVisible(seconds);
    await tester.pumpAndSettle();
    await tester.tap(seconds);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.clock.showSeconds, isTrue);

    final weekday = find.byKey(
      const ValueKey<String>('clock-date-style-weekday'),
    );
    await tester.ensureVisible(weekday);
    await tester.pumpAndSettle();
    await tester.tap(weekday);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.clock.dateStyle, ClockDateStyle.weekday);

    await openOptions('media');
    final compactChip = find.byKey(
      const ValueKey<String>('media-mode-compact'),
    );
    await tester.ensureVisible(compactChip);
    await tester.pumpAndSettle();
    await tester.tap(compactChip);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.media.mode, MediaMode.compact);
    final resetMode = find.byKey(const ValueKey<String>('reset-media-mode'));
    await tester.ensureVisible(resetMode);
    await tester.pumpAndSettle();
    await tester.tap(resetMode);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.media.mode, const MediaOptions().mode);

    final barsSlider = find.byKey(const ValueKey<String>('media-bars'));
    await tester.ensureVisible(barsSlider);
    await tester.pumpAndSettle();
    final sliderRect = tester.getRect(barsSlider);
    await tester.tapAt(Offset(sliderRect.right - 2, sliderRect.center.dy));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.media.bars, MediaOptions.maxBars);
    final resetBars = find.byKey(const ValueKey<String>('reset-media-bars'));
    await tester.ensureVisible(resetBars);
    await tester.pumpAndSettle();
    await tester.tap(resetBars);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.media.bars, MediaOptions.defaultBars);

    final stepSlider = find.byKey(const ValueKey<String>('media-volume-step'));
    await tester.ensureVisible(stepSlider);
    await tester.pumpAndSettle();
    final stepRect = tester.getRect(stepSlider);
    await tester.tapAt(Offset(stepRect.right - 2, stepRect.center.dy));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.media.volumeStep, MediaOptions.maxVolumeStep);
    final resetStep = find.byKey(
      const ValueKey<String>('reset-media-volume-step'),
    );
    await tester.ensureVisible(resetStep);
    await tester.pumpAndSettle();
    await tester.tap(resetStep);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.media.volumeStep, MediaOptions.defaultVolumeStep);

    await openOptions('opencode');
    final weekly = find.byKey(const ValueKey<String>('opencode-meter-weekly'));
    await tester.ensureVisible(weekly);
    await tester.pumpAndSettle();
    await tester.tap(weekly);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.opencode.meter, OpencodeMeter.weekly);
    final resetMeter = find.byKey(
      const ValueKey<String>('reset-opencode-meter'),
    );
    await tester.ensureVisible(resetMeter);
    await tester.pumpAndSettle();
    await tester.tap(resetMeter);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.opencode.meter, const OpencodeOptions().meter);

    final showCost = find.byKey(const ValueKey<String>('opencode-show-cost'));
    await tester.ensureVisible(showCost);
    await tester.pumpAndSettle();
    await tester.tap(showCost);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.opencode.showCost, isFalse);
    final resetCost = find.byKey(
      const ValueKey<String>('reset-opencode-show-cost'),
    );
    await tester.ensureVisible(resetCost);
    await tester.pumpAndSettle();
    await tester.tap(resetCost);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.opencode.showCost, isTrue);

    await openOptions('workspaces');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('workspaces-pip-dot')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('workspaces-pip-dot')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.workspaces.pipStyle, PipStyle.dot);

    await tester.tap(
      find.byKey(const ValueKey<String>('workspaces-pip-image')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.workspaces.pipStyle, PipStyle.image);

    // The gear's Browse button asks the host for a path and stores it.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('org.trickster.bar/layer_shell'),
      (call) async => call.method == 'pickImageFile' ? '/tmp/pip.svg' : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('org.trickster.bar/layer_shell'),
        null,
      ),
    );
    final browse = find.byKey(
      const ValueKey<String>('workspaces-image-browse'),
    );
    await tester.ensureVisible(browse);
    await tester.pumpAndSettle();
    await tester.tap(browse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.workspaces.imageSource, '/tmp/pip.svg');

    // An SVG file reveals the recolor option, which writes tint_svg.
    final tint = find.byKey(const ValueKey<String>('workspaces-tint-svg'));
    await tester.ensureVisible(tint);
    await tester.pumpAndSettle();
    await tester.tap(tint);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.workspaces.tintSvg, isTrue);

    // The dropdown offers the bar's live names; picking one fills the name
    // without showing the text field.
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('workspaces-map-pick')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('workspaces-map-pick')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('workspaces-map-pick-2')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('workspaces-map-pick-2')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('workspaces-map-name')),
      findsNothing,
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.workspaces.imageByWorkspace, {'2': '/tmp/pip.svg'});

    final remove = find.byKey(
      const ValueKey<String>('workspaces-map-2-remove'),
    );
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    await tester.tap(remove);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.workspaces.imageByWorkspace, isEmpty);

    // Custom entry still allows typing a name the bar did not report.
    await tester.tap(find.byKey(const ValueKey<String>('workspaces-map-pick')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('workspaces-map-pick-custom')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('workspaces-map-name')),
      'web',
    );
    final customBrowse = find.byKey(
      const ValueKey<String>('workspaces-map-custom-browse'),
    );
    await tester.ensureVisible(customBrowse);
    await tester.pumpAndSettle();
    await tester.tap(customBrowse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.workspaces.imageByWorkspace, {'web': '/tmp/pip.svg'});

    final clear = find.byKey(const ValueKey<String>('workspaces-image-clear'));
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.workspaces.imageSource, isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('clock-show-date')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('clock-show-date')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.clock.showDate, isFalse);

    await openOptions('gpu');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('gpu-meter-caption-device')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('gpu-meter-caption-device')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.gpu.captionSource, MeterCaptionSource.device);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('gpu-meter-sparkline')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('gpu-meter-sparkline')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.gpu.sparkline, isFalse);

    // The custom source reveals the prefix field, which writes the document.
    final customChip = find.byKey(
      const ValueKey<String>('gpu-meter-caption-custom'),
    );
    await tester.ensureVisible(customChip);
    await tester.pumpAndSettle();
    await tester.tap(customChip);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.gpu.captionSource, MeterCaptionSource.custom);
    final prefixField = find.byKey(const ValueKey<String>('gpu-meter-prefix'));
    await tester.ensureVisible(prefixField);
    await tester.pumpAndSettle();
    await tester.enterText(prefixField, 'GPU0');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.gpu.captionPrefix, 'GPU0');

    // A wheel pick lands a threshold tint in the document, and reset drops it.
    final wheel = find.byKey(const ValueKey<String>('gpu-critical-color'));
    await tester.ensureVisible(wheel);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(wheel) + const Offset(30, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(bloc.settings.gpu.criticalColor, isNotNull);
    final colorReset = find.byKey(
      const ValueKey<String>('reset-gpu-critical-color'),
    );
    await tester.ensureVisible(colorReset);
    await tester.pumpAndSettle();
    await tester.tap(colorReset);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(bloc.settings.gpu.criticalColor, isNull);

    // The CPU panel carries the same controls and writes its own options.
    await openOptions('cpu');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('cpu-meter-caption-device')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('cpu-meter-caption-device')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.cpu.captionSource, MeterCaptionSource.device);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('cpu-meter-sparkline')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('cpu-meter-sparkline')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.cpu.sparkline, isFalse);
    // The GPU keeps its own custom source while the CPU switches.
    expect(bloc.settings.gpu.captionSource, MeterCaptionSource.custom);
  });

  testWidgets('rapid changes preview at most once per frame', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    final saver = DebouncedSaver(bloc);
    addTearDown(saver.dispose);

    var states = 0;
    final subscription = bloc.stream.listen((_) => states++);
    addTearDown(subscription.cancel);

    // Three changes before any frame: one preview carries the last one.
    saver.apply((settings) => settings.withAccent(const Color(0xff112233)));
    saver.apply((settings) => settings.withAccent(const Color(0xff445566)));
    saver.apply((settings) => settings.withAccent(const Color(0xff778899)));
    await tester.pump();
    expect(states, 1);
    expect(bloc.settings.accent, const Color(0xff778899));

    // The next frame coalesces a second batch.
    saver.apply((settings) => settings.withAccent(const Color(0xff010203)));
    saver.apply((settings) => settings.withAccent(const Color(0xff040506)));
    await tester.pump();
    expect(states, 2);
    expect(bloc.settings.accent, const Color(0xff040506));

    // This test owns only the coalescing behavior; dedicated tests cover the
    // dispose flush. Drop the pending save so it leaves no timer behind.
    saver.dispose(flush: false);
  });

  testWidgets('appearance page switches the accent source', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    await tester.tap(
      find.byKey(const ValueKey<String>('accent-source-wallpaper')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.accentSource, AccentSource.wallpaper);
    expect(file.readAsStringSync(), contains('"accent_source": "wallpaper"'));

    await tester.tap(
      find.byKey(const ValueKey<String>('accent-source-custom')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.accentSource, AccentSource.custom);
  });

  testWidgets('appearance blur toggle writes and resets', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    expect(bloc.settings.appearance.blur, isTrue);

    final toggle = find.byKey(const ValueKey<String>('appearance-blur'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.appearance.blur, isFalse);
    expect(file.readAsStringSync(), contains('"blur": false'));

    final reset = find.byKey(const ValueKey<String>('reset-appearance-blur'));
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.appearance.blur, isTrue);
  });

  testWidgets('appearance target edits one display and resets', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);

    // Select a display, switch its source, and open the picker.
    await tester.tap(
      find.byKey(const ValueKey<String>('appearance-target-HDMI-A-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('accent-source-wallpaper')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    final decoded = BarSettings.decode(file.readAsStringSync());
    expect(
      decoded.displayAppearance['HDMI-A-1']?.accentSource,
      AccentSource.wallpaper,
    );
    // No sample exists in the test tree, so the waiting note points at grim.
    expect(find.textContaining('grim'), findsOneWidget);
    // The global key and the other display stay untouched.
    expect(decoded.accentSource, AccentSource.custom);
    expect(decoded.accentSourceFor('eDP-1'), AccentSource.custom);

    // Resetting the display drops its overrides.
    await tester.tap(
      find.byKey(const ValueKey<String>('reset-appearance-HDMI-A-1')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(
      BarSettings.decode(file.readAsStringSync()).displayAppearance,
      isEmpty,
    );
  });

  testWidgets('wallpaper source swaps the wheel for the sampled list', (
    tester,
  ) async {
    final settingsFile = File('${directory.path}/wallpaper-settings.json')
      ..writeAsStringSync(
        const BarSettings(
          revision: 2,
          accentSource: AccentSource.wallpaper,
        ).encode(),
      );
    final bloc = await _bloc(settingsFile);
    addTearDown(bloc.close);

    final cache = Directory('${directory.path}/awww')..createSync();
    File('${cache.path}/HDMI-A-1').writeAsStringSync('/tmp/a.png');
    File('${cache.path}/HDMI-A-2').writeAsStringSync('/tmp/b.png');
    final accents = WallpaperAccentBloc(
      cache: WallpaperCache(root: cache),
      sampleCandidates: (path) async => path.endsWith('a.png')
          ? const [Color(0xffe01020), Color(0xff2050e0)]
          : const <Color>[],
      watch: false,
    );
    addTearDown(accents.close);
    accents.add(const WallpaperAccentEnabled(enabled: true));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: BlocProvider.value(
          value: accents,
          child: TricksterLocalizationScope(
            child: MediaQuery(
              data: const MediaQueryData(size: Size(980, 720)),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SettingsHome(
                  onClose: () {},
                  availabilityProbe: () => const <ModuleAvailability>[],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(HsvColorWheel), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('accent-preset-#D0BCFF')),
      findsNothing,
    );
    expect(find.text('Sampled accents'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('wallpaper-accent-#E01020')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('wallpaper-accent-#2050E0')),
      findsOneWidget,
    );

    expect(find.text('#E01020'), findsOneWidget);
    expect(find.text('#2050E0'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('wallpaper-accent-#2050E0')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.accentWallpaperPick, '#2050E0');
    expect(settingsFile.readAsStringSync(), contains('#2050E0'));

    await tester.tap(find.text('#E01020'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('#E01020'), findsOneWidget);
  });

  test('the blur key gates the settings window glass', () {
    expect(settingsGlassEnabled(hostBlur: true, documentBlur: true), isTrue);
    expect(settingsGlassEnabled(hostBlur: true, documentBlur: false), isFalse);
    expect(settingsGlassEnabled(hostBlur: false, documentBlur: true), isFalse);
    expect(settingsGlassEnabled(hostBlur: false, documentBlur: false), isFalse);
  });

  test('settings app state round-trips output geometry', () {
    const state = SettingsAppState(
      availableOutputs: [
        LayerOutput(
          name: 'HDMI-A-1',
          viewId: 7,
          x: 1920,
          y: 0,
          width: 2560,
          height: 1440,
          scale: 2,
        ),
      ],
      usingSocket: true,
      loaded: true,
    );
    final json = jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>;
    final decoded = SettingsAppState.fromJson(json);
    final output = decoded.availableOutputs.single;
    expect(output.name, 'HDMI-A-1');
    expect(output.viewId, 7);
    expect(output.x, 1920);
    expect(output.y, 0);
    expect(output.width, 2560);
    expect(output.height, 1440);
    expect(output.scale, 2);
    expect(decoded.usingSocket, isTrue);
  });

  test('an external document change reloads the settings', () async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    expect(bloc.settings.media.mode, MediaMode.semi);

    // The bar writes a new revision underneath the open window.
    final next = bloc.settings
        .copyWith(media: bloc.settings.media.copyWith(mode: MediaMode.compact))
        .copyWith(revision: bloc.settings.revision + 1);
    final writer = FileSettingsTransport(file);
    await writer.read();
    await writer.write(
      expectedRevision: bloc.settings.revision,
      document: next.encode(),
    );

    bloc.add(const SettingsAppDocumentChanged());
    final reloaded = await bloc.stream.firstWhere(
      (state) => state.settings.media.mode == MediaMode.compact,
    );
    expect(reloaded.settings.revision, next.revision);
  });

  testWidgets('language page writes the locale', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await tester.tap(find.bySemanticsLabel('Language'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('language-zh')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(bloc.settings.locale, 'zh');
    expect(file.readAsStringSync(), contains('"locale": "zh"'));

    await tester.tap(find.byKey(const ValueKey<String>('language-system')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(bloc.settings.locale, isNull);
  });

  testWidgets('about page shows versions and degrades without a bar', (
    tester,
  ) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);

    Future<void> pumpAbout(Future<Map<String, Object?>> Function() loader) {
      return tester.pumpWidget(
        BlocProvider.value(
          value: bloc,
          child: TricksterLocalizationScope(
            child: MediaQuery(
              data: const MediaQueryData(size: Size(980, 720)),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: AboutPage(versionLoader: loader),
              ),
            ),
          ),
        ),
      );
    }

    await pumpAbout(
      () async => const <String, Object?>{
        'ok': true,
        'version': Cli.appVersion,
        'protocol': 1,
      },
    );
    await tester.pumpAndSettle();
    expect(find.text(Cli.appVersion), findsNWidgets(2));
    expect(find.text('1'), findsOneWidget);

    await pumpAbout(() async => const <String, Object?>{'ok': false});
    await tester.pumpAndSettle();
    expect(find.text('Not running'), findsOneWidget);
  });

  testWidgets('the close control announces and fires', (tester) async {
    final bloc = await _bloc(file);
    addTearDown(bloc.close);
    var closed = 0;
    await _pump(tester, bloc, onClose: () => closed++);

    expect(find.bySemanticsLabel('Close settings'), findsOneWidget);
    await tester.tap(find.byType(SettingsCloseButton));
    await tester.pump();
    expect(closed, 1);
  });
}
