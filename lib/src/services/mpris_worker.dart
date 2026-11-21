import 'dart:async';
import 'dart:isolate';

import 'package:trickster/src/services/mpris.dart';

/// Commands accepted by the MPRIS worker isolate.
enum MediaPlayerWorkerOperation {
  start,
  pauseRecovery,
  resumeRecovery,
  playPause,
  next,
  previous,
  dispose,
}

/// UI-side handle to one spawned MPRIS worker.
///
/// Tests replace this with a fake command/event channel; production uses
/// [spawnMediaPlayerWorker], which owns a real isolate, its command port, and
/// its error/exit ports.
class MediaPlayerWorkerConnection {
  MediaPlayerWorkerConnection({
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

/// Spawns the MPRIS worker and returns its typed UI-side handle.
Future<MediaPlayerWorkerConnection> spawnMediaPlayerWorker() async {
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
        StateError('MPRIS worker returned an invalid command port'),
      );
    }
  });

  Isolate? isolate;
  try {
    isolate = await Isolate.spawn<List<SendPort>>(
      mediaPlayerWorkerMain,
      <SendPort>[ready.sendPort, events.sendPort],
      debugName: 'trickster-mpris-worker',
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

  return MediaPlayerWorkerConnection(
    commands: commands.future,
    events: events.cast<Object?>(),
    errors: errors.cast<Object?>(),
    exits: exits.cast<Object?>(),
    kill: () => isolate?.kill(priority: Isolate.immediate),
    close: () {
      if (!commands.isCompleted) {
        commands.completeError(StateError('MPRIS worker was closed'));
      }
      unawaited(readySubscription.cancel());
      ready.close();
      events.close();
      errors.close();
      exits.close();
    },
  );
}

/// Entry point for the widget-free MPRIS worker.
///
/// The worker owns the only [MediaPlayerService] and therefore the only
/// DBusClient for MPRIS. States cross the isolate boundary as
/// [MprisPlaybackState.toJson] maps; no D-Bus object, snapshot subscription,
/// or client leaves this isolate.
@pragma('vm:entry-point')
void mediaPlayerWorkerMain(List<SendPort> bootstrap) {
  if (bootstrap.length != 2) {
    throw ArgumentError.value(bootstrap, 'bootstrap');
  }
  final ready = bootstrap[0];
  final events = bootstrap[1];
  final commands = ReceivePort();
  MediaPlayerService? service;
  StreamSubscription<MprisPlaybackState>? snapshots;
  var disposed = false;

  void publish(MprisPlaybackState state) {
    events.send(<Object?>['state', state.toJson()]);
  }

  Future<void> handle(List<Object?> message) async {
    if (message.length != 3 || message[0] is! int || message[1] is! int) {
      return;
    }
    final requestId = message[0]! as int;
    final index = message[1]! as int;
    if (index < 0 || index >= MediaPlayerWorkerOperation.values.length) {
      events.send(<Object?>[
        requestId,
        false,
        'Unknown MPRIS worker operation $index',
      ]);
      return;
    }
    final operation = MediaPlayerWorkerOperation.values[index];
    try {
      switch (operation) {
        case MediaPlayerWorkerOperation.start:
          service ??= MediaPlayerService();
          snapshots ??= service!.snapshots.listen(
            publish,
            onError: (Object error) =>
                events.send(<Object?>['error', '$error']),
          );
          final paused =
              message[2] is Map && (message[2]! as Map)['paused'] == true;
          await service!.start(paused: paused);
          publish(service!.current);
        case MediaPlayerWorkerOperation.pauseRecovery:
          service?.pauseRecovery();
        case MediaPlayerWorkerOperation.resumeRecovery:
          await service?.resumeRecovery();
        case MediaPlayerWorkerOperation.playPause:
          await service?.playPause();
        case MediaPlayerWorkerOperation.next:
          await service?.next();
        case MediaPlayerWorkerOperation.previous:
          await service?.previous();
        case MediaPlayerWorkerOperation.dispose:
          disposed = true;
          await snapshots?.cancel();
          snapshots = null;
          await service?.dispose();
          service = null;
          events.send(<Object?>[requestId, true, null]);
          commands.close();
          return;
      }
      if (!disposed) {
        events.send(<Object?>[requestId, true, null]);
      }
    } on Object catch (error, stackTrace) {
      events.send(<Object?>[requestId, false, '$error', '$stackTrace']);
    }
  }

  var tail = Future<void>.value();
  commands.listen((message) {
    if (message is! List<Object?>) {
      return;
    }
    tail = tail.then((_) => handle(message));
  });
  ready.send(commands.sendPort);
}
