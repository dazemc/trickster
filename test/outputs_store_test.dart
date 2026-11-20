import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/control_socket.dart';

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

  test('a write falls back to the file and stays there', () async {
    const initial = OutputsConfig(side: SystemBarSide.top, thickness: 32);
    const saved = OutputsConfig(
      side: SystemBarSide.bottom,
      thickness: 40,
      connectors: <String>['eDP-1'],
    );
    final socket = _LosingOutputsSocket(initial.encode());
    final transport = FallbackOutputsTransport(
      socket: socket,
      file: FileOutputsTransport(file),
    );

    expect(OutputsConfig.parse(await transport.read()).side, SystemBarSide.top);
    expect(transport.usingSocket, isTrue);

    final written = OutputsConfig.parse(await transport.write(saved.encode()));
    expect(written.side, SystemBarSide.bottom);
    expect(written.thickness, 40);
    expect(transport.usingSocket, isFalse);
    expect(file.readAsStringSync(), contains('system_bar=bottom,40,eDP-1'));

    await transport.write(
      const OutputsConfig(side: SystemBarSide.hidden, thickness: 32).encode(),
    );
    expect(socket.writes, 1);
    expect(file.readAsStringSync(), contains('system_bar=hidden'));
  });
}

class _LosingOutputsSocket implements OutputsDocumentTransport {
  _LosingOutputsSocket(this.document);

  final String document;
  var writes = 0;

  @override
  Future<String> read() async => document;

  @override
  Future<String> write(String document) async {
    writes += 1;
    throw const ControlSocketException('bar exited');
  }
}
