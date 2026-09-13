import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/workspaces.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

// Canned replies shaped like the real Hyprland IPC: `j/workspaces` carries
// no `focused` flag, urgency lives per-client in `j/clients`.
const _workspacesReply = '''
[{"id":1,"name":"1","monitor":"HDMI-A-1","windows":1},
 {"id":2,"name":"2","monitor":"HDMI-A-1","windows":0}]''';

const _activeReply = '{"id":2,"name":"2","monitor":"HDMI-A-1","windows":0}';

const _clientsReply = '''
[{"address":"0x1","urgent":false,"workspace":{"id":1,"name":"1"}},
 {"address":"0x2","urgent":false,"workspace":{"id":2,"name":"2"}}]''';

const _clientsUrgentReply = '''
[{"address":"0x1","urgent":true,"workspace":{"id":1,"name":"1"}},
 {"address":"0x2","urgent":false,"workspace":{"id":2,"name":"2"}}]''';

/// A fake Hyprland IPC endpoint: serves canned `j/*` replies on
/// `.socket.sock` and optionally accepts `.socket2.sock` event sinks.
/// Replies are split across two writes so the client must accumulate
/// chunks; with [keepOpen] the request connection stays open after the
/// reply, reproducing the Hyprland versions where reading until
/// socket-done hangs forever.
class _FakeHyprlandServer {
  _FakeHyprlandServer._(this.dir, this._ownsDir);

  final String dir;
  final bool _ownsDir;
  final replies = <String, List<int>>{};
  var keepOpen = false;

  ServerSocket? _requests;
  ServerSocket? _events;
  final _openClients = <Socket>{};
  final _eventSinks = <Socket>{};

  static Future<_FakeHyprlandServer> bind({
    bool keepOpen = false,
    bool withEvents = false,
    String? dir,
  }) async {
    final owned = dir == null;
    final path =
        dir ?? (await Directory.systemTemp.createTemp('hyprland-test')).path;
    final server = _FakeHyprlandServer._(path, owned)
      ..keepOpen = keepOpen
      ..replies['j/workspaces'] = utf8.encode(_workspacesReply)
      ..replies['j/activeworkspace'] = utf8.encode(_activeReply)
      ..replies['j/clients'] = utf8.encode(_clientsReply);
    server._requests = await ServerSocket.bind(
      InternetAddress('$path/.socket.sock', type: InternetAddressType.unix),
      0,
    );
    server._requests!.listen(server._serveRequest);
    if (withEvents) {
      server._events = await ServerSocket.bind(
        InternetAddress('$path/.socket2.sock',
            type: InternetAddressType.unix),
        0,
      );
      server._events!.listen((socket) {
        server._eventSinks.add(socket);
        socket.done.then((_) => server._eventSinks.remove(socket));
      });
    }
    return server;
  }

  Future<void> _serveRequest(Socket client) async {
    _openClients.add(client);
    try {
      final command = utf8.decode(await client.first);
      final reply = replies[command];
      if (reply != null) {
        // Split write: the client must accumulate, not assume one chunk.
        final half = reply.length ~/ 2;
        client.add(reply.sublist(0, half));
        await client.flush();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        client.add(reply.sublist(half));
        await client.flush();
      }
      if (!keepOpen) {
        await client.close();
      }
    } on Object {
      try {
        await client.close();
      } on Object {
        // Teardown races are not test failures.
      }
    }
  }

  /// Writes an event line, waiting for the backend to connect first.
  Future<void> fireEvent(String line) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (_eventSinks.isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('backend never connected to .socket2.sock');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (final sink in _eventSinks) {
      sink.add(utf8.encode(line));
    }
  }

  Future<void> dispose() async {
    for (final client in _openClients) {
      try {
        await client.close();
      } on Object {
        // Already gone.
      }
    }
    for (final sink in _eventSinks.toList()) {
      try {
        await sink.close();
      } on Object {
        // Already gone.
      }
    }
    await _requests?.close();
    await _events?.close();
    if (_ownsDir) {
      await Directory(dir).delete(recursive: true);
    }
  }
}

void main() {
  test(
      'keep-open request connection still completes and marks the '
      'active workspace focused', () async {
    final server = await _FakeHyprlandServer.bind(keepOpen: true);
    try {
      final backend = HyprlandWorkspaces(socketDir: server.dir);
      final expectation = expectLater(
        backend.snapshots,
        emits(const [
          Workspace(id: '1', name: '1'),
          Workspace(id: '2', name: '2', focused: true),
        ]),
      );
      await backend.start().timeout(const Duration(seconds: 5));
      await expectation.timeout(const Duration(seconds: 5));
      await backend.dispose();
    } finally {
      await server.dispose();
    }
  });

  test('close-after-reply connection maps focus the same way', () async {
    final server = await _FakeHyprlandServer.bind(keepOpen: false);
    try {
      final backend = HyprlandWorkspaces(socketDir: server.dir);
      final expectation = expectLater(
        backend.snapshots,
        emits(const [
          Workspace(id: '1', name: '1'),
          Workspace(id: '2', name: '2', focused: true),
        ]),
      );
      await backend.start().timeout(const Duration(seconds: 5));
      await expectation.timeout(const Duration(seconds: 5));
      await backend.dispose();
    } finally {
      await server.dispose();
    }
  });

  test('urgency resolves through the clients join', () async {
    final server = await _FakeHyprlandServer.bind(keepOpen: false);
    server.replies['j/clients'] = utf8.encode(_clientsUrgentReply);
    try {
      final backend = HyprlandWorkspaces(socketDir: server.dir);
      final expectation = expectLater(
        backend.snapshots,
        emits(const [
          Workspace(id: '1', name: '1', urgent: true),
          Workspace(id: '2', name: '2', focused: true),
        ]),
      );
      await backend.start().timeout(const Duration(seconds: 5));
      await expectation.timeout(const Duration(seconds: 5));
      await backend.dispose();
    } finally {
      await server.dispose();
    }
  });

  test('socket2 urgent event triggers a refresh with new urgency', () async {
    final server = await _FakeHyprlandServer.bind(
      keepOpen: false,
      withEvents: true,
    );
    try {
      final backend = HyprlandWorkspaces(socketDir: server.dir);
      final seen = <List<Workspace>>[];
      final sub = backend.snapshots.listen((workspaces) {
        seen.add(workspaces);
        if (seen.length == 1) {
          server.replies['j/clients'] = utf8.encode(_clientsUrgentReply);
          unawaited(server.fireEvent('urgent>>0x1\n'));
        }
      });
      await backend.start().timeout(const Duration(seconds: 5));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (seen.length < 2) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for the urgent refresh');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await sub.cancel();
      await backend.dispose();
      expect(seen[0][0].urgent, isFalse);
      expect(seen[1][0].urgent, isTrue);
      expect(seen[1][1].focused, isTrue);
    } finally {
      await server.dispose();
    }
  });

  test('bloc receives the initial refresh through the monitor', () async {
    // Guards the subscribe-before-start ordering: the bloc subscribes to
    // monitor snapshots before starting it, so a backend created lazily
    // in start() would leave it listening to an empty stream forever.
    final server = await _FakeHyprlandServer.bind(keepOpen: true);
    try {
      final monitor = WorkspaceMonitor(
        backend: HyprlandWorkspaces(socketDir: server.dir),
      );
      final bloc = WorkspacesBloc(monitor: monitor);
      final expectation = expectLater(
        bloc.stream,
        emits(const WorkspacesState([
          Workspace(id: '1', name: '1'),
          Workspace(id: '2', name: '2', focused: true),
        ])),
      );
      bloc.add(const WorkspacesStarted());
      await expectation.timeout(const Duration(seconds: 5));
      await bloc.close();
    } finally {
      await server.dispose();
    }
  });

  test('malformed reply keeps the previous snapshot and completes', () async {    final server = await _FakeHyprlandServer.bind(keepOpen: false);
    server.replies['j/workspaces'] = utf8.encode('not json{');
    try {
      final backend = HyprlandWorkspaces(socketDir: server.dir);
      final seen = <List<Workspace>>[];
      final sub = backend.snapshots.listen(seen.add);
      await backend.start().timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();
      await backend.dispose();
      expect(seen, isEmpty);
    } finally {
      await server.dispose();
    }
  });

  test('refused first attempt retries on a fresh connection', () async {
    // The compositor serves IPC on its main loop; a query opened while it
    // is still tearing down the previous connection can be refused. The
    // backend retries once after a short settle delay.
    final dir = await Directory.systemTemp.createTemp('hyprland-retry');
    try {
      final backend = HyprlandWorkspaces(socketDir: dir.path);
      final expectation = expectLater(
        backend.snapshots,
        emits(const [
          Workspace(id: '1', name: '1'),
          Workspace(id: '2', name: '2', focused: true),
        ]),
      );
      final started = backend.start();
      // Bind inside the retry's settle window: the first attempt is
      // refused, the retry finds a listener and completes the refresh.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final server = await _FakeHyprlandServer.bind(dir: dir.path);
      try {
        await started.timeout(const Duration(seconds: 5));
        await expectation.timeout(const Duration(seconds: 5));
      } finally {
        await server.dispose();
      }
      await backend.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('unreachable socket completes silently with no snapshot', () async {
    final dir = await Directory.systemTemp.createTemp('hyprland-retry');
    try {
      final backend = HyprlandWorkspaces(socketDir: dir.path);
      final seen = <List<Workspace>>[];
      final sub = backend.snapshots.listen(seen.add);
      // No listener ever appears: both attempts are refused, the refresh
      // keeps the previous (empty) snapshot instead of hanging.
      await backend.start().timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();
      await backend.dispose();
      expect(seen, isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
