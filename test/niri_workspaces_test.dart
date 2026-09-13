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

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Serves the niri event stream: every `EventStream` request gets the
/// current workspace snapshot replayed, matching niri's behavior on connect.
class _FakeNiriServer {
  _FakeNiriServer._(this._server);

  final ServerSocket _server;
  final requests = <String>[];
  final _streams = <Socket>[];
  var workspaces = const [
    {'id': 1, 'idx': 1, 'is_focused': true, 'active_window_id': 10},
    {'id': 2, 'idx': 2, 'is_focused': false},
  ];

  static Future<_FakeNiriServer> bind(String path) async {
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final fake = _FakeNiriServer._(server);
    server.listen(fake._onConnection);
    return fake;
  }

  void _onConnection(Socket socket) {
    socket.listen((data) {
      final line = utf8.decode(data).trim();
      requests.add(line);
      if (line.contains('EventStream')) {
        _streams.add(socket);
        _sendSnapshot(socket);
      }
    }, onError: (_) {});
    socket.done.then((_) => _streams.remove(socket));
  }

  void _sendSnapshot(Socket socket) {
    socket.add(
      utf8.encode(
        '${jsonEncode({
          'WorkspacesChanged': {'workspaces': workspaces},
        })}\n',
      ),
    );
  }

  Future<void> dropStreams() async {
    for (final socket in _streams.toList()) {
      await socket.close();
    }
  }

  Future<void> dispose() async {
    for (final socket in _streams.toList()) {
      await socket.close();
    }
    await _server.close();
  }
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

  test('reconnects the event stream and replays workspace state', () async {
    final dir = await _temporaryDir();
    final server = await _FakeNiriServer.bind('${dir.path}/ipc');
    addTearDown(server.dispose);

    final backend = NiriWorkspaces(socketPath: '${dir.path}/ipc');
    final snapshots = <List<Workspace>>[];
    final sub = backend.snapshots.listen(snapshots.add);
    await backend.start();
    await _waitFor(() => snapshots.length == 1);
    expect(snapshots.single[0].focused, isTrue);
    expect(snapshots.single[0].occupied, isTrue);

    server.workspaces = const [
      {'id': 1, 'idx': 1, 'is_focused': false, 'active_window_id': 10},
      {'id': 2, 'idx': 2, 'is_focused': true},
    ];
    await server.dropStreams();
    await _waitFor(() => snapshots.length == 2);
    expect(snapshots[1][1].focused, isTrue);
    expect(
      server.requests.where((request) => request.contains('EventStream')),
      hasLength(2),
      reason: 'the stream request is replayed after a drop',
    );

    await sub.cancel();
    await backend.dispose();
  });
}
