import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/settings/availability.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/modules_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('groups ignore unknown names and duplicate configured entries', () {
    const settings = BarSettings(modules: ['clock', 'weather', 'clock', 'cpu']);
    final groups = moduleGroups(settings, const []);
    expect(groups[ModuleZone.trailing], ['clock', 'cpu']);
    expect([
      for (final entry in groups.values) ...entry,
    ], isNot(contains('weather')));
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

  test('pruneOptions closes only enabled unavailable modules', () {
    const settings = BarSettings(modules: ['clock', 'network']);
    const unavailable = [
      ModuleAvailability(
        module: 'ram',
        reason: ModuleUnavailableReason.noBattery,
      ),
      ModuleAvailability(
        module: 'network',
        reason: ModuleUnavailableReason.noNetwork,
      ),
    ];
    expect(pruneOptions('clock', settings, unavailable), 'clock');
    expect(pruneOptions('ram', settings, unavailable), 'ram');
    expect(pruneOptions('network', settings, unavailable), isNull);

    const disabled = BarSettings(modules: ['clock']);
    expect(pruneOptions('network', disabled, unavailable), 'network');
    expect(pruneOptions('unknown', settings, unavailable), isNull);
    expect(pruneOptions(null, settings, unavailable), isNull);
  });

  test('options selection is exclusive and toggles closed', () async {
    final settings = SettingsAppBloc();
    addTearDown(settings.close);
    final modules = ModulesBloc(
      settings: settings,
      availabilityProbe: () => const <ModuleAvailability>[],
    );
    addTearDown(modules.close);

    modules.add(const ModulesOptionsToggled('clock'));
    await modules.stream.firstWhere((state) => state.optionsModule == 'clock');
    modules.add(const ModulesOptionsToggled('ram'));
    final replaced = await modules.stream.firstWhere(
      (state) => state.optionsModule == 'ram',
    );
    expect(replaced.optionsModule, 'ram');

    modules.add(const ModulesOptionsToggled('ram'));
    await modules.stream.firstWhere((state) => state.optionsModule == null);

    modules.add(const ModulesOptionsToggled('clock'));
    await modules.stream.firstWhere((state) => state.optionsModule == 'clock');
    modules.add(const ModulesOptionsClosed());
    await modules.stream.firstWhere((state) => state.optionsModule == null);
  });

  test('availability and drags clear the options selection', () async {
    final settings = SettingsAppBloc();
    addTearDown(settings.close);
    final modules = ModulesBloc(
      settings: settings,
      availabilityProbe: () => const <ModuleAvailability>[],
    );
    addTearDown(modules.close);

    modules.add(const ModulesOptionsToggled('clock'));
    await modules.stream.firstWhere((state) => state.optionsModule == 'clock');

    modules.add(
      const ModulesAvailabilityLoaded([
        ModuleAvailability(
          module: 'clock',
          reason: ModuleUnavailableReason.noBattery,
        ),
      ]),
    );
    await modules.stream.firstWhere(
      (state) => state.optionsModule == null && state.unavailable.isNotEmpty,
    );

    modules.add(const ModulesOptionsToggled('cpu'));
    await modules.stream.firstWhere((state) => state.optionsModule == 'cpu');
    modules.add(
      const ModulesDragStarted(module: 'clock', zone: ModuleZone.trailing),
    );
    await modules.stream.firstWhere((state) => state.dragging == 'clock');
    expect(modules.state.optionsModule, isNull);
  });

  test(
    'disabling or dropping the active module clears its inspector',
    () async {
      final settings = SettingsAppBloc();
      addTearDown(settings.close);
      final modules = ModulesBloc(
        settings: settings,
        availabilityProbe: () => const <ModuleAvailability>[],
      );
      addTearDown(modules.close);

      modules.add(const ModulesOptionsToggled('clock'));
      await modules.stream.firstWhere(
        (state) => state.optionsModule == 'clock',
      );
      modules.add(const ModulesToggled(module: 'clock', enabled: false));
      await modules.stream.firstWhere((state) => state.optionsModule == null);
      expect(modules.state.optionsModule, isNull);

      modules.add(const ModulesOptionsToggled('cpu'));
      await modules.stream.firstWhere((state) => state.optionsModule == 'cpu');
      modules.add(const ModulesDroppedOnDisabled('cpu'));
      await modules.stream.firstWhere((state) => state.dropHandled);
      expect(modules.state.optionsModule, isNull);
    },
  );

  test('disabled unavailable modules keep their options open', () async {
    final settings = SettingsAppBloc();
    addTearDown(settings.close);
    settings.add(
      SettingsAppPreviewed(
        BarSettings(
          modules: [
            for (final module in BarSettings.knownModules)
              if (module != 'network') module,
          ],
        ),
      ),
    );
    await settings.stream.firstWhere(
      (state) => !state.settings.includes('network'),
    );
    final modules = ModulesBloc(
      settings: settings,
      availabilityProbe: () => const <ModuleAvailability>[],
    );
    addTearDown(modules.close);

    modules.add(const ModulesOptionsToggled('network'));
    await modules.stream.firstWhere(
      (state) => state.optionsModule == 'network',
    );
    modules.add(
      const ModulesAvailabilityLoaded([
        ModuleAvailability(
          module: 'network',
          reason: ModuleUnavailableReason.noNetwork,
        ),
      ]),
    );
    await modules.stream.firstWhere((state) => state.unavailable.isNotEmpty);
    expect(modules.state.optionsModule, 'network');
  });

  test('modules state round-trips its json', () {
    const state = ModulesState(
      unavailable: [
        ModuleAvailability(
          module: 'battery',
          reason: ModuleUnavailableReason.noBattery,
        ),
      ],
      optionsModule: 'clock',
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
      'options_module': 7,
      'preview_zone': 'nowhere',
      'last_pointer': 'not-an-offset',
    });
    expect(decoded.optionsModule, isNull);
    expect(decoded.previewZone, isNull);
    expect(decoded.lastPointer, isNull);
  });
}
