import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/layout/system_bar.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('trickster-outputs');
    file = File('${directory.path}/outputs.conf');
  });

  tearDown(() => directory.delete(recursive: true));

  test('reads defaults when the file is missing', () async {
    final transport = FileOutputsTransport(file);
    final config = OutputsConfig.parse(await transport.read());
    expect(config.side, SystemBarSide.top);
    expect(config.thickness, 32);
    expect(config.connectors, isEmpty);
  });

  test('writes the system_bar grammar and round-trips', () async {
    final transport = FileOutputsTransport(file);
    const config = OutputsConfig(
      side: SystemBarSide.bottom,
      thickness: 44,
      connectors: ['eDP-1', 'HDMI-A-1'],
    );
    await transport.write(config.encode());

    expect(
      file.readAsStringSync(),
      contains('system_bar=bottom,44,eDP-1,HDMI-A-1'),
    );
    final decoded = OutputsConfig.parse(file.readAsStringSync());
    expect(decoded.side, SystemBarSide.bottom);
    expect(decoded.thickness, 44);
    expect(decoded.connectors, ['eDP-1', 'HDMI-A-1']);
  });

  test('hidden encodes without geometry', () async {
    final transport = FileOutputsTransport(file);
    await transport.write(
      const OutputsConfig(side: SystemBarSide.hidden, thickness: 32).encode(),
    );
    expect(file.readAsStringSync(), contains('system_bar=hidden'));
  });

  test('rejects an invalid document before writing', () async {
    final transport = FileOutputsTransport(file);
    await expectLater(
      transport.write('system_bar=middle,32'),
      throwsFormatException,
    );
    expect(file.existsSync(), isFalse);
  });
}
