import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/tray.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/theme/accent.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

SystemTrayItem _item(
  String id, {
  String title = 'Item',
  SystemTrayStatus status = SystemTrayStatus.active,
}) {
  return SystemTrayItem(
    id: id,
    title: title,
    status: status,
    iconName: 'icon',
    iconThemePath: '',
    iconPixmap: null,
    menuAvailable: false,
    primaryOpensMenu: false,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<SystemTrayItem> items,
  void Function(SystemTrayItem item, Offset position) onActivate,
) {
  return tester.pumpWidget(
    TricksterLocalizationScope(
      child: Center(
        child: TrayPill(accent: _accent, items: items, onActivate: onActivate),
      ),
    ),
  );
}

void main() {
  testWidgets('renders one button per item and activates the tapped one', (
    tester,
  ) async {
    final pressed = <(SystemTrayItem, Offset)>[];
    await _pump(tester, [
      _item('a', title: 'Alpha'),
      _item('b', title: 'Beta'),
    ], (item, position) => pressed.add((item, position)));

    expect(find.byKey(const ValueKey<String>('tray-item-a')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('tray-item-b')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('tray-item-b')));
    await tester.pump();
    expect(pressed.single.$1.id, 'b');
    expect(pressed.single.$2, isA<Offset>());
  });

  testWidgets('semantics announce the title and status', (tester) async {
    await _pump(tester, [
      _item('a', title: 'Alpha'),
      _item('b', title: 'Beta', status: SystemTrayStatus.needsAttention),
    ], (item, position) {});

    expect(find.bySemanticsLabel('Alpha'), findsOneWidget);
    expect(find.bySemanticsLabel('Beta'), findsOneWidget);
    final semantics = tester.getSemantics(find.bySemanticsLabel('Beta'));
    expect(semantics.value, 'Needs attention');
  });

  testWidgets('untitled passive items fall back to a tray label', (
    tester,
  ) async {
    await _pump(tester, [
      _item('c', title: '', status: SystemTrayStatus.passive),
    ], (item, position) {});

    expect(find.bySemanticsLabel('icon'), findsOneWidget);
    final semantics = tester.getSemantics(find.bySemanticsLabel('icon'));
    expect(semantics.value, 'Passive');
  });
}
