import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// The selected keyboard's active layout, as reported by the compositor.
class KeyboardLayoutState extends Equatable {
  const KeyboardLayoutState({
    this.available = false,
    this.backend,
    this.active,
    this.index,
    this.names = const [],
  });

  final bool available;
  final String? backend;

  /// Short active layout token, uppercase (`US`, `RU`), or null.
  final String? active;

  /// Index into [names] reported by the compositor.
  final int? index;

  /// Layout tokens in compositor order (`['us', 'ru']`).
  final List<String> names;

  bool get hasLayout => available && active != null && active!.isNotEmpty;

  @override
  List<Object?> get props => [available, backend, active, index, names];

  Map<String, Object?> toJson() => {
    'available': available,
    'backend': backend,
    'active': active,
    'index': index,
    'names': names,
  };

  static KeyboardLayoutState fromJson(Map<String, dynamic> json) =>
      KeyboardLayoutState(
        available: json['available'] == true,
        backend: json['backend'] as String?,
        active: json['active'] as String?,
        index: (json['index'] as num?)?.toInt(),
        names: [
          for (final name in json['names'] as List<dynamic>? ?? const [])
            '$name',
        ],
      );
}

/// Parses the `j/devices` document. The main keyboard wins; when none is
/// marked main, the first keyboard in compositor order is used. Other
/// keyboards are ignored: their layouts can differ, and the bar has one
/// global keyboard-layout pill.
@visibleForTesting
KeyboardLayoutState? parseHyprlandDevices(Object? json) {
  if (json is! Map<String, dynamic>) {
    return null;
  }
  final keyboards = json['keyboards'];
  if (keyboards is! List || keyboards.isEmpty) {
    return const KeyboardLayoutState(backend: 'hyprland');
  }
  Map<String, dynamic>? selected;
  for (final keyboard in keyboards) {
    if (keyboard is Map<String, dynamic> && keyboard['main'] == true) {
      selected = keyboard;
      break;
    }
  }
  selected ??= keyboards.whereType<Map<String, dynamic>>().firstOrNull;
  if (selected == null) {
    return const KeyboardLayoutState(backend: 'hyprland');
  }
  final layout = selected['layout'];
  final names = layout is String
      ? [
          for (final name in layout.split(','))
            if (name.trim().isNotEmpty) name.trim(),
        ]
      : const <String>[];
  final rawIndex = selected['active_layout_index'];
  final index = rawIndex is num ? rawIndex.toInt() : (names.isEmpty ? null : 0);
  final active = index != null && index >= 0 && index < names.length
      ? names[index].toUpperCase()
      : (names.isEmpty ? null : names.first.toUpperCase());
  return KeyboardLayoutState(
    available: true,
    backend: 'hyprland',
    active: active,
    index: index,
    names: names,
  );
}

/// One keyboard-layout backend; the Hyprland implementation is the only one
/// wired for now.
abstract interface class KeyboardLayoutBackend {
  Stream<KeyboardLayoutState> get snapshots;

  Future<void> start();

  Future<void> dispose();
}

/// Hyprland keyboard layout over `.socket.sock` (`j/devices`) and
/// `.socket2.sock` (`activelayout` events).
///
/// The initial state is queried once; layout changes are event-driven and
/// coalesced into one re-query. There is no polling and no idle pause. A dead
/// event socket reconnects with capped exponential backoff.
class HyprlandKeyboardLayout implements KeyboardLayoutBackend {
  HyprlandKeyboardLayout({String? socketDir})
    : _socketDir = socketDir ?? _dirFromEnvironment;

  static String? get _dirFromEnvironment {
    final signature = Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'];
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (signature == null || runtime == null) {
      return null;
    }
    return '$runtime/hypr/$signature';
  }

  static const _maxReplyBytes = 1 << 20;
  static const _replyTimeout = Duration(seconds: 5);
  static const _reconnectDelayBase = Duration(milliseconds: 500);
  static const _reconnectDelayMax = Duration(seconds: 5);
  static const _eventDebounce = Duration(milliseconds: 32);

  final String? _socketDir;
  Socket? _events;
  Timer? _reconnect;
  Timer? _refreshDebounce;
  Duration _reconnectDelay = _reconnectDelayBase;
  var _generation = 0;
  var _refreshing = false;
  var _refreshAgain = false;
  var _running = false;
  var _disposed = false;
  KeyboardLayoutState? _last;
  final _controller = StreamController<KeyboardLayoutState>.broadcast();

  @override
  Stream<KeyboardLayoutState> get snapshots => _controller.stream;

  @visibleForTesting
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running || _disposed) {
      return;
    }
    _running = true;
    await _refresh();
    if (_running && !_disposed) {
      _connectEvents();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    _generation += 1;
    _reconnect?.cancel();
    _reconnect = null;
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    final events = _events;
    _events = null;
    await events?.close();
    await _controller.close();
  }

  void _connectEvents() {
    final dir = _socketDir;
    if (dir == null) {
      return;
    }
    final generation = _generation;
    unawaited(_dialEvents(dir, generation));
  }

  Future<void> _dialEvents(String dir, int generation) async {
    Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress('$dir/.socket2.sock', type: InternetAddressType.unix),
        0,
      );
    } on Object {
      _scheduleReconnect(generation);
      return;
    }
    if (generation != _generation || _disposed || !_running) {
      await socket.close();
      return;
    }
    _events = socket;
    _reconnectDelay = _reconnectDelayBase;
    unawaited(_refresh());
    final buffer = StringBuffer();
    socket.listen(
      (data) {
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
      },
      onError: (_) {},
      onDone: () => _scheduleReconnect(generation),
    );
  }

  void _scheduleReconnect(int generation) {
    if (_disposed || !_running || generation != _generation) {
      return;
    }
    _generation += 1;
    _events = null;
    _reconnect?.cancel();
    _reconnect = Timer(_reconnectDelay, () {
      _reconnect = null;
      if (!_disposed && _running) {
        _connectEvents();
      }
    });
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectDelayMax ? _reconnectDelayMax : next;
  }

  void _handleEvent(String line) {
    if (!line.startsWith('activelayout>>')) {
      return;
    }
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_eventDebounce, () {
      _refreshDebounce = null;
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        await _refreshOnce();
      } while (_refreshAgain);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOnce() async {
    final dir = _socketDir;
    if (dir == null) {
      _emit(const KeyboardLayoutState(backend: 'hyprland'));
      return;
    }
    final state = await Isolate.run(() => _queryDevices(dir));
    if (!_running || _disposed || _controller.isClosed) {
      return;
    }
    if (state == null) {
      if (_last == null) {
        _emit(const KeyboardLayoutState(backend: 'hyprland'));
      }
      return;
    }
    _emit(state);
  }

  void _emit(KeyboardLayoutState state) {
    if (_last == state || _controller.isClosed) {
      return;
    }
    _last = state;
    _controller.add(state);
  }
}

Future<KeyboardLayoutState?> _queryDevices(String dir) async {
  Socket? socket;
  StreamSubscription<List<int>>? subscription;
  try {
    socket = await Socket.connect(
      InternetAddress('$dir/.socket.sock', type: InternetAddressType.unix),
      0,
    );
    final buffer = BytesBuilder();
    final done = Completer<KeyboardLayoutState?>();
    subscription = socket.listen(
      (data) {
        buffer.add(data);
        if (buffer.length > HyprlandKeyboardLayout._maxReplyBytes) {
          if (!done.isCompleted) {
            done.complete(null);
          }
          return;
        }
        try {
          final decoded = jsonDecode(utf8.decode(buffer.toBytes()));
          final state = parseHyprlandDevices(decoded);
          if (!done.isCompleted) {
            done.complete(state);
          }
        } on FormatException {
          // A split JSON chunk; wait for more bytes.
        }
      },
      onError: (_) {
        if (!done.isCompleted) {
          done.complete(null);
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete(null);
        }
      },
    );
    socket.add(utf8.encode('j/devices'));
    return await done.future.timeout(
      HyprlandKeyboardLayout._replyTimeout,
      onTimeout: () => null,
    );
  } on Object {
    return null;
  } finally {
    await subscription?.cancel();
    socket?.destroy();
  }
}
