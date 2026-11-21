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

  test('writes atomically and leaves no temp file behind', () async {
    final transport = FileOutputsTransport(file);
    await transport.write(
      const OutputsConfig(side: SystemBarSide.top, thickness: 32).encode(),
    );

    final entries = directory
        .listSync()
        .map((entity) => entity.uri.pathSegments.last)
        .toSet();
    expect(entries, {'outputs.conf'});
    expect(file.readAsStringSync(), contains('system_bar=top,32\n'));
  });

  test('snapshots the previous document in .prev', () async {
    final transport = FileOutputsTransport(file);
    await transport.write(
      const OutputsConfig(
        side: SystemBarSide.top,
        thickness: 32,
        connectors: <String>['eDP-1'],
      ).encode(),
    );
    final first = file.readAsStringSync();

    await transport.write(
      const OutputsConfig(side: SystemBarSide.bottom, thickness: 44).encode(),
    );
    final previous = File('${file.path}.prev');
    expect(previous.existsSync(), isTrue);
    expect(previous.readAsStringSync(), first);
    expect(file.readAsStringSync(), contains('system_bar=bottom,44\n'));

    // A second write refreshes the single snapshot; no history accumulates.
    await transport.write(
      const OutputsConfig(side: SystemBarSide.left, thickness: 72).encode(),
    );
    expect(previous.readAsStringSync(), contains('system_bar=bottom,44'));
    expect(
      directory
          .listSync()
          .where((entity) => entity.path.contains('.prev.'))
          .map((entity) => entity.path),
      isEmpty,
    );
  });

  test('recovers from a corrupt live document through .prev', () async {
    final transport = FileOutputsTransport(file);
    const good = OutputsConfig(
      side: SystemBarSide.bottom,
      thickness: 40,
      connectors: <String>['eDP-1'],
    );
    await transport.write(good.encode());
    await transport.write(
      const OutputsConfig(side: SystemBarSide.top, thickness: 32).encode(),
    );

    file.writeAsStringSync('system_bar=top,NaN\n');
    final recovered = OutputsConfig.parse(await transport.read());
    expect(recovered, good);
  });

  test('recovers from an empty live document through .prev', () async {
    final transport = FileOutputsTransport(file);
    const good = OutputsConfig(
      side: SystemBarSide.right,
      thickness: 60,
      connectors: <String>['HDMI-A-1'],
    );
    await transport.write(good.encode());
    await transport.write(
      const OutputsConfig(side: SystemBarSide.top, thickness: 32).encode(),
    );

    file.writeAsStringSync('');
    expect(OutputsConfig.parse(await transport.read()), good);
  });

  test('recovers .prev when the live document is missing', () async {
    final transport = FileOutputsTransport(file);
    const good = OutputsConfig(side: SystemBarSide.left, thickness: 72);
    await transport.write(good.encode());
    await transport.write(
      const OutputsConfig(side: SystemBarSide.top, thickness: 32).encode(),
    );

    file.deleteSync();
    expect(OutputsConfig.parse(await transport.read()), good);
  });

  test('a valid live document wins over .prev', () async {
    final transport = FileOutputsTransport(file);
    await transport.write(
      const OutputsConfig(side: SystemBarSide.top, thickness: 32).encode(),
    );
    await transport.write(
      const OutputsConfig(side: SystemBarSide.bottom, thickness: 44).encode(),
    );

    file.writeAsStringSync('system_bar=left,72\n');
    expect(
      OutputsConfig.parse(await transport.read()),
      const OutputsConfig(side: SystemBarSide.left, thickness: 72),
    );
  });

  test('falls back to defaults only when no valid document exists', () async {
    final transport = FileOutputsTransport(file);
    await transport.write(
      const OutputsConfig(side: SystemBarSide.top, thickness: 32).encode(),
    );
    await transport.write(
      const OutputsConfig(side: SystemBarSide.bottom, thickness: 44).encode(),
    );
    file.writeAsStringSync('');
    File('${file.path}.prev').writeAsStringSync('system_bar=top,Infinity\n');

    expect(OutputsConfig.parse(await transport.read()), const OutputsConfig());
  });

  test(
    'an invalid write leaves the live document and snapshot alone',
    () async {
      final transport = FileOutputsTransport(file);
      await transport.write(
        const OutputsConfig(side: SystemBarSide.top, thickness: 32).encode(),
      );
      await transport.write(
        const OutputsConfig(side: SystemBarSide.bottom, thickness: 44).encode(),
      );
      final live = file.readAsStringSync();
      final previous = File('${file.path}.prev').readAsStringSync();

      await expectLater(
        transport.write('system_bar=top,1e999\n'),
        throwsFormatException,
      );
      expect(file.readAsStringSync(), live);
      expect(File('${file.path}.prev').readAsStringSync(), previous);
    },
  );

  test('preserves comments and unrelated keys when rewriting', () async {
    final transport = FileOutputsTransport(file);
    file.writeAsStringSync(
      '# my layout\n'
      'GAMMA=1.0\n'
      'system_bar=top,32,eDP-1\n'
      '# trailing note\n',
    );

    await transport.write(
      const OutputsConfig(side: SystemBarSide.left, thickness: 72).encode(),
    );

    expect(
      file.readAsStringSync(),
      '# my layout\n'
      'GAMMA=1.0\n'
      'system_bar=left,72\n'
      '# trailing note\n',
    );
  });

  test('inserts system_bar without discarding comments', () async {
    final transport = FileOutputsTransport(file);
    file.writeAsStringSync('# mine\nDEBUG=1\n');

    await transport.write(
      const OutputsConfig(side: SystemBarSide.bottom, thickness: 40).encode(),
    );

    expect(file.readAsStringSync(), '# mine\nDEBUG=1\nsystem_bar=bottom,40\n');
  });

  test('server rejection stays on the socket and surfaces the error', () async {
    final socket = SocketOutputsTransport(
      request: (request) async => <String, Object?>{
        'ok': false,
        'error': 'permission denied',
      },
    );
    final transport = FallbackOutputsTransport(
      socket: socket,
      file: FileOutputsTransport(file),
    );

    await expectLater(
      transport.write(const OutputsConfig().encode()),
      throwsA(
        isA<OutputsRequestException>().having(
          (error) => error.message,
          'message',
          contains('permission denied'),
        ),
      ),
    );
    expect(transport.usingSocket, isTrue);
    expect(file.existsSync(), isFalse);

    await expectLater(
      transport.read(),
      throwsA(isA<OutputsRequestException>()),
    );
    expect(transport.usingSocket, isTrue);
  });

  test('genuine transport loss still flips to the file', () async {
    final transport = FallbackOutputsTransport(
      socket: _NoBarOutputsSocket(),
      file: FileOutputsTransport(file),
    );

    expect(OutputsConfig.parse(await transport.read()).side, SystemBarSide.top);
    expect(transport.usingSocket, isFalse);
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

class _NoBarOutputsSocket implements OutputsDocumentTransport {
  @override
  Future<String> read() async => throw const ControlSocketException('no bar');

  @override
  Future<String> write(String document) async =>
      throw const ControlSocketException('no bar');
}
