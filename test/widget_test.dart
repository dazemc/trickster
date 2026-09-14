import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trickster/src/bar/bar.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/cpu.dart';
import 'package:trickster/src/bar/gpu.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/bar/workspaces.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/wallpaper.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

import 'support/strip_harness.dart';

Future<void> _pumpClock(
  WidgetTester tester,
  Locale locale, {
  ClockFormat format = ClockFormat.locale,
  bool vertical = false,
}) {
  return tester.pumpWidget(
    MultiBlocProvider(
      providers: [BlocProvider(create: (_) => ClockBloc())],
      child: TricksterLocalizationScope(
        locale: locale,
        child: Center(
          child: ClockPill(
            accent: const WallpaperAccent(Color(0xffd0bcff)),
            format: format,
            vertical: vertical,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_US');
    await initializeDateFormatting('de_DE');
    await initializeDateFormatting('zh');
  });
  testWidgets('strip shows clock, cpu, battery, and workspaces', (
    tester,
  ) async {
    await pumpBarHarness(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('42%', findRichText: true), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('workspace-pip-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('workspace-pip-2')),
      findsOneWidget,
    );
  });

  testWidgets('disabled modules render nothing', (tester) async {
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock']),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('CPU'), findsNothing);
    expect(find.text('42%', findRichText: true), findsNothing);
    expect(find.text('87%'), findsNothing);
    expect(find.byKey(const ValueKey<String>('workspace-pip-1')), findsNothing);
  });

  testWidgets('gpu cards follow the service list', (tester) async {
    tester.view.physicalSize = const Size(1600, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpBarHarness(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GpuPill), findsNothing);

    final gpu = tester.element(find.byType(TricksterBarStrip)).read<GpuBloc>();
    gpu.add(
      const GpuSampled([
        GpuLoad(id: 'card0', label: 'AMD0', usage: 0.4, history: [0.2, 0.4]),
        GpuLoad(id: 'card1', label: 'AMD1', usage: 0.8, history: [0.8]),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GpuPill), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey<String>('system-bar-gpu-card0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('system-bar-gpu-card1')),
      findsOneWidget,
    );
    expect(find.text('AMD0'), findsOneWidget);
    expect(find.text('AMD1'), findsOneWidget);

    gpu.add(const GpuSampled([]));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GpuPill), findsNothing);
  });

  testWidgets('strip tints captions with the settings accent', (tester) async {
    const accent = Color(0xffff0000);
    await pumpBarHarness(tester, settings: const BarSettings(accent: accent));
    await tester.pump(const Duration(milliseconds: 500));
    final expected = const WallpaperAccent(accent).captionColor();
    final caption = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.style?.fontSize == ShellText.systemBarCaption.fontSize,
      ),
    );
    expect(caption.style?.color, expected);
  });

  testWidgets('vertical clock drops the date', (tester) async {
    await _pumpClock(tester, const Locale('en', 'US'), vertical: true);
    await tester.pump(const Duration(milliseconds: 500));
    final texts = tester.widgetList<RichText>(find.byType(RichText)).length;
    expect(texts, 1);
  });

  testWidgets('vertical strips stack upright pills', (tester) async {
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'cpu']),
      side: SystemBarSide.left,
      thickness: 72,
      settle: const Duration(milliseconds: 500),
    );
    expect(find.byType(RotatedBox), findsNothing);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
  });

  testWidgets('wallpaper accent source colors the strip', (tester) async {
    final directory = Directory.systemTemp.createTempSync('trickster-wall');
    addTearDown(() => directory.delete(recursive: true));
    final cacheFile = File('${directory.path}/awww/OUTPUT');
    cacheFile.parent.createSync(recursive: true);
    cacheFile.writeAsStringSync('/tmp/wall.png');

    final controller = WallpaperAccentController(
      cache: WallpaperCache(root: cacheFile.parent),
      sampleCandidates: (_) async => const [
        Color(0xffe01020),
        Color(0xff2050e0),
      ],
      watch: false,
    );
    addTearDown(controller.dispose);

    await pumpBarHarness(
      tester,
      settings: const BarSettings(
        modules: ['workspaces'],
        accentSource: AccentSource.wallpaper,
      ),
      wallpaperAccent: controller,
      settle: const Duration(milliseconds: 500),
    );
    controller.update(enabled: true);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(controller.color, const Color(0xffe01020));

    Color? pipColor() {
      final pip = tester.widget<AnimatedDefaultTextStyle>(
        find
            .descendant(
              of: find.byKey(const ValueKey<String>('workspace-pip-1')),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .last,
      );
      return pip.style.color;
    }

    // No pick: the dominant (first) candidate is the accent.
    expect(pipColor(), const Color(0xffe01020));

    // A stored pick chooses the candidate closest to it in hue.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpBarHarness(
      tester,
      settings: const BarSettings(
        modules: ['workspaces'],
        accentSource: AccentSource.wallpaper,
        accentWallpaperPick: '#2050E0',
      ),
      wallpaperAccent: controller,
      settle: const Duration(milliseconds: 500),
    );
    expect(pipColor(), const Color(0xff2050e0));
  });

  testWidgets('count rail maps active and occupied per output', (tester) async {
    const accent = Color(0xffd0bcff);
    final handle = tester.ensureSemantics();
    await pumpBarHarness(
      tester,
      settings: const BarSettings(
        accent: accent,
        modules: ['workspaces'],
        workspaces: WorkspaceOptions(count: 3),
      ),
      output: 'HDMI-A-1',
      workspacesBuilder: () => WorkspacesBloc(
        initial: const WorkspacesState([
          Workspace(
            id: '1',
            name: '1',
            output: 'HDMI-A-2',
            focused: true,
            occupied: true,
          ),
          Workspace(id: '2', name: '2', output: 'HDMI-A-1', focused: true),
          Workspace(id: '3', name: '3', output: 'HDMI-A-1', occupied: true),
        ]),
      ),
      settle: const Duration(milliseconds: 500),
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(
      _pipStyle(tester, '1').color,
      ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.3),
    );
    expect(_pipStyle(tester, '2').color, accent);
    expect(_pipStyle(tester, '3').color, ShellMediaColors.lightForeground);
    final lens = tester.widget<AnimatedAlign>(
      find.byKey(WorkspacesPill.lensKey),
    );
    expect(lens.alignment, Alignment.center);
    expect(find.bySemanticsLabel('Workspace 1, empty'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('workspace rail centers independently of the cluster', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['workspaces', 'clock']),
      settle: const Duration(milliseconds: 500),
    );
    final rail = find.byType(WorkspacesPill);
    expect(rail, findsOneWidget);
    expect(
      find.ancestor(of: rail, matching: find.byType(SystemBarIndicatorSlot)),
      findsOneWidget,
    );
    final stripCenter = tester.getCenter(find.byType(TricksterBarStrip)).dx;
    expect(tester.getCenter(rail).dx, closeTo(stripCenter, 0.5));
    expect(
      tester.getCenter(rail).dx,
      lessThan(tester.getCenter(find.byType(ClockPill)).dx),
    );
  });

  testWidgets('tray pins to the leading edge', (tester) async {
    tester.view.physicalSize = const Size(1200, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'tray']),
      trayBuilder: () => TrayBloc(
        initial: const TrayState([
          SystemTrayItem(
            id: 'app',
            title: 'App',
            status: SystemTrayStatus.active,
            iconName: 'icon',
            iconThemePath: '',
            iconPixmap: null,
            menuAvailable: false,
            primaryOpensMenu: false,
          ),
        ]),
      ),
    );
    // The entrance timer fires, then the ticker starts on the following
    // frame; two pumps settle it to its resting offset.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 300));
    final tray = find.byType(TrayPill);
    expect(tray, findsOneWidget);
    final stripLeft = tester.getTopLeft(find.byType(TricksterBarStrip)).dx;
    expect(tester.getTopLeft(tray).dx, lessThan(stripLeft + 20));
    expect(
      tester.getCenter(tray).dx,
      lessThan(tester.getCenter(find.byType(ClockPill)).dx),
    );
  });

  testWidgets('strip renders modules in configured order', (tester) async {
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['clock', 'cpu']),
      settle: const Duration(milliseconds: 500),
    );
    expect(
      tester.getCenter(find.byType(ClockPill)).dx,
      lessThan(tester.getCenter(find.byType(CpuPill)).dx),
    );

    // Tear the first provider tree down so the second seeds a fresh
    // SettingsBloc; BlocProvider keeps blocs across same-shape rebuilds.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpBarHarness(
      tester,
      settings: const BarSettings(modules: ['cpu', 'clock']),
      settle: const Duration(milliseconds: 500),
    );
    expect(
      tester.getCenter(find.byType(CpuPill)).dx,
      lessThan(tester.getCenter(find.byType(ClockPill)).dx),
    );
  });

  testWidgets('clock follows the US 12-hour cycle', (tester) async {
    await _pumpClock(tester, const Locale('en', 'US'));
    await tester.pump(const Duration(milliseconds: 500));
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(texts, anyOf(contains('AM'), contains('PM')));
  });

  testWidgets('clock options force 24h and 12h', (tester) async {
    await _pumpClock(
      tester,
      const Locale('en', 'US'),
      format: ClockFormat.hour24,
    );
    await tester.pump(const Duration(milliseconds: 500));
    var texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(texts, isNot(contains('AM')));
    expect(texts, isNot(contains('PM')));

    await _pumpClock(
      tester,
      const Locale('en', 'US'),
      format: ClockFormat.hour12,
    );
    await tester.pump(const Duration(milliseconds: 500));
    texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(texts, anyOf(contains('AM'), contains('PM')));
  });

  testWidgets('action card announces, taps, and rings on focus', (
    tester,
  ) async {
    var pressed = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      TricksterLocalizationScope(
        locale: const Locale('en', 'US'),
        child: Center(
          child: TricksterActionCard(
            accent: const WallpaperAccent(Color(0xffd0bcff)),
            label: 'Test action',
            onPressed: () => pressed++,
            focusNode: node,
            child: const Text('go'),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Test action'), findsOneWidget);
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(pressed, 1);
    node.requestFocus();
    // Focus notification is delivered asynchronously behind the full
    // ancestor chain; the first pump applies focus, the second rebuilds.
    await tester.pump();
    await tester.pump();
    final ringed = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).border != null,
    );
    expect(ringed, findsOneWidget);
  });

  test('bar date caption follows the locale', () {
    final fixed = DateTime(2026, 9, 12);
    expect(formatBarDate(fixed, 'en_US'), 'Sep 12');
    expect(formatBarDate(fixed, 'de_DE'), contains('Sept'));
  });

  testWidgets('clock follows the Chinese 24-hour cycle', (tester) async {
    await _pumpClock(tester, const Locale('zh'));
    await tester.pump(const Duration(milliseconds: 500));
    final texts = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join(' ');
    expect(texts, isNot(anyOf(contains('AM'), contains('PM'))));
    expect(texts, matches(RegExp(r'\b\d{1,2}:\d{2}\b')));
  });
}

TextStyle _pipStyle(WidgetTester tester, String id) {
  final pip = tester.widget<AnimatedDefaultTextStyle>(
    find
        .descendant(
          of: find.byKey(ValueKey<String>('workspace-pip-$id')),
          matching: find.byType(AnimatedDefaultTextStyle),
        )
        .last,
  );
  return pip.style;
}
