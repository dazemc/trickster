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

Future<Directory> _temporaryDir() async {
  final dir = await Directory.systemTemp.createTemp('sway-focus');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
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

const _initialWorkspaces = '''
[{"num":1,"name":"1","output":"eDP-1","visible":true,"focused":true,"urgent":false},
 {"num":2,"name":"web","output":"eDP-1","visible":false,"focused":false,"urgent":false}]''';

const _updatedWorkspaces = '''
[{"num":1,"name":"1","output":"eDP-1","visible":false,"focused":false,"urgent":false},
 {"num":2,"name":"web","output":"eDP-1","visible":true,"focused":true,"urgent":true}]''';

const _initialOutputs =
    '[{"name":"eDP-1","current_workspace":"1"},'
    '{"name":"HDMI-A-1","current_workspace":"1"}]';

const _updatedOutputs =
    '[{"name":"eDP-1","current_workspace":"web"},'
    '{"name":"HDMI-A-1","current_workspace":"1"}]';

/// A persistent Sway endpoint: records every frame, answers IPC requests,
/// and can fire workspace events. Frames can be split across writes to
/// exercise reassembly.
class _FakeSwayServer {
  _FakeSwayServer._(this._server);

  final ServerSocket _server;
  final requests = <({int type, String payload})>[];
  final _connections = <Socket>[];
  var workspacesReply = _initialWorkspaces;
  var outputsReply = _initialOutputs;
  var splitFrames = false;

  int get refreshCount =>
      requests.where((request) => request.type == 1).length;

  static Future<_FakeSwayServer> bind(String path) async {
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final fake = _FakeSwayServer._(server);
    server.listen(fake._onConnection);
    return fake;
  }

  void _onConnection(Socket socket) {
    _connections.add(socket);
    final buffer = <int>[];
    var tail = Future<void>.value();
    socket.listen((data) {
      buffer.addAll(data);
      var consumed = 0;
      final frames = <({int type, String payload})>[];
      while (buffer.length - consumed >= 14) {
        final view = ByteData.sublistView(
          Uint8List.fromList(buffer.sublist(consumed, consumed + 14)),
        );
        final length = view.getUint32(6, Endian.little);
        if (buffer.length - consumed < 14 + length) {
          break;
        }
        final type = view.getUint32(10, Endian.little);
        final payload = utf8.decode(
          buffer.sublist(consumed + 14, consumed + 14 + length),
        );
        consumed += 14 + length;
        frames.add((type: type, payload: payload));
      }
      buffer.removeRange(0, consumed);
      for (final frame in frames) {
        requests.add(frame);
        // Serialize replies: flush() marks the sink bound until it drains,
        // so two concurrent replies would throw.
        tail = tail.then((_) => _reply(socket, frame.type));
      }
    }, onError: (_) {});
    socket.done.then((_) => _connections.remove(socket));
  }

  Future<void> _reply(Socket socket, int type) async {
    if (type == 1) {
      final frame = _frame(1, workspacesReply);
      if (splitFrames && frame.length > 1) {
        final half = frame.length ~/ 2;
        socket.add(frame.sublist(0, half));
        await socket.flush();
        socket.add(frame.sublist(half));
      } else {
        socket.add(frame);
      }
      await socket.flush();
      return;
    }
    if (type == 2) {
      socket.add(_frame(2, '{"success":true}'));
      await socket.flush();
      return;
    }
    if (type == 3) {
      socket.add(_frame(3, outputsReply));
      await socket.flush();
    }
  }

  Future<void> fireWorkspaceEvent() async {
    for (final socket in _connections.toList()) {
      socket.add(_frame(0x80000003, '{"change":"focus"}'));
      await socket.flush();
    }
  }

  /// Drops every client connection, simulating a compositor-side socket loss.
  Future<void> dropConnections() async {
    for (final socket in _connections.toList()) {
      await socket.close();
    }
  }

  Future<void> dispose() async {
    for (final socket in _connections.toList()) {
      await socket.close();
    }
    await _server.close();
  }
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

void main() {
  test('start emits the snapshot and then stays quiet', () async {
    final dir = await _temporaryDir();
    final server = await _FakeSwayServer.bind('${dir.path}/ipc');
    addTearDown(server.dispose);

    final backend = SwayWorkspaces(socketPath: '${dir.path}/ipc');
    final snapshots = <List<Workspace>>[];
    final sub = backend.snapshots.listen(snapshots.add);
    await backend.start();
    await _waitFor(() => snapshots.length == 1);

    final workspaces = snapshots.single;
    expect(workspaces.map((workspace) => workspace.id), ['1', '2']);
    expect(workspaces.map((workspace) => workspace.name), ['1', 'web']);
    expect(workspaces[0].output, 'eDP-1');
    expect(workspaces[0].focused, isTrue);
    expect(workspaces[1].focused, isFalse);
    expect(
      server.requests.map((request) => request.type),
      [2, 1, 3],
      reason: 'subscribe, workspaces, and outputs requests',
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.refreshCount, 1, reason: 'replies must not re-request');

    await sub.cancel();
    await backend.dispose();
  });

  test('workspace events refresh and emit the updated focus', () async {
    final dir = await _temporaryDir();
    final server = await _FakeSwayServer.bind('${dir.path}/ipc');
    addTearDown(server.dispose);

    final backend = SwayWorkspaces(socketPath: '${dir.path}/ipc');
    final snapshots = <List<Workspace>>[];
    final sub = backend.snapshots.listen(snapshots.add);
    await backend.start();
    await _waitFor(() => snapshots.length == 1);

    server.workspacesReply = _updatedWorkspaces;
    server.outputsReply = _updatedOutputs;
    await server.fireWorkspaceEvent();
    await _waitFor(() => snapshots.length == 2);

    expect(snapshots[1][1].focused, isTrue);
    expect(snapshots[1][1].urgent, isTrue);
    expect(server.refreshCount, 2);

    await sub.cancel();
    await backend.dispose();
  });

  test('split frames reassemble across chunks', () async {
    final dir = await _temporaryDir();
    final server = await _FakeSwayServer.bind('${dir.path}/ipc');
    addTearDown(server.dispose);
    server.splitFrames = true;

    final backend = SwayWorkspaces(socketPath: '${dir.path}/ipc');
    final snapshots = <List<Workspace>>[];
    final sub = backend.snapshots.listen(snapshots.add);
    await backend.start();
    await _waitFor(() => snapshots.length == 1);

    expect(snapshots.single, hasLength(2));
    expect(snapshots.single[1].name, 'web');

    await sub.cancel();
    await backend.dispose();
  });

  test('malformed workspaces payload emits nothing', () async {
    final dir = await _temporaryDir();
    final server = await _FakeSwayServer.bind('${dir.path}/ipc');
    addTearDown(server.dispose);
    server.workspacesReply = 'not json{';

    final backend = SwayWorkspaces(socketPath: '${dir.path}/ipc');
    final snapshots = <List<Workspace>>[];
    final sub = backend.snapshots.listen(snapshots.add);
    await backend.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(snapshots, isEmpty);
    expect(server.refreshCount, 1);

    await sub.cancel();
    await backend.dispose();
  });

  test('reconnects and resubscribes after the socket drops', () async {
    final dir = await _temporaryDir();
    final server = await _FakeSwayServer.bind('${dir.path}/ipc');
    addTearDown(server.dispose);

    final backend = SwayWorkspaces(socketPath: '${dir.path}/ipc');
    final snapshots = <List<Workspace>>[];
    final sub = backend.snapshots.listen(snapshots.add);
    await backend.start();
    await _waitFor(() => snapshots.length == 1);

    await server.dropConnections();
    await _waitFor(() => server.requests.length >= 6);
    expect(
      server.requests.map((request) => request.type),
      [2, 1, 3, 2, 1, 3],
      reason: 'reconnect resubscribes and refreshes once',
    );
    // Identical state on reconnect is deduplicated, so no extra emission.
    expect(snapshots.length, 1);

    await sub.cancel();
    await backend.dispose();
  });

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

    final perOutput = await backend.focusWorkspace(
      const Workspace(id: '2', name: 'web', output: 'eDP-1'),
    );
    expect(perOutput, isTrue);
    expect(commands.last, 'workspace web output eDP-1');
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
