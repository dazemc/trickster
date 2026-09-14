import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
import 'package:trickster/src/settings/color_format.dart';
import 'package:trickster/src/settings/color_wheel.dart';
import 'package:trickster/src/settings/controller.dart';
import 'package:trickster/src/settings/pages/about.dart';
import 'package:trickster/src/settings/scope.dart';
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

Future<SettingsAppController> _controller(File file) async {
  final directory = file.parent;
  final controller = SettingsAppController(
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
  await controller.load();
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  SettingsAppController controller, {
  VoidCallback? onClose,
  List<ModuleAvailability> Function()? availabilityProbe,
}) {
  return tester.pumpWidget(
    SettingsAppScope(
      notifier: controller,
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
                        availabilityProbe ?? () => const <ModuleAvailability>[],
                  ),
                ),
              ],
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(
      find.byKey(const ValueKey<String>('accent-preset-#8AB4FF')),
    );
    await tester.pump();
    expect(controller.settings.accent, const Color(0xff8ab4ff));
    expect(file.readAsStringSync(), isNot(contains('8ab4ff')));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(file.readAsStringSync(), contains('8ab4ff'));
    expect(controller.error, isNull);
  });

  testWidgets('reset clears the accent', (tester) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await controller.save(
      const BarSettings(revision: 2, accent: Color(0xff8ab4ff)),
    );
    await _pump(tester, controller);
    expect(file.readAsStringSync(), contains('8ab4ff'));

    await tester.tap(find.byKey(const ValueKey<String>('reset-accent')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(controller.settings.accent, isNull);
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

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
    expect(controller.settings.modules, isNot(contains('gpu')));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(file.readAsStringSync(), isNot(contains('"gpu"')));

    final before = List<String>.of(controller.settings.modules);
    await _dragModuleTo(
      tester,
      'clock',
      find.byKey(const ValueKey<String>('module-battery')),
    );
    expect(
      controller.settings.modules.indexOf('clock'),
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
    expect(controller.settings.zoneFor('clock'), ModuleZone.leading);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(file.readAsStringSync(), contains('"module_placement"'));
    expect(
      BarSettings.decode(file.readAsStringSync()).zoneFor('clock'),
      ModuleZone.leading,
    );
  });

  testWidgets('every module option resets to its default', (tester) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    expect(controller.settings.clock.format, ClockFormat.hour24);
    await reset('reset-clock-format');
    expect(controller.settings.clock.format, const ClockOptions().format);

    await openOptions('cpu');
    await nudgeToMax('options-cpu-warn');
    await reset('reset-cpu-warn');
    expect(controller.settings.cpu.warn, const CpuOptions().warn);
    await reset('reset-cpu-critical');
    expect(controller.settings.cpu.critical, const CpuOptions().critical);

    await openOptions('battery');
    await nudgeToMax('options-battery-warn');
    await reset('reset-battery-warn');
    expect(controller.settings.battery.warn, const BatteryOptions().warn);
    await reset('reset-battery-critical');
    expect(
      controller.settings.battery.critical,
      const BatteryOptions().critical,
    );

    await openOptions('gpu');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('meter-caption-device')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('meter-caption-device')),
    );
    await tester.pump();
    await settle();
    expect(controller.settings.meter.captionSource, MeterCaptionSource.device);
    await reset('reset-meter-caption');
    expect(
      controller.settings.meter.captionSource,
      const MeterOptions().captionSource,
    );

    final decoded = BarSettings.decode(file.readAsStringSync());
    expect(decoded.clock.format, const ClockOptions().format);
    expect(decoded.cpu.warn, const CpuOptions().warn);
    expect(decoded.cpu.critical, const CpuOptions().critical);
    expect(decoded.battery.warn, const BatteryOptions().warn);
    expect(decoded.battery.critical, const BatteryOptions().critical);
    expect(decoded.meter.captionSource, const MeterOptions().captionSource);

    await tester.tap(find.bySemanticsLabel('Language'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('language-zh')));
    await tester.pump();
    await settle();
    expect(controller.settings.locale, 'zh');
    await reset('reset-locale');
    expect(controller.settings.locale, isNull);
    expect(BarSettings.decode(file.readAsStringSync()).locale, isNull);
  });

  testWidgets('displays page writes placement and output selection', (
    tester,
  ) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    final before = List<String>.of(controller.settings.modules);
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
      controller.settings.modules.indexOf('clock'),
      lessThan(before.indexOf('clock')),
    );
  });

  testWidgets('dragging previews the landing slot before release', (
    tester,
  ) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    final before = List<String>.of(controller.settings.modules);
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
      controller.settings.modules.indexOf('clock'),
      lessThan(before.indexOf('clock')),
    );
  });

  testWidgets('absent hardware lands in the unavailable segment', (
    tester,
  ) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();

    // The empty leading zone carries the hint; populated zones do not.
    expect(find.text('Drop a module here'), findsWidgets);

    await _dragModuleBelow(
      tester,
      'workspaces',
      find.byKey(const ValueKey<String>('module-battery')),
    );
    expect(controller.settings.zoneFor('workspaces'), ModuleZone.trailing);
    expect(controller.settings.modules.last, 'workspaces');
  });

  testWidgets('the disabled section stays visible and accepts a drop', (
    tester,
  ) async {
    file.writeAsStringSync(
      '{"revision": 1, "modules": ["workspaces", "cpu", "battery"]}',
    );
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    expect(controller.settings.modules, isNot(contains('battery')));
    expect(
      find.byKey(const ValueKey<String>('module-battery')),
      findsOneWidget,
    );
  });

  testWidgets('a disabled module drags out to a zone', (tester) async {
    file.writeAsStringSync(
      '{"revision": 1, "modules": ["workspaces", "cpu", "battery"]}',
    );
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.tap(find.bySemanticsLabel('Modules'));
    await tester.pump();
    expect(controller.settings.modules, isNot(contains('gpu')));

    // Drag the disabled GPU row to the empty leading zone.
    await _dragModuleTo(
      tester,
      'gpu',
      find.byKey(const ValueKey<String>('module-zone-leading')),
    );
    expect(controller.settings.modules, contains('gpu'));
    expect(controller.settings.zoneFor('gpu'), ModuleZone.leading);
  });

  testWidgets('appearance resets restore the accent defaults', (tester) async {
    file.writeAsStringSync(
      '{"revision": 1, "accent_source": "wallpaper", '
      '"accent_wallpaper_pick": "#2050E0"}',
    );
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

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

    expect(controller.settings.accentWallpaperPick, '#2050E0');
    await reset('reset-wallpaper-pick');
    expect(controller.settings.accentWallpaperPick, isNull);

    await reset('reset-accent-source');
    expect(controller.settings.accentSource, AccentSource.custom);

    final preset = ValueKey<String>(
      'accent-preset-${formatOpaqueColorHex(const Color(0xff8ab4ff))}',
    );
    await tester.ensureVisible(find.byKey(preset));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(preset));
    await settle();
    expect(controller.settings.accent, const Color(0xff8ab4ff));
    await reset('reset-accent');
    expect(controller.settings.accent, isNull);

    final decoded = BarSettings.decode(file.readAsStringSync());
    expect(decoded.accent, isNull);
    expect(decoded.accentSource, AccentSource.custom);
    expect(decoded.accentWallpaperPick, isNull);
  });

  testWidgets('module resets restore order and placement', (tester) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    expect(controller.settings.modules, isNot(BarSettings.knownModules));
    expect(controller.settings.zoneFor('tray'), ModuleZone.center);

    await reset('reset-modules');
    expect(controller.settings.modules, BarSettings.knownModules);
    expect(controller.settings.zoneFor('tray'), ModuleZone.leading);

    final decoded = BarSettings.decode(file.readAsStringSync());
    expect(decoded.modules, BarSettings.knownModules);
    expect(decoded.modulePlacement, isEmpty);
  });

  testWidgets('display resets restore edge, thickness, and outputs', (
    tester,
  ) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
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
    expect(controller.settings.clock.format, ClockFormat.hour24);

    await openOptions('gpu');
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('meter-caption-device')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('meter-caption-device')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(controller.settings.meter.captionSource, MeterCaptionSource.device);
  });

  testWidgets('appearance page switches the accent source', (tester) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(
      find.byKey(const ValueKey<String>('accent-source-wallpaper')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(controller.settings.accentSource, AccentSource.wallpaper);
    expect(file.readAsStringSync(), contains('"accent_source": "wallpaper"'));

    await tester.tap(
      find.byKey(const ValueKey<String>('accent-source-custom')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(controller.settings.accentSource, AccentSource.custom);
  });

  testWidgets('appearance target edits one display and resets', (tester) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

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
    final controller = await _controller(settingsFile);
    addTearDown(controller.dispose);

    final cache = Directory('${directory.path}/awww')..createSync();
    File('${cache.path}/HDMI-A-1').writeAsStringSync('/tmp/a.png');
    File('${cache.path}/HDMI-A-2').writeAsStringSync('/tmp/b.png');
    final accents = WallpaperAccentController(
      cache: WallpaperCache(root: cache),
      sampleCandidates: (path) async => path.endsWith('a.png')
          ? const [Color(0xffe01020), Color(0xff2050e0)]
          : const <Color>[],
      watch: false,
    );
    addTearDown(accents.dispose);
    accents.update(enabled: true);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    await tester.pumpWidget(
      SettingsAppScope(
        notifier: controller,
        child: WallpaperAccentScope(
          notifier: accents,
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
    expect(controller.settings.accentWallpaperPick, '#2050E0');
    expect(settingsFile.readAsStringSync(), contains('#2050E0'));

    await tester.tap(find.text('#E01020'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('#E01020'), findsOneWidget);
  });

  testWidgets('language page writes the locale', (tester) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.tap(find.bySemanticsLabel('Language'));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('language-zh')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(controller.settings.locale, 'zh');
    expect(file.readAsStringSync(), contains('"locale": "zh"'));

    await tester.tap(find.byKey(const ValueKey<String>('language-system')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(controller.settings.locale, isNull);
  });

  testWidgets('about page shows versions and degrades without a bar', (
    tester,
  ) async {
    final controller = await _controller(file);
    addTearDown(controller.dispose);

    Future<void> pumpAbout(Future<Map<String, Object?>> Function() loader) {
      return tester.pumpWidget(
        SettingsAppScope(
          notifier: controller,
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
    final controller = await _controller(file);
    addTearDown(controller.dispose);
    var closed = 0;
    await _pump(tester, controller, onClose: () => closed++);

    expect(find.bySemanticsLabel('Close settings'), findsOneWidget);
    await tester.tap(find.byType(SettingsCloseButton));
    await tester.pump();
    expect(closed, 1);
  });
}
