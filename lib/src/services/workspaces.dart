import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class Workspace {
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
}

abstract class WorkspaceBackend {
  Stream<List<Workspace>> get snapshots;
  Future<void> start();
  Future<void> dispose();
}

class WorkspaceMonitor {
  WorkspaceBackend? _backend;

  Stream<List<Workspace>> get snapshots =>
      _backend?.snapshots ?? const Stream.empty();

  Future<void> start() async {
    _backend = _detect();
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
  Socket? _events;
  final _controller = StreamController<List<Workspace>>.broadcast();

  @override
  Stream<List<Workspace>> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    await _refresh();
    final signature = Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'];
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (signature == null || runtime == null) {
      return;
    }
    final path = '$runtime/hypr/$signature/.socket2.sock';
    try {
      _events = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      _events!.listen((data) {
        final text = utf8.decode(data);
        if (text.contains('workspace') || text.contains('focusedmon')) {
          unawaited(_refresh());
        }
      }, onError: (_) {});
    } on Object {
      return;
    }
  }

  Future<void> _refresh() async {
    final signature = Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'];
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (signature == null || runtime == null) {
      return;
    }
    try {
      final socket = await Socket.connect(
        InternetAddress(
          '$runtime/hypr/$signature/.socket.sock',
          type: InternetAddressType.unix,
        ),
        0,
      );
      socket.add(utf8.encode('j/workspaces'));
      final payload = await socket.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      await socket.close();
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! List) {
        return;
      }
      final workspaces = <Workspace>[];
      for (final entry in decoded) {
        if (entry is! Map) {
          continue;
        }
        workspaces.add(
          Workspace(
            id: '${entry['id']}',
            name: '${entry['name'] ?? entry['id']}',
            focused: entry['focused'] == true,
            urgent: entry['urgent'] == true,
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
