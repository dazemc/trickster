import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/app.dart';
import 'package:trickster/src/settings/color_wheel.dart';
import 'package:trickster/src/settings/controller.dart';
import 'package:trickster/src/settings/scope.dart';
import 'package:trickster/src/settings/settings_theme.dart';

Future<SettingsAppController> _controller(File file) async {
  final controller = SettingsAppController(
    socket: SocketSettingsTransport(
      socketPath: '${file.parent.path}/no-bar.sock',
    ),
    file: FileSettingsTransport(file),
  );
  await controller.load();
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  SettingsAppController controller, {
  VoidCallback? onClose,
}) {
  return tester.pumpWidget(
    SettingsAppScope(
      notifier: controller,
      child: TricksterLocalizationScope(
        child: MediaQuery(
          data: const MediaQueryData(size: Size(980, 720)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SettingsHome(onClose: onClose),
          ),
        ),
      ),
    ),
  );
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
    expect(find.text('Appearance'), findsOneWidget);
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

    await tester.tap(find.bySemanticsLabel('Reset'));
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
