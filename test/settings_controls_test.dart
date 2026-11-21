import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/theme/tokens.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget control, {
  Size size = const Size(900, 600),
  double textScale = 2,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    TricksterLocalizationScope(
      locale: const Locale('en'),
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: control),
        ),
      ),
    ),
  );
}

/// The focus highlight follows the last input modality; these tests assert
/// the keyboard ring directly.
void _useKeyboardHighlight() {
  final previous = FocusManager.instance.highlightStrategy;
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = previous);
}

FocusNode _focusNodeOf(WidgetTester tester, Finder control) {
  return tester
      .widget<FocusableActionDetector>(
        find.descendant(
          of: control,
          matching: find.byType(FocusableActionDetector),
        ),
      )
      .focusNode!;
}

void main() {
  testWidgets('a text button activates with Enter and Space and rings', (
    tester,
  ) async {
    _useKeyboardHighlight();
    var presses = 0;
    await _pump(
      tester,
      SettingsButton(label: 'Browse', onPressed: () => presses++),
    );
    await tester.pump();

    _focusNodeOf(tester, find.byType(SettingsButton)).requestFocus();
    await tester.pump();
    await tester.pump();
    final box = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(SettingsButton),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (box.decoration! as BoxDecoration).border!.top.color,
      ShellBrandColors.defaultAccent,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(presses, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slider steps with every arrow key and rings on focus', (
    tester,
  ) async {
    _useKeyboardHighlight();
    var value = 5.0;
    late StateSetter setValue;
    await _pump(
      tester,
      SizedBox(
        width: 320,
        child: StatefulBuilder(
          builder: (context, setState) {
            setValue = setState;
            return SettingsSlider(
              value: value,
              min: 0,
              max: 10,
              label: 'Warn',
              semanticsStep: 1,
              onChanged: (next) => setValue(() => value = next),
              onChangeEnd: (next) => setValue(() => value = next),
            );
          },
        ),
      ),
    );
    await tester.pump();

    _focusNodeOf(tester, find.byType(SettingsSlider)).requestFocus();
    await tester.pump();
    final rings = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(SettingsSlider),
            matching: find.byType(DecoratedBox),
          ),
        )
        .where((box) {
          final decoration = box.decoration;
          return decoration is BoxDecoration && decoration.border != null;
        });
    expect(rings, isNotEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(value, 7);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(value, 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(value, 5);

    // The ends clamp instead of overshooting.
    setValue(() => value = 10);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected chips and enabled toggles keep a contrasting ring', (
    tester,
  ) async {
    _useKeyboardHighlight();
    var toggled = 0;
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsChoiceChip(
            label: 'Selected',
            selected: true,
            onPressed: () {},
          ),
          SettingsToggle(
            label: 'Enabled',
            enabled: true,
            onChanged: (_) => toggled++,
          ),
        ],
      ),
    );
    await tester.pump();

    final chip = find.byType(SettingsChoiceChip);
    _focusNodeOf(tester, chip).requestFocus();
    await tester.pump();
    await tester.pump();
    final chipBox = tester.widget<AnimatedContainer>(
      find.descendant(of: chip, matching: find.byType(AnimatedContainer)),
    );
    final chipDecoration = chipBox.decoration! as BoxDecoration;
    expect(chipDecoration.color, ShellBrandColors.defaultAccent);
    expect(chipDecoration.border!.top.color, isNot(chipDecoration.color));
    expect(chipDecoration.border!.top.color, ShellMediaColors.lightForeground);

    final toggle = find.byType(SettingsToggle);
    _focusNodeOf(tester, toggle).requestFocus();
    await tester.pump();
    await tester.pump();
    final toggleBox = tester.widget<AnimatedContainer>(
      find.descendant(of: toggle, matching: find.byType(AnimatedContainer)),
    );
    final toggleDecoration = toggleBox.decoration! as BoxDecoration;
    expect(toggleDecoration.color, ShellBrandColors.defaultAccent);
    expect(toggleDecoration.border!.top.color, isNot(toggleDecoration.color));
    expect(
      toggleDecoration.border!.top.color,
      ShellMediaColors.lightForeground,
    );

    // The keyboard path still toggles the switch.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(toggled, 1);
    expect(tester.takeException(), isNull);
  });
}
