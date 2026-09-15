import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:trickster/src/settings/pages/about.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell() : super(channel: const MethodChannel('test/trickster'));

  @override
  Future<List<LayerOutput>> outputs() async => const <LayerOutput>[
    LayerOutput(name: 'eDP-1', width: 1920, height: 1080),
    LayerOutput(name: 'HDMI-A-1', width: 2560, height: 1440),
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
  Future<List<String>> Function()? workspaceNames,
}) {
  return tester.pumpWidget(
    BlocProvider.value(
      value: bloc,
      child: BlocProvider<WallpaperAccentBloc>(
        create: (_) => WallpaperAccentBloc(watch: false),
        child: TricksterLocalizationScope(
          child: MediaQuery(
            data: const MediaQueryData(size: Size(980, 720)),
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
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.ensureVisible(handle);
  await tester.pumpAndSettle();
  final start = tester.getCenter(handle);
  final end = tester.getCenter(target);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 120));
  // Cross the drag slop first so the recognizer claims the pointer. The
  // source row then collapses, which moves the target; re-read it before
  // steering there.
  final slop = Offset(0, end.dy >= start.dy ? 24 : -24);
  await gesture.moveBy(slop);
  await tester.pump(const Duration(milliseconds: 60));
  final liveEnd = tester.getCenter(target);
  var current = start + slop;
  const steps = 8;
  for (var step = 1; step <= steps; step++) {
    current = Offset.lerp(start + slop, liveEnd, step / steps)!;
    await gesture.moveTo(current);
    await tester.pump(const Duration(milliseconds: 40));
  }
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
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.ensureVisible(handle);
  await tester.pumpAndSettle();
  final start = tester.getCenter(handle);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 120));
  const slop = Offset(0, 24);
  await gesture.moveBy(slop);
  await tester.pump(const Duration(milliseconds: 60));
  final rect = tester.getRect(target);
  final end = Offset(rect.center.dx, rect.bottom + 12);
  var current = start + slop;
  const steps = 8;
  for (var step = 1; step <= steps; step++) {
    current = Offset.lerp(start + slop, end, step / steps)!;
    await gesture.moveTo(current);
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
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

  testWidgets('every module option resets to its default', (tester) async {
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

    // Trailing holds media, cpu, gpu, battery, clock; media goes last.
    await _dragModuleBelow(
      tester,
      'media',
      find.byKey(const ValueKey<String>('module-clock')),
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
    expect(bloc.settings.gpu.captionSource, MeterCaptionSource.device);
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
                child: SettingsHome(onClose: () {}),
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
