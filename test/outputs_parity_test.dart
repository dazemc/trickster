import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bootstrap.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/layout/system_bar.dart';

/// Both processes read the same `outputs.conf`. The settings application uses
/// [FileOutputsTransport]; bootstrap must reach the same placement decision,
/// and only differ in how it reports the live document's state.
void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('trickster-outputs-parity');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  ConfigPaths paths() {
    final paths = ConfigPaths(configHome: directory.path);
    Directory(paths.root).createSync(recursive: true);
    return paths;
  }

  Future<void> expectAgreement(
    ConfigPaths paths, {
    required OutputsConfig placement,
    required bool warns,
    required bool errors,
  }) async {
    final runtime = Bootstrap.load(paths: paths);
    final transport = OutputsConfig.parse(
      await FileOutputsTransport(File(paths.outputs)).read(),
    );

    expect(runtime.outputs, placement, reason: 'bootstrap placement');
    expect(transport, placement, reason: 'settings transport placement');
    expect(runtime.outputsWarning != null, warns, reason: 'warning');
    expect(runtime.outputsError != null, errors, reason: 'error');
  }

  test('comments-only live recovers the snapshot in both processes', () async {
    final config = paths();
    File(config.outputs).writeAsStringSync('# my layout\n');
    File('${config.outputs}.prev').writeAsStringSync('system_bar=bottom,44\n');

    await expectAgreement(
      config,
      placement: const OutputsConfig(side: SystemBarSide.bottom, thickness: 44),
      warns: true,
      errors: false,
    );
  });

  test('comments plus unrelated keys still recover the snapshot', () async {
    final config = paths();
    File(config.outputs).writeAsStringSync('# my layout\nGAMMA=1.0\n');
    File('${config.outputs}.prev').writeAsStringSync('system_bar=right,64\n');

    await expectAgreement(
      config,
      placement: const OutputsConfig(side: SystemBarSide.right, thickness: 64),
      warns: true,
      errors: false,
    );
  });

  test(
    'comments-only live with no snapshot is benign in both processes',
    () async {
      final config = paths();
      File(config.outputs).writeAsStringSync(
        '# Trickster output configuration\n# system_bar=top,32\n',
      );

      await expectAgreement(
        config,
        placement: const OutputsConfig(),
        warns: false,
        errors: false,
      );
    },
  );

  test('empty live recovers the snapshot in both processes', () async {
    final config = paths();
    File(config.outputs).writeAsStringSync('');
    File('${config.outputs}.prev').writeAsStringSync('system_bar=left,72\n');

    await expectAgreement(
      config,
      placement: const OutputsConfig(side: SystemBarSide.left, thickness: 72),
      warns: true,
      errors: false,
    );
  });

  test('corrupt live recovers the snapshot in both processes', () async {
    final config = paths();
    File(config.outputs).writeAsStringSync('system_bar=nonsense,40\n');
    File(
      '${config.outputs}.prev',
    ).writeAsStringSync('system_bar=bottom,40,eDP-1\n');

    await expectAgreement(
      config,
      placement: const OutputsConfig(
        side: SystemBarSide.bottom,
        thickness: 40,
        connectors: <String>['eDP-1'],
      ),
      warns: true,
      errors: false,
    );
  });

  test('a valid live document wins over the snapshot', () async {
    final config = paths();
    File(config.outputs).writeAsStringSync('system_bar=bottom,44\n');
    File('${config.outputs}.prev').writeAsStringSync('system_bar=left,72\n');

    await expectAgreement(
      config,
      placement: const OutputsConfig(side: SystemBarSide.bottom, thickness: 44),
      warns: false,
      errors: false,
    );
  });

  test(
    'a valid live rollback to a lower band wins over the snapshot',
    () async {
      final config = paths();
      File(config.outputs).writeAsStringSync('system_bar=top,20\n');
      File(
        '${config.outputs}.prev',
      ).writeAsStringSync('system_bar=bottom,44\n');

      await expectAgreement(
        config,
        placement: const OutputsConfig(side: SystemBarSide.top, thickness: 20),
        warns: false,
        errors: false,
      );
    },
  );

  test('empty live with no usable snapshot is an error in bootstrap', () async {
    final config = paths();
    File(config.outputs).writeAsStringSync('');

    await expectAgreement(
      config,
      placement: const OutputsConfig(),
      warns: false,
      errors: true,
    );
  });

  test(
    'corrupt live with no usable snapshot is an error in bootstrap',
    () async {
      final config = paths();
      File(config.outputs).writeAsStringSync('system_bar=nonsense,40\n');
      File('${config.outputs}.prev').writeAsStringSync('not a document\n');

      await expectAgreement(
        config,
        placement: const OutputsConfig(),
        warns: false,
        errors: true,
      );
    },
  );
}
