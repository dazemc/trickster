import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bootstrap.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/config/watcher.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/settings/app.dart';
import 'package:trickster/src/settings/bloc.dart';

class _FakeLayerShell extends LayerShell {
  _FakeLayerShell()
    : super(channel: const MethodChannel('test/settings-paths'));

  @override
  Future<List<LayerOutput>> outputs() async => const <LayerOutput>[];
}

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('trickster-paths');
  });

  tearDown(() {
    home.deleteSync(recursive: true);
  });

  group('Bootstrap.resolvePaths', () {
    ConfigPaths resolve({
      String? configPath,
      Map<String, String>? environment,
      String? sessionPath,
      ConfigPaths? paths,
    }) {
      return Bootstrap.resolvePaths(
        configPath: configPath,
        environment: environment,
        sessionPath: sessionPath,
        paths: paths,
      );
    }

    String sessionFile(String override) {
      final file = File('${home.path}/session.conf')
        ..writeAsStringSync('TRICKSTER_OUTPUT_CONFIG=$override\n');
      return file.path;
    }

    test('CLI --config wins over the process environment and session', () {
      final session = sessionFile('${home.path}/session-output.conf');
      final paths = resolve(
        configPath: '${home.path}/cli-output.conf',
        environment: <String, String>{
          'HOME': '${home.path}/home',
          'XDG_CONFIG_HOME': '${home.path}/config',
          'TRICKSTER_OUTPUT_CONFIG': '${home.path}/env-output.conf',
        },
        sessionPath: session,
      );

      expect(paths.outputOverride, '${home.path}/cli-output.conf');
      expect(paths.outputs, '${home.path}/cli-output.conf');
    });

    test('the process environment wins over session.conf', () {
      final session = sessionFile('${home.path}/session-output.conf');
      final paths = resolve(
        environment: <String, String>{
          'HOME': '${home.path}/home',
          'XDG_CONFIG_HOME': '${home.path}/config',
          'TRICKSTER_OUTPUT_CONFIG': '${home.path}/env-output.conf',
        },
        sessionPath: session,
      );

      expect(paths.outputOverride, '${home.path}/env-output.conf');
    });

    test('session.conf fills the override when the environment is unset', () {
      final session = sessionFile('${home.path}/session-output.conf');
      final paths = resolve(
        environment: <String, String>{
          'HOME': '${home.path}/home',
          'XDG_CONFIG_HOME': '${home.path}/config',
        },
        sessionPath: session,
      );

      expect(paths.outputOverride, '${home.path}/session-output.conf');
      expect(paths.settings, '${home.path}/config/trickster/settings.json');
    });

    test('an empty override at every level falls back to the default root', () {
      final session = sessionFile('');
      final paths = resolve(
        configPath: '',
        environment: <String, String>{
          'HOME': '${home.path}/home',
          'XDG_CONFIG_HOME': '${home.path}/config',
          'TRICKSTER_OUTPUT_CONFIG': '',
        },
        sessionPath: session,
      );

      expect(paths.outputOverride, isNull);
      expect(paths.outputs, '${home.path}/config/trickster/outputs.conf');
    });

    test('an explicitly injected paths object wins over every source', () {
      final injected = ConfigPaths(
        configHome: '${home.path}/injected',
        outputOverride: '${home.path}/injected/custom.conf',
      );
      final paths = resolve(
        configPath: '${home.path}/cli-output.conf',
        environment: <String, String>{
          'HOME': '${home.path}/home',
          'XDG_CONFIG_HOME': '${home.path}/config',
          'TRICKSTER_OUTPUT_CONFIG': '${home.path}/env-output.conf',
        },
        sessionPath: sessionFile('${home.path}/session-output.conf'),
        paths: injected,
      );

      expect(identical(paths, injected), isTrue);
    });

    test('a relative override becomes an absolute normalized path', () {
      final paths = resolve(
        configPath: './tmp/../tmp/relative-output.conf',
        environment: <String, String>{
          'HOME': '${home.path}/home',
          'XDG_CONFIG_HOME': '${home.path}/config',
        },
      );

      expect(File(paths.outputs).isAbsolute, isTrue);
      expect(
        paths.outputs,
        normalizeConfigPath('./tmp/../tmp/relative-output.conf'),
      );
      expect(paths.outputs, isNot(contains('/../')));
    });
  });

  group('settings path watches', () {
    test('watch plan covers the root and a custom outputs parent', () {
      final outputDirectory = Directory('${home.path}/override-outputs')
        ..createSync();
      final paths = ConfigPaths(
        configHome: '${home.path}/config',
        outputOverride: '${outputDirectory.path}/custom.conf',
      );

      expect(paths.watchDirectories.map((directory) => directory.path), [
        '${home.path}/config/trickster',
        outputDirectory.path,
      ]);
    });

    test('watch plan watches a nested outputs parent beside the root', () {
      final paths = ConfigPaths(
        configHome: '${home.path}/config',
        outputOverride: '${home.path}/config/trickster/nested/custom.conf',
      );

      expect(paths.watchDirectories.map((directory) => directory.path), [
        '${home.path}/config/trickster',
        '${home.path}/config/trickster/nested',
      ]);
    });

    test('a default outputs document needs one watch', () {
      final paths = ConfigPaths(configHome: '${home.path}/config');

      expect(paths.watchDirectories, hasLength(1));
      expect(paths.watchDirectories.single.path, paths.root);
    });

    test('the filter accepts exact custom paths and their spellings', () {
      final paths = ConfigPaths(
        configHome: '${home.path}/config',
        outputOverride:
            '${home.path}/config/./override/../override/custom.conf',
      );
      final include = configDocumentFilter(
        settings: paths.settings,
        outputs: paths.outputs,
      );

      expect(
        include(
          FileSystemCreateEvent(
            '${home.path}/config/override/custom.conf',
            false,
          ),
        ),
        isTrue,
      );
      expect(
        include(
          FileSystemCreateEvent(
            '${home.path}/config/./override/../override/custom.conf',
            false,
          ),
        ),
        isTrue,
      );
      expect(include(FileSystemCreateEvent(paths.settings, false)), isTrue);
      expect(
        include(
          FileSystemCreateEvent(
            '${home.path}/config/override/custom.conf.tmp.42',
            false,
          ),
        ),
        isFalse,
      );
      expect(
        include(
          FileSystemCreateEvent(
            '${home.path}/config/override/custom.conf.prev',
            false,
          ),
        ),
        isFalse,
      );
      expect(
        include(
          FileSystemCreateEvent(
            '${home.path}/config/override/outputs.conf',
            false,
          ),
        ),
        isFalse,
      );
      expect(
        include(
          FileSystemMoveEvent(
            '${home.path}/config/override/custom.conf.tmp.42',
            false,
            '${home.path}/config/./override/custom.conf',
          ),
        ),
        isTrue,
      );
    });

    test('settings app filter ignores a custom outputs path snarl', () {
      final paths = ConfigPaths(
        configHome: '${home.path}/config',
        outputOverride: '${home.path}/./override/../override/custom.conf',
      );

      expect(
        isEditedDocumentEvent(
          FileSystemCreateEvent('${home.path}/override/custom.conf', false),
          paths: paths,
        ),
        isTrue,
      );
      expect(
        isEditedDocumentEvent(
          FileSystemCreateEvent('${home.path}/override/other.conf', false),
          paths: paths,
        ),
        isFalse,
      );
    });
  });

  test('the settings bloc file transports use the resolved paths', () async {
    final paths = ConfigPaths(
      configHome: '${home.path}/config',
      outputOverride: '${home.path}/override/custom-outputs.conf',
    );
    Directory('${home.path}/override').createSync(recursive: true);
    File(paths.settings)
      ..createSync(recursive: true)
      ..writeAsStringSync(const BarSettings(revision: 6).encode());
    File(paths.outputs).writeAsStringSync('system_bar=bottom,44,eDP-1\n');
    final defaultOutputs = File('${paths.root}/outputs.conf');

    final bloc = SettingsAppBloc(
      socket: SocketSettingsTransport(socketPath: '${home.path}/no-bar.sock'),
      outputsSocket: SocketOutputsTransport(
        socketPath: '${home.path}/no-bar.sock',
      ),
      paths: paths,
      layerShell: _FakeLayerShell(),
    );
    addTearDown(bloc.close);
    bloc.add(const SettingsAppLoadRequested());
    await bloc.stream.firstWhere((state) => state.loaded);

    expect(bloc.settings.revision, 6);
    expect(bloc.outputs.side, SystemBarSide.bottom);
    expect(bloc.outputs.thickness, 44);
    expect(defaultOutputs.existsSync(), isFalse);

    bloc.add(
      const SettingsAppOutputsSaveRequested(
        OutputsConfig(side: SystemBarSide.left, thickness: 56),
      ),
    );
    await bloc.stream.firstWhere(
      (state) => !state.busy && state.outputs.side == SystemBarSide.left,
    );
    expect(
      File(paths.outputs).readAsStringSync(),
      contains('system_bar=left,56'),
    );
    expect(defaultOutputs.existsSync(), isFalse);

    bloc.add(SettingsAppSaveRequested(bloc.settings));
    await bloc.stream.firstWhere((state) => !state.busy);
    expect(bloc.error, isNull);
    expect(bloc.settings.revision, 7);
    expect(
      BarSettings.decode(File(paths.settings).readAsStringSync()).revision,
      7,
    );
  });
}
