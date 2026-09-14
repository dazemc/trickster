import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/settings/availability.dart';
import 'package:trickster/src/settings/modules_bloc.dart';

void main() {
  test('groups keep strip order, placement, and available modules', () {
    const settings = BarSettings(
      modules: ['clock', 'cpu', 'gpu', 'tray'],
      modulePlacement: {
        'clock': ModuleZone.center,
        'cpu': ModuleZone.center,
        'gpu': ModuleZone.leading,
        'tray': ModuleZone.trailing,
      },
    );
    final groups = moduleGroups(settings, const [
      ModuleAvailability(
        module: 'cpu',
        reason: ModuleUnavailableReason.noBattery,
      ),
    ]);
    expect(groups[ModuleZone.leading], ['gpu']);
    expect(groups[ModuleZone.center], ['clock']);
    expect(groups[ModuleZone.trailing], ['tray']);
    expect(groups[ModuleZone.center], isNot(contains('cpu')));
  });

  test('groups exclude the row in flight', () {
    const settings = BarSettings(
      modules: ['clock', 'tray'],
      modulePlacement: {
        'clock': ModuleZone.trailing,
        'tray': ModuleZone.trailing,
      },
    );
    expect(
      moduleGroups(settings, const [], exclude: 'tray')[ModuleZone.trailing],
      ['clock'],
    );
  });

  test('modules state round-trips its json', () {
    const state = ModulesState(
      unavailable: [
        ModuleAvailability(
          module: 'battery',
          reason: ModuleUnavailableReason.noBattery,
        ),
      ],
      expanded: {'clock'},
      dragging: 'tray',
      previewZone: ModuleZone.trailing,
      previewIndex: 2,
      lastPointer: Offset(12, 34),
      dropHandled: true,
    );
    expect(ModulesState.fromJson(state.toJson()), state);
  });

  test('modules state json degrades on junk', () {
    final decoded = ModulesState.fromJson(const <String, dynamic>{
      'expanded': ['clock', 7],
      'preview_zone': 'nowhere',
      'last_pointer': 'not-an-offset',
    });
    expect(decoded.expanded, {'clock', '7'});
    expect(decoded.previewZone, isNull);
    expect(decoded.lastPointer, isNull);
  });
}
