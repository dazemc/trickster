import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bootstrap.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/settings.dart';

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
