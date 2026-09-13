import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class Workspace extends Equatable {
  const Workspace({
    required this.id,
    required this.name,
    this.focused = false,
    this.urgent = false,
  });

  final String id;
  final String name;
  final bool focused;
  final bool urgent;

  @override
  List<Object?> get props => [id, name, focused, urgent];

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'focused': focused,
    'urgent': urgent,
  };

  static Workspace fromJson(Map<String, dynamic> json) => Workspace(
    id: '${json['id']}',
    name: '${json['name']}',
    focused: (json['focused'] as bool?) ?? false,
    urgent: (json['urgent'] as bool?) ?? false,
  );
}

List<Map<String, Object?>> workspacesToJson(List<Workspace> workspaces) =>
    workspaces.map((workspace) => workspace.toJson()).toList(growable: false);

List<Workspace> workspacesFromJson(List<dynamic> json) => json
    .whereType<Map<String, dynamic>>()
    .map(Workspace.fromJson)
    .toList(growable: false);

/// Bloc state for the workspace list. A bare `List` compares by identity,
/// so the wrapper exists to give the bloc value semantics — and a JSON
/// shape for the future `tricksterctl status` dump.
class WorkspacesState extends Equatable {
  const WorkspacesState([this.workspaces = const []]);

  final List<Workspace> workspaces;

  // Spread: Equatable compares props element-wise, so spreading gives deep
  // equality over the list (each Workspace is itself Equatable).
  @override
  List<Object?> get props => [...workspaces];

  Map<String, Object?> toJson() => {
    'workspaces': workspacesToJson(workspaces),
  };

  static WorkspacesState fromJson(Map<String, dynamic> json) =>
      WorkspacesState(
        workspacesFromJson((json['workspaces'] as List?) ?? const []),
      );
}

abstract class WorkspaceBackend {
  Stream<List<Workspace>> get snapshots;
  Future<void> start();
  Future<void> dispose();
}

class WorkspaceMonitor {
  WorkspaceMonitor({WorkspaceBackend? backend})
    : _backend = backend ?? _detect();

  // Detected in the constructor, not in start(): WorkspacesBloc subscribes
  // to snapshots before starting the monitor, and a backend created in
  // start() would leave that subscription attached to an empty stream —
  // the initial refresh (and every later one) unheard.
  WorkspaceBackend? _backend;

  Stream<List<Workspace>> get snapshots =>
      _backend?.snapshots ?? const Stream.empty();

  Future<void> start() async {
    await _backend?.start();
  }

  Future<void> dispose() async {
    await _backend?.dispose();
    _backend = null;
  }

  static WorkspaceBackend? _detect() {
    if (Platform.environment.containsKey('HYPRLAND_INSTANCE_SIGNATURE')) {
      return HyprlandWorkspaces();
    }
    if (Platform.environment.containsKey('SWAYSOCK')) {
      return SwayWorkspaces();
    }
    if (Platform.environment.containsKey('NIRI_SOCKET')) {
      return NiriWorkspaces();
    }
    return null;
  }
}

class HyprlandWorkspaces implements WorkspaceBackend {
  HyprlandWorkspaces({String? socketDir}) : _socketDir = socketDir ?? _dirFromEnvironment;

  static String? get _dirFromEnvironment {
    final signature = Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'];
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (signature == null || runtime == null) {
      return null;
    }
    return '$runtime/hypr/$signature';
  }

  /// Cap on a single `j/*` reply. Replies are ~1 KiB; the cap only bounds a
  /// runaway socket, never real data.
  static const _maxReplyBytes = 1 << 20;

  static const _replyTimeout = Duration(seconds: 5);

  final String? _socketDir;
  Socket? _events;
  final _controller = StreamController<List<Workspace>>.broadcast();

  @override
  Stream<List<Workspace>> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    await _refresh();
    final dir = _socketDir;
    if (dir == null) {
      return;
    }
    try {
      _events = await Socket.connect(
        InternetAddress('$dir/.socket2.sock', type: InternetAddressType.unix),
        0,
      );
      final buffer = StringBuffer();
      _events!.listen((data) {
        // socket2 sends newline-terminated `event>>payload` lines; a chunk
        // boundary can split them, so reassemble before matching.
        buffer.write(utf8.decode(data, allowMalformed: true));
        var text = buffer.toString();
        var newline = text.indexOf('\n');
        while (newline != -1) {
          _handleEvent(text.substring(0, newline));
          text = text.substring(newline + 1);
          newline = text.indexOf('\n');
        }
        buffer
          ..clear()
          ..write(text);
      }, onError: (_) {});
    } on Object {
      return;
    }
  }

  void _handleEvent(String line) {
    if (line.contains('workspace') ||
        line.contains('focusedmon') ||
        line.startsWith('urgent')) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final dir = _socketDir;
    if (dir == null) {
      return;
    }
    try {
      final workspacesJson = await _requestJson('j/workspaces', dir);
      if (workspacesJson is! List) {
        return;
      }
      // `j/workspaces` carries no focused flag — join the active workspace
      // in the same refresh. `j/clients` supplies urgency the same way:
      // no per-workspace urgency exists in the workspace JSON.
      final activeJson = await _requestJson('j/activeworkspace', dir);
      final activeId = activeJson is Map ? '${activeJson['id']}' : null;
      final clientsJson = await _requestJson('j/clients', dir);
      final urgentIds = <String>{};
      if (clientsJson is List) {
        for (final client in clientsJson) {
          if (client is Map && client['urgent'] == true) {
            final workspace = client['workspace'];
            if (workspace is Map && workspace['id'] != null) {
              urgentIds.add('${workspace['id']}');
            }
          }
        }
      }
      final workspaces = <Workspace>[];
      for (final entry in workspacesJson) {
        if (entry is! Map) {
          continue;
        }
        final id = '${entry['id']}';
        workspaces.add(
          Workspace(
            id: id,
            name: '${entry['name'] ?? entry['id']}',
            focused: activeId != null
                ? id == activeId
                : entry['focused'] == true,
            urgent: urgentIds.contains(id),
          ),
        );
      }
      _controller.add(workspaces);
    } on Object {
      return;
    }
  }

  /// One `j/*` query with a bounded read. Some Hyprland versions keep the
  /// request connection open after the reply, so reading until socket-done
  /// hangs forever — instead return as soon as the accumulated bytes parse
  /// as a complete JSON document. The byte cap and timeout bound the
  /// cases where no complete document ever arrives. Returns null when the
  /// query fails, keeping the previous snapshot.
  ///
  /// A transport failure (refused connection, reset mid-write) is retried
  /// once on a fresh connection after a short settle delay: the compositor
  /// serves IPC on its main loop, and a connection opened while it is
  /// still tearing down the previous one can be refused.
  Future<Object?> _requestJson(String command, String dir) async {
    try {
      return await _attemptRequest(command, dir);
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        return await _attemptRequest(command, dir);
      } on Object {
        return null;
      }
    } on Object {
      return null;
    }
  }

  Future<Object?> _attemptRequest(String command, String dir) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress('$dir/.socket.sock', type: InternetAddressType.unix),
        0,
      );
      socket.add(utf8.encode(command));
      final buffer = BytesBuilder();
      await for (final chunk in socket.timeout(_replyTimeout)) {
        buffer.add(chunk);
        if (buffer.length > _maxReplyBytes) {
          return null;
        }
        try {
          return jsonDecode(utf8.decode(buffer.toBytes()));
        } on FormatException {
          continue; // Incomplete document (or split multibyte rune).
        }
      }
      return null; // EOF before a complete document.
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<void> dispose() async {
    await _events?.close();
    _events = null;
    await _controller.close();
  }
}

class SwayWorkspaces implements WorkspaceBackend {
  Socket? _socket;
  final _controller = StreamController<List<Workspace>>.broadcast();

  @override
  Stream<List<Workspace>> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    final path = Platform.environment['SWAYSOCK'];
    if (path == null) {
      return;
    }
    try {
      _socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      await _request(1);
      _socket!.listen((data) {
        unawaited(_request(1));
      }, onError: (_) {});
      await _subscribe();
    } on Object {
      return;
    }
  }

  Future<void> _subscribe() async {
    final payload = utf8.encode('["workspace"]');
    _socket?.add(_frame(2, payload));
  }

  Future<void> _request(int type) async {
    final socket = _socket;
    if (socket == null) {
      return;
    }
    socket.add(_frame(type, Uint8List(0)));
  }

  Uint8List _frame(int type, List<int> payload) {
    final header = Uint8List(14);
    header.setAll(0, utf8.encode('i3-ipc'));
    final view = ByteData.sublistView(header);
    view.setUint32(6, payload.length, Endian.little);
    view.setUint32(10, type, Endian.little);
    return Uint8List.fromList([...header, ...payload]);
  }

  @override
  Future<void> dispose() async {
    await _socket?.close();
    _socket = null;
    await _controller.close();
  }
}

class NiriWorkspaces implements WorkspaceBackend {
  Socket? _socket;
  final _controller = StreamController<List<Workspace>>.broadcast();

  @override
  Stream<List<Workspace>> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    final path = Platform.environment['NIRI_SOCKET'];
    if (path == null) {
      return;
    }
    try {
      _socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      _socket!.add(utf8.encode('${jsonEncode({'EventStream': null})}\n'));
      final buffer = StringBuffer();
      _socket!.listen((data) {
        buffer.write(utf8.decode(data));
        var text = buffer.toString();
        var newline = text.indexOf('\n');
        while (newline != -1) {
          final line = text.substring(0, newline);
          text = text.substring(newline + 1);
          _handle(line);
          newline = text.indexOf('\n');
        }
        buffer
          ..clear()
          ..write(text);
      }, onError: (_) {});
    } on Object {
      return;
    }
  }

  void _handle(String line) {
    if (line.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return;
      }
      final event = decoded['WorkspacesChanged'] ?? decoded['Workspaces'];
      if (event is! Map) {
        return;
      }
      final list = event['workspaces'];
      if (list is! List) {
        return;
      }
      final workspaces = <Workspace>[];
      for (final entry in list) {
        if (entry is! Map) {
          continue;
        }
        workspaces.add(
          Workspace(
            id: '${entry['id'] ?? entry['idx']}',
            name: '${entry['name'] ?? entry['idx'] ?? entry['id']}',
            focused: entry['is_focused'] == true || entry['focused'] == true,
            urgent: entry['is_urgent'] == true,
          ),
        );
      }
      _controller.add(workspaces);
    } on Object {
      return;
    }
  }

  @override
  Future<void> dispose() async {
    await _socket?.close();
    _socket = null;
    await _controller.close();
  }
}
