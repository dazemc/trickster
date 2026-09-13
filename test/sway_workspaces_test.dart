import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/workspaces.dart';

Uint8List _frame(int type, String payload) {
  final body = utf8.encode(payload);
  final header = Uint8List(14);
  header.setAll(0, utf8.encode('i3-ipc'));
  final view = ByteData.sublistView(header);
  view.setUint32(6, body.length, Endian.little);
  view.setUint32(10, type, Endian.little);
  return Uint8List.fromList([...header, ...body]);
}

({int type, String payload}) _decodeRequest(List<int> bytes) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  final length = view.getUint32(6, Endian.little);
  final type = view.getUint32(10, Endian.little);
  return (type: type, payload: utf8.decode(bytes.sublist(14, 14 + length)));
}

Future<ServerSocket> _bindCommandServer(
  String path,
  Map<String, Object?> Function(String command) reply,
  List<String> commands,
) async {
  final server = await ServerSocket.bind(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
  );
  server.listen((socket) async {
    final request = await socket.first;
    final decoded = _decodeRequest(request);
    expect(decoded.type, 0);
    commands.add(decoded.payload);
    socket.add(_frame(0, jsonEncode(reply(decoded.payload))));
    await socket.flush();
    await socket.close();
  });
  return server;
}

Future<Directory> _temporaryDir() async {
  final dir = await Directory.systemTemp.createTemp('sway-focus');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  test('focus sends the workspace command over a one-shot connection', () async {
    final dir = await _temporaryDir();
    final commands = <String>[];
    final server = await _bindCommandServer(
      '${dir.path}/ipc',
      (_) => {'success': true},
      commands,
    );
    addTearDown(server.close);

    final backend = SwayWorkspaces(socketPath: '${dir.path}/ipc');
    final focused = await backend.focusWorkspace(
      const Workspace(id: '2', name: 'web'),
    );
    expect(focused, isTrue);
    expect(commands, ['workspace web']);
  });

  test('refused command reply reports failure', () async {
    final dir = await _temporaryDir();
    final server = await _bindCommandServer(
      '${dir.path}/ipc',
      (_) => {'success': false},
      <String>[],
    );
    addTearDown(server.close);

    final backend = SwayWorkspaces(socketPath: '${dir.path}/ipc');
    expect(
      await backend.focusWorkspace(const Workspace(id: '2', name: 'web')),
      isFalse,
    );
  });

  test('missing socket reports failure instead of hanging', () async {
    final backend = SwayWorkspaces(socketPath: '/nonexistent/sway-ipc');
    expect(
      await backend.focusWorkspace(const Workspace(id: '2', name: 'web')),
      isFalse,
    );
  });
}
