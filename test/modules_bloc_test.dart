import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/services/network.dart';
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

  test('a corrected disk path clears the stale disk row', () async {
    final root = Directory.systemTemp.createTempSync('trickster-disk-refresh');
    addTearDown(() => root.deleteSync(recursive: true));
    final missing = '${root.path}/missing';
    final mount = Directory('${root.path}/mount');

    final settings = SettingsAppBloc();
    addTearDown(settings.close);
    settings.add(
      SettingsAppPreviewed(
        BarSettings(
          modules: BarSettings.knownModules,
          disk: DiskOptions(path: missing),
        ),
      ),
    );
    await settings.stream.firstWhere(
      (state) => state.settings.disk.path == missing,
    );

    final modules = ModulesBloc(
      settings: settings,
      availabilityProbe: () {
        final document = settings.settings;
        return [
          if (!hasDiskMount(document.disk.path))
            const ModuleAvailability(
              module: 'disk',
              reason: ModuleUnavailableReason.noDisk,
            ),
        ];
      },
    );
    addTearDown(modules.close);
    expect(
      modules.state.unavailable.map((entry) => entry.module),
      contains('disk'),
    );
    final modulesBefore = settings.settings.modules;

    mount.createSync();
    settings.add(
      SettingsAppPreviewed(
        settings.settings.copyWith(
          disk: const DiskOptions().copyWith(path: mount.path),
        ),
      ),
    );
    final refreshed = await modules.stream
        .firstWhere(
          (state) => state.unavailable.every((entry) => entry.module != 'disk'),
        )
        .timeout(const Duration(seconds: 2));

    expect(refreshed.unavailable, isEmpty);
    expect(settings.settings.modules, modulesBefore);
    expect(settings.settings.disk.path, mount.path);
  });

  test('a missing pinned interface enters the unavailable list', () async {
    final root = Directory.systemTemp.createTempSync('trickster-net-refresh');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/enp1s0/device').createSync(recursive: true);

    final settings = SettingsAppBloc();
    addTearDown(settings.close);
    final modules = ModulesBloc(
      settings: settings,
      availabilityProbe: () {
        final document = settings.settings;
        return [
          if (!hasNetworkInterface(
            netRoot: root.path,
            pinned: document.network.interface,
          ))
            const ModuleAvailability(
              module: 'network',
              reason: ModuleUnavailableReason.noNetwork,
            ),
        ];
      },
    );
    addTearDown(modules.close);
    expect(modules.state.unavailable, isEmpty);

    modules.add(const ModulesOptionsToggled('network'));
    await modules.stream.firstWhere(
      (state) => state.optionsModule == 'network',
    );
    settings.add(
      SettingsAppPreviewed(
        settings.settings.copyWith(
          network: const NetworkOptions(interface: 'missing0'),
        ),
      ),
    );
    final refreshed = await modules.stream
        .firstWhere(
          (state) =>
              state.unavailable.any((entry) => entry.module == 'network'),
        )
        .timeout(const Duration(seconds: 2));

    expect(
      refreshed.unavailable.single.reason,
      ModuleUnavailableReason.noNetwork,
    );
    // Enabled and now unrunnable: the inspector has no gear to return to.
    expect(refreshed.optionsModule, isNull);

    // A disabled module keeps its inspector when it becomes runnable again.
    settings.add(
      SettingsAppPreviewed(
        settings.settings.copyWith(
          modules: [
            for (final module in settings.settings.modules)
              if (module != 'network') module,
          ],
        ),
      ),
    );
    await settings.stream.firstWhere(
      (state) => !state.settings.includes('network'),
    );
    modules.add(const ModulesOptionsToggled('network'));
    await modules.stream.firstWhere(
      (state) => state.optionsModule == 'network',
    );

    settings.add(
      SettingsAppPreviewed(
        settings.settings.copyWith(network: const NetworkOptions()),
      ),
    );
    final available = await modules.stream
        .firstWhere((state) => state.unavailable.isEmpty)
        .timeout(const Duration(seconds: 2));
    expect(available.optionsModule, 'network');
  });

  test(
    'refreshes are idempotent and leave disabled modules in place',
    () async {
      final settings = SettingsAppBloc();
      addTearDown(settings.close);
      settings.add(
        SettingsAppPreviewed(
          const BarSettings(modules: ['clock'], modulePlacement: {}),
        ),
      );
      await settings.stream.firstWhere(
        (state) => state.settings.modules.length == 1,
      );
      final modules = ModulesBloc(
        settings: settings,
        availabilityProbe: () => const [
          ModuleAvailability(
            module: 'network',
            reason: ModuleUnavailableReason.noNetwork,
          ),
        ],
      );
      addTearDown(modules.close);
      modules.add(const ModulesOptionsToggled('network'));
      await modules.stream.firstWhere(
        (state) => state.optionsModule == 'network',
      );

      modules
        ..refreshAvailability()
        ..refreshAvailability();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        modules.state.unavailable.where((entry) => entry.module == 'network'),
        hasLength(1),
      );
      expect(modules.state.optionsModule, 'network');
      expect(settings.settings.includes('network'), isFalse);
      final groups = moduleGroups(settings.settings, modules.state.unavailable);
      expect([
        for (final entry in groups.values) ...entry,
      ], isNot(contains('network')));
    },
  );

  test('a throwing loader keeps the last good availability', () async {
    final settings = SettingsAppBloc();
    addTearDown(settings.close);
    var calls = 0;
    final modules = ModulesBloc(
      settings: settings,
      availabilityProbe: () => const [
        ModuleAvailability(
          module: 'network',
          reason: ModuleUnavailableReason.noNetwork,
        ),
      ],
      availabilityLoader: (_) async {
        calls += 1;
        if (calls == 1) {
          throw StateError('control socket closed');
        }
        return const <ModuleAvailability>[];
      },
    );
    addTearDown(modules.close);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(modules.state.unavailable.single.module, 'network');

    modules.refreshAvailability();
    final recovered = await modules.stream
        .firstWhere((state) => state.unavailable.isEmpty)
        .timeout(const Duration(seconds: 2));
    expect(recovered.unavailable, isEmpty);
    expect(calls, 2);
  });

  test('a stale loader answer cannot overwrite newer inputs', () async {
    final settings = SettingsAppBloc();
    addTearDown(settings.close);
    settings.add(
      SettingsAppPreviewed(
        const BarSettings(disk: DiskOptions(path: '/first-mount')),
      ),
    );
    await settings.stream.firstWhere(
      (state) => state.settings.disk.path == '/first-mount',
    );

    final first = Completer<List<ModuleAvailability>>();
    final second = Completer<List<ModuleAvailability>>();
    var calls = 0;
    final modules = ModulesBloc(
      settings: settings,
      availabilityProbe: () => const <ModuleAvailability>[],
      availabilityLoader: (_) {
        calls += 1;
        return calls == 1 ? first.future : second.future;
      },
    );
    addTearDown(modules.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);

    settings.add(
      SettingsAppPreviewed(
        settings.settings.copyWith(
          disk: const DiskOptions(path: '/second-mount'),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(calls, 2);

    // The first request answers for /first-mount after /second-mount was
    // typed. It must not replace the availability the page will show.
    first.complete(const [
      ModuleAvailability(
        module: 'disk',
        reason: ModuleUnavailableReason.noDisk,
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(modules.state.unavailable, isEmpty);

    second.complete(const [
      ModuleAvailability(
        module: 'network',
        reason: ModuleUnavailableReason.noNetwork,
      ),
    ]);
    final settled = await modules.stream
        .firstWhere((state) => state.unavailable.isNotEmpty)
        .timeout(const Duration(seconds: 2));
    expect(settled.unavailable.single.module, 'network');
  });

  test('reset closes an inspector that would lose its gear', () async {
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
      availabilityProbe: () => const [
        ModuleAvailability(
          module: 'network',
          reason: ModuleUnavailableReason.noNetwork,
        ),
      ],
    );
    addTearDown(modules.close);

    modules.add(const ModulesOptionsToggled('network'));
    await modules.stream.firstWhere(
      (state) => state.optionsModule == 'network',
    );
    modules.add(const ModulesReset());
    final closed = await modules.stream.firstWhere(
      (state) => state.optionsModule == null,
    );
    expect(closed.optionsModule, isNull);

    // An available module keeps its inspector across the same reset.
    modules.add(const ModulesOptionsToggled('clock'));
    await modules.stream.firstWhere((state) => state.optionsModule == 'clock');
    modules.add(const ModulesReset());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(modules.state.optionsModule, 'clock');
  });

  test('enabling an unavailable module closes its inspector', () async {
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
      availabilityProbe: () => const [
        ModuleAvailability(
          module: 'network',
          reason: ModuleUnavailableReason.noNetwork,
        ),
      ],
    );
    addTearDown(modules.close);

    modules.add(const ModulesOptionsToggled('network'));
    await modules.stream.firstWhere(
      (state) => state.optionsModule == 'network',
    );
    modules.add(const ModulesToggled(module: 'network', enabled: true));
    final closed = await modules.stream.firstWhere(
      (state) => state.optionsModule == null,
    );
    expect(closed.optionsModule, isNull);
  });

  test('a disabled-row drag previews nothing until a real zone', () async {
    final settings = SettingsAppBloc();
    addTearDown(settings.close);
    settings.add(
      SettingsAppPreviewed(
        BarSettings(
          modules: [
            for (final module in BarSettings.knownModules)
              if (module != 'gpu') module,
          ],
        ),
      ),
    );
    await settings.stream.firstWhere(
      (state) => !state.settings.includes('gpu'),
    );
    final modules = ModulesBloc(
      settings: settings,
      availabilityProbe: () => const <ModuleAvailability>[],
    );
    addTearDown(modules.close);

    modules.add(
      ModulesDragStarted(
        module: 'gpu',
        zone: settings.settings.zoneFor('gpu'),
        fromDisabled: true,
      ),
    );
    final started = await modules.stream.firstWhere(
      (state) => state.dragging == 'gpu',
    );
    expect(started.draggingFromDisabled, isTrue);
    expect(started.previewZone, isNull);
    expect(started.previewIndex, 0);

    modules.add(
      const ModulesDragPreviewed(
        zone: ModuleZone.leading,
        index: 0,
        position: Offset(10, 20),
      ),
    );
    final previewed = await modules.stream.firstWhere(
      (state) => state.previewZone == ModuleZone.leading,
    );
    expect(previewed.previewIndex, 0);
    expect(previewed.lastPointer, const Offset(10, 20));
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
      draggingFromDisabled: true,
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
