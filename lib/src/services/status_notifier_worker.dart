import 'dart:async';
import 'dart:isolate';

import 'package:dbus/dbus.dart';

import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/services/status_notifier_protocol.dart';

/// UI-side handle to one spawned StatusNotifier worker.
class StatusNotifierWorkerConnection {
  StatusNotifierWorkerConnection({
    required this.commands,
    required this.events,
    required this.errors,
    required this.exits,
    required this.kill,
    required this.close,
  });

  final Future<SendPort> commands;
  final Stream<Object?> events;
  final Stream<Object?> errors;
  final Stream<Object?> exits;
  final void Function() kill;
  final void Function() close;
}

/// Spawns the StatusNotifier worker and returns its typed UI-side handle.
Future<StatusNotifierWorkerConnection> spawnStatusNotifierWorker() async {
  final ready = ReceivePort();
  final events = ReceivePort();
  final errors = ReceivePort();
  final exits = ReceivePort();
  final commands = Completer<SendPort>();
  final readySubscription = ready.listen((message) {
    if (commands.isCompleted) {
      return;
    }
    if (message is SendPort) {
      commands.complete(message);
    } else {
      commands.completeError(
        StateError('StatusNotifier worker returned an invalid command port'),
      );
    }
  });

  Isolate? isolate;
  try {
    isolate = await Isolate.spawn<List<SendPort>>(
      statusNotifierWorkerMain,
      <SendPort>[ready.sendPort, events.sendPort],
      debugName: 'trickster-sni-worker',
      errorsAreFatal: true,
      onError: errors.sendPort,
      onExit: exits.sendPort,
    );
  } on Object {
    await readySubscription.cancel();
    ready.close();
    events.close();
    errors.close();
    exits.close();
    rethrow;
  }

  return StatusNotifierWorkerConnection(
    commands: commands.future,
    events: events.cast<Object?>(),
    errors: errors.cast<Object?>(),
    exits: exits.cast<Object?>(),
    kill: () => isolate?.kill(priority: Isolate.immediate),
    close: () {
      if (!commands.isCompleted) {
        commands.completeError(StateError('StatusNotifier worker was closed'));
      }
      unawaited(readySubscription.cancel());
      ready.close();
      events.close();
      errors.close();
      exits.close();
    },
  );
}

/// Entry point for the widget-free StatusNotifier worker.
///
/// The worker owns the only [StatusNotifierService] and therefore the only
/// DBusClient, watcher endpoint, signal subscriptions, and menu parser. Only
/// bounded [StatusNotifierSnapshot], menu, command, and reply payloads cross
/// the isolate boundary.
@pragma('vm:entry-point')
void statusNotifierWorkerMain(List<SendPort> bootstrap) {
  if (bootstrap.length != 2) {
    throw ArgumentError.value(bootstrap, 'bootstrap');
  }
  final ready = bootstrap[0];
  final events = bootstrap[1];
  final commands = ReceivePort();
  final host = _StatusNotifierWorkerHost(events);

  var tail = Future<void>.value();
  commands.listen((message) {
    tail = tail.then((_) async {
      if (host.disposed) {
        return;
      }
      StatusNotifierCommand? command;
      try {
        command = StatusNotifierCommand.decode(message);
        final result = await host.handle(command);
        events.send(
          StatusNotifierReply(
            requestId: command.requestId,
            ok: true,
            result: result,
          ).toMessage(),
        );
        if (command.operation == StatusNotifierWorkerOperation.dispose) {
          commands.close();
        }
      } on Object catch (error, stackTrace) {
        final requestId = command?.requestId ?? _requestIdFrom(message);
        if (requestId == null) {
          events.send(StatusNotifierErrorEvent(_bounded('$error')).toMessage());
          return;
        }
        events.send(
          StatusNotifierReply(
            requestId: requestId,
            ok: false,
            error: _bounded('$error'),
            stack: _bounded('$stackTrace'),
          ).toMessage(),
        );
      }
    });
  });
  ready.send(commands.sendPort);
}

int? _requestIdFrom(Object? message) {
  if (message is List && message.isNotEmpty && message.first is int) {
    return message.first! as int;
  }
  return null;
}

String _bounded(String value) {
  return value.length <= StatusNotifierProtocolLimits.maxString
      ? value
      : value.substring(0, StatusNotifierProtocolLimits.maxString);
}

class _StatusNotifierWorkerHost {
  _StatusNotifierWorkerHost(this._events);

  final SendPort _events;
  StatusNotifierService? _service;
  StreamSubscription<List<SystemTrayItem>>? _snapshots;
  Map<String, String> _lastIcons = <String, String>{};
  bool disposed = false;

  FutureOr<Object?> handle(StatusNotifierCommand command) {
    return switch (command.operation) {
      StatusNotifierWorkerOperation.start => _start(command.payload),
      StatusNotifierWorkerOperation.invoke => _invoke(command.payload),
      StatusNotifierWorkerOperation.loadMenu => _loadMenu(command.payload),
      StatusNotifierWorkerOperation.activateMenuEntry => _activateMenu(
        command.payload,
      ),
      StatusNotifierWorkerOperation.dispose => _dispose(),
    };
  }

  Future<Object?> _start(Object? payload) async {
    final options = StatusNotifierStartPayload.decode(payload);
    final existing = _service;
    if (existing != null) {
      _publish(existing.current);
      return _startResult().toJson();
    }
    final service = StatusNotifierService(
      clientFactory: options.address == null
          ? null
          : () => DBusClient(DBusAddress(options.address!)),
      iconFileDecoder: null,
      heartbeatInterval:
          options.heartbeatInterval ?? const Duration(seconds: 60),
      recoveryBackoff:
          options.recoveryBackoff ??
          const <Duration>[
            Duration(seconds: 1),
            Duration(seconds: 2),
            Duration(seconds: 5),
            Duration(seconds: 10),
            Duration(seconds: 30),
          ],
    );
    _service = service;
    _snapshots = service.snapshots.listen(
      _publish,
      onError: (Object error) => _events.send(
        StatusNotifierErrorEvent(_bounded('$error')).toMessage(),
      ),
    );
    try {
      await service.start();
    } on Object catch (error) {
      // The service scheduled its own recovery; the worker stays alive.
      _events.send(StatusNotifierErrorEvent(_bounded('$error')).toMessage());
    }
    _publish(service.current);
    return _startResult().toJson();
  }

  StatusNotifierStartResult _startResult() => StatusNotifierStartResult(
    isolateName: Isolate.current.debugName ?? '',
    protocolVersion: StatusNotifierProtocolLimits.protocolVersion,
  );

  Future<bool> _invoke(Object? payload) async {
    final request = StatusNotifierInvokePayload.decode(payload);
    final service = _requireService();
    return service.invokeAt(
      request.itemId,
      request.action,
      request.dx.round(),
      request.dy.round(),
    );
  }

  Future<Object?> _loadMenu(Object? payload) async {
    final request = StatusNotifierItemIdPayload.decode(payload);
    final service = _requireService();
    final item = service.itemForId(request.itemId);
    if (item == null) {
      return null;
    }
    final entries = await service.loadMenu(item);
    return entries == null ? null : encodeStatusNotifierMenuEntries(entries);
  }

  Future<bool> _activateMenu(Object? payload) async {
    final request = StatusNotifierActivateMenuPayload.decode(payload);
    final service = _requireService();
    final item = service.itemForId(request.itemId);
    if (item == null) {
      return false;
    }
    return service.activateMenuEntry(item, request.entryId);
  }

  Future<Object?> _dispose() async {
    disposed = true;
    await _snapshots?.cancel();
    _snapshots = null;
    final service = _service;
    _service = null;
    await service?.dispose();
    return null;
  }

  StatusNotifierService _requireService() {
    return _service ??
        (throw StateError('StatusNotifier worker has not been started'));
  }

  void _publish(List<SystemTrayItem> items) {
    if (disposed) {
      return;
    }
    final service = _service;
    if (service == null) {
      return;
    }
    final nextIcons = <String, String>{};
    final encoded = <StatusNotifierSnapshotItem>[];
    for (final item in items) {
      final (signature, icon) = _iconFor(service, item);
      nextIcons[item.id] = signature;
      encoded.add(
        StatusNotifierSnapshotItem(
          id: item.id,
          title: item.title,
          status: item.status,
          iconName: item.iconName,
          iconThemePath: item.iconThemePath,
          icon: icon,
          menuAvailable: item.menuAvailable,
          primaryOpensMenu: item.primaryOpensMenu,
          menuPath: item.menuPath,
        ),
      );
    }
    _lastIcons = nextIcons;
    _events.send(StatusNotifierSnapshot(encoded).toMessage());
  }

  (String, StatusNotifierIcon) _iconFor(
    StatusNotifierService service,
    SystemTrayItem item,
  ) {
    final pixmap = item.iconPixmap;
    if (pixmap != null) {
      final signature =
          'rgba:${pixmap.digest}:${pixmap.width}x${pixmap.height}';
      if (_lastIcons[item.id] == signature) {
        return (signature, StatusNotifierIcon.unchanged());
      }
      return (
        signature,
        StatusNotifierIcon.rgba(
          width: pixmap.width,
          height: pixmap.height,
          digest: pixmap.digest,
          rgba: pixmap.rgba,
        ),
      );
    }
    final path = service.resolvedIconPathFor(item.id);
    if (path != null &&
        path.isNotEmpty &&
        path.length <= StatusNotifierProtocolLimits.maxIconPath) {
      final signature = 'file:$path';
      if (_lastIcons[item.id] == signature) {
        return (signature, StatusNotifierIcon.unchanged());
      }
      return (signature, StatusNotifierIcon.file(path));
    }
    return ('', StatusNotifierIcon.none());
  }
}
