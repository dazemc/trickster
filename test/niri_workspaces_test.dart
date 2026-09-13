import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/workspaces.dart';

Future<Directory> _temporaryDir() async {
  final dir = await Directory.systemTemp.createTemp('niri-focus');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

Future<ServerSocket> _bindActionServer(
  String path,
  String reply,
  List<String> requests,
) async {
  final server = await ServerSocket.bind(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
  );
  server.listen((socket) async {
    final request = utf8.decode(await socket.first).trim();
    requests.add(request);
    socket.add(utf8.encode('$reply\n'));
    await socket.flush();
    await socket.close();
  });
  return server;
}

void main() {
  test('focus sends the niri action with an id reference', () async {
    final dir = await _temporaryDir();
    final requests = <String>[];
    final server = await _bindActionServer(
      '${dir.path}/ipc',
      '{"Ok":"Handled"}',
      requests,
    );
    addTearDown(server.close);

    final backend = NiriWorkspaces(socketPath: '${dir.path}/ipc');
    final focused = await backend.focusWorkspace(
      const Workspace(id: '5', name: 'web'),
    );
    expect(focused, isTrue);
    expect(jsonDecode(requests.single), {
      'Action': {
        'FocusWorkspace': {
          'reference': {'Id': 5},
        },
      },
    });
  });

  test('named workspaces fall back to a name reference', () async {
    final dir = await _temporaryDir();
    final requests = <String>[];
    final server = await _bindActionServer(
      '${dir.path}/ipc',
      '{"Ok":"Handled"}',
      requests,
    );
    addTearDown(server.close);

    final backend = NiriWorkspaces(socketPath: '${dir.path}/ipc');
    final focused = await backend.focusWorkspace(
      const Workspace(id: 'web', name: 'web'),
    );
    expect(focused, isTrue);
    expect(jsonDecode(requests.single), {
      'Action': {
        'FocusWorkspace': {
          'reference': {'Name': 'web'},
        },
      },
    });
  });

  test('niri error reply reports failure', () async {
    final dir = await _temporaryDir();
    final server = await _bindActionServer(
      '${dir.path}/ipc',
      '{"Err":"Workspace not found"}',
      <String>[],
    );
    addTearDown(server.close);

    final backend = NiriWorkspaces(socketPath: '${dir.path}/ipc');
    expect(
      await backend.focusWorkspace(const Workspace(id: '5', name: 'web')),
      isFalse,
    );
  });

  test('missing niri socket reports failure instead of hanging', () async {
    final backend = NiriWorkspaces(socketPath: '/nonexistent/niri-ipc');
    expect(
      await backend.focusWorkspace(const Workspace(id: '5', name: 'web')),
      isFalse,
    );
  });
}
