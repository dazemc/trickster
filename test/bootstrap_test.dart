import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bootstrap.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('trickster-seed');
  });

  tearDown(() {
    home.deleteSync(recursive: true);
  });

  test('first launch copies the packaged template, settings decode', () {
    final template = File('${home.path}/template.conf')
      ..writeAsStringSync('# Packaged template\nsystem_bar=bottom,40\n');
    final paths = ConfigPaths(configHome: '${home.path}/config');

    Bootstrap.seedUserConfig(paths, outputsTemplate: template.path);

    expect(
      File(paths.outputs).readAsStringSync(),
      '# Packaged template\nsystem_bar=bottom,40\n',
    );
    final settings = BarSettings.decode(
      File(paths.settings).readAsStringSync(),
    );
    expect(settings.modules, const BarSettings().modules);
  });

  test('existing per-user config is never overwritten', () {
    final paths = ConfigPaths(configHome: '${home.path}/config')
      ..directory.createSync(recursive: true);
    File(paths.outputs).writeAsStringSync('# mine\nsystem_bar=hidden\n');
    File(paths.settings).writeAsStringSync('{"revision": 9}');

    Bootstrap.seedUserConfig(paths, outputsTemplate: null);

    expect(
      File(paths.outputs).readAsStringSync(),
      '# mine\nsystem_bar=hidden\n',
    );
    expect(File(paths.settings).readAsStringSync(), '{"revision": 9}');
  });

  test(
    'malformed scalar values fall back to defaults and surface strict error',
    () {
      final paths = ConfigPaths(configHome: home.path);
      Directory(paths.root).createSync(recursive: true);
      File(
        paths.settings,
      ).writeAsStringSync('{"revision":1,"clock":{"show_date":"yes"}}');

      final runtime = Bootstrap.load(paths: paths);
      expect(runtime.settings, const BarSettings());
      final strict = Bootstrap.load(paths: paths, strict: true);
      expect(strict.settings, const BarSettings());
      expect(strict.settingsError, isNotNull);
      expect(strict.outputsError, isNull);
    },
  );

  test('normal load recovers a corrupt live settings file from .prev', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(paths.settings).writeAsStringSync('{"revision":9,"modules":');
    File(
      '${paths.settings}.prev',
    ).writeAsStringSync(const BarSettings(revision: 4).encode());

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.settings.revision, 4);
    final strict = Bootstrap.load(paths: paths, strict: true);
    expect(strict.settingsError, isNotNull);
    expect(strict.settings, const BarSettings());
  });

  test('strict reload keeps settings and outputs independent', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(paths.outputs).writeAsStringSync('system_bar=bottom,40\n');
    File(paths.settings).writeAsStringSync('{"revision":3,"modules":');

    final settingsBroken = Bootstrap.load(paths: paths, strict: true);
    expect(settingsBroken.outputs.side, SystemBarSide.bottom);
    expect(settingsBroken.outputs.thickness, 40);
    expect(settingsBroken.outputsError, isNull);
    expect(settingsBroken.settingsError, isNotNull);

    File(
      paths.settings,
    ).writeAsStringSync(const BarSettings(revision: 3, locale: 'zh').encode());
    File(paths.outputs).writeAsStringSync('system_bar=nonsense,40\n');
    final outputsBroken = Bootstrap.load(paths: paths, strict: true);
    expect(outputsBroken.settings.revision, 3);
    expect(outputsBroken.settings.locale, 'zh');
    expect(outputsBroken.settingsError, isNull);
    expect(outputsBroken.outputsError, isNotNull);
  });

  test('a recoverable .prev prevents seeding a default live document', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(
      '${paths.settings}.prev',
    ).writeAsStringSync(const BarSettings(revision: 7, locale: 'zh').encode());
    File('${paths.outputs}.prev').writeAsStringSync('system_bar=right,64\n');

    Bootstrap.seedUserConfig(paths, outputsTemplate: null);
    expect(File(paths.outputs).existsSync(), isFalse);
    expect(File(paths.settings).existsSync(), isFalse);

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.settings.revision, 7);
    expect(runtime.settings.locale, 'zh');
    expect(runtime.outputs.side, SystemBarSide.right);
    expect(runtime.outputs.thickness, 64);
    expect(runtime.outputsError, isNull);
  });

  test('a corrupt live outputs file recovers from a valid .prev', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(paths.outputs).writeAsStringSync('system_bar=nonsense,40\n');
    File(
      '${paths.outputs}.prev',
    ).writeAsStringSync('system_bar=bottom,40,eDP-1\n');

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.outputs.side, SystemBarSide.bottom);
    expect(runtime.outputs.thickness, 40);
    expect(runtime.outputs.connectors, ['eDP-1']);
    // The live parse error was logged, but a usable snapshot means reload
    // must apply it. `--check` still sees the live document as invalid.
    expect(runtime.outputsError, isNull);
    expect(runtime.outputsWarning, isNotNull);
  });

  test('a comment-only live outputs file recovers from a valid .prev', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(paths.outputs).writeAsStringSync('# my layout\n');
    File('${paths.outputs}.prev').writeAsStringSync('system_bar=bottom,44\n');

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.outputs.side, SystemBarSide.bottom);
    expect(runtime.outputs.thickness, 44);
    expect(runtime.outputsError, isNull);
    // The live document has no placement line, so `--check` still reports
    // it even though the bar applies the snapshot.
    expect(runtime.outputsWarning, isNotNull);
  });

  test(
    'a comment-only live outputs file without .prev is not a torn write',
    () {
      final paths = ConfigPaths(configHome: home.path);
      Directory(paths.root).createSync(recursive: true);
      // The shape the package seeds on first launch.
      File(paths.outputs).writeAsStringSync(
        '# Trickster output configuration\n# system_bar=top,32\n',
      );

      final runtime = Bootstrap.load(paths: paths);
      expect(runtime.outputs, const OutputsConfig());
      expect(runtime.outputsError, isNull);
      expect(runtime.outputsWarning, isNull);
    },
  );

  test('an empty live outputs file without .prev surfaces the error', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(paths.outputs).writeAsStringSync('');

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.outputs, const OutputsConfig());
    expect(runtime.outputsError, isNotNull);
    expect(runtime.outputsWarning, isNull);
  });

  test('an empty live outputs file recovers from a valid .prev', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(paths.outputs).writeAsStringSync('');
    File('${paths.outputs}.prev').writeAsStringSync('system_bar=left,72\n');

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.outputs.side, SystemBarSide.left);
    expect(runtime.outputs.thickness, 72);
    expect(runtime.outputsError, isNull);
    expect(runtime.outputsWarning, isNotNull);
  });

  test('a missing live outputs file recovers from a valid .prev', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File('${paths.outputs}.prev').writeAsStringSync('system_bar=bottom,48\n');

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.outputs.side, SystemBarSide.bottom);
    expect(runtime.outputs.thickness, 48);
    expect(runtime.outputsError, isNull);
    expect(runtime.outputsWarning, isNull);
  });

  test('corrupt live outputs without a usable .prev surfaces the error', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(paths.outputs).writeAsStringSync('system_bar=nonsense,40\n');

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.outputs, const OutputsConfig());
    expect(runtime.outputsError, isNotNull);
    expect(runtime.outputsWarning, isNull);
  });

  test('--edge reactivates a hidden outputs document at the default size', () {
    final paths = ConfigPaths(configHome: home.path);
    Directory(paths.root).createSync(recursive: true);
    File(paths.outputs).writeAsStringSync('system_bar=hidden\n');

    final runtime = Bootstrap.load(paths: paths, edge: 'top');
    expect(runtime.outputs.side, SystemBarSide.top);
    expect(runtime.outputs.thickness, OutputsConfig.defaultThickness);
    expect(runtime.outputs.active, isTrue);
  });

  test('an unwritable config directory never crashes seeding or load', () {
    final blocker = File('${home.path}/blocked')
      ..writeAsStringSync('not a directory');
    final paths = ConfigPaths(configHome: blocker.path);

    expect(() => Bootstrap.seedUserConfig(paths), returnsNormally);

    final runtime = Bootstrap.load(paths: paths);
    expect(runtime.outputs, const OutputsConfig());
    expect(runtime.settings, const BarSettings());
  });

  test('a missing template falls back to the built-in header', () {
    final paths = ConfigPaths(configHome: '${home.path}/config');

    Bootstrap.seedUserConfig(
      paths,
      outputsTemplate: '${home.path}/absent.conf',
    );

    expect(
      File(paths.outputs).readAsStringSync(),
      '# Trickster output configuration\n# system_bar=top,32\n',
    );
  });
}
