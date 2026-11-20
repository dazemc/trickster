import 'dart:async';
import 'dart:io' show stderr;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/platform/layer_shell.dart';

/// The seat's idle state as reported by `ext-idle-notify-v1`.
class SeatIdleState extends Equatable {
  const SeatIdleState({this.idle = false});

  final bool idle;

  @override
  List<Object?> get props => [idle];

  Map<String, Object?> toJson() => {'idle': idle};

  static SeatIdleState fromJson(Map<String, dynamic> json) =>
      SeatIdleState(idle: json['idle'] as bool? ?? false);
}

sealed class SeatIdleEvent extends Equatable {
  const SeatIdleEvent();

  @override
  List<Object?> get props => [];
}

/// Reconcile with native's last-known state once at startup. The event stream
/// is broadcast, so an idle transition that happened before Dart subscribed
/// is otherwise lost.
class SeatIdleProbeRequested extends SeatIdleEvent {
  const SeatIdleProbeRequested();
}

class SeatIdleChanged extends SeatIdleEvent {
  const SeatIdleChanged(this.idle);

  final bool idle;

  @override
  List<Object?> get props => [idle];
}

/// Watches the compositor's seat idle notifications for the whole process.
///
/// This is a shared service, not a module: it owns no timer and only exists
/// when something below reads it. CPU/GPU sampling is the only consumer in
/// this step; disabled modules still create no blocs, timers, or sampler
/// subscriptions.
class SeatIdleBloc extends Bloc<SeatIdleEvent, SeatIdleState> {
  SeatIdleBloc({
    Future<bool> Function()? probe,
    Stream<bool> Function()? changes,
    SeatIdleState? initial,
    void Function(String message)? log,
  }) : _probe = probe ?? _nativeProbe,
       _log = log ?? stderr.writeln,
       super(initial ?? const SeatIdleState()) {
    on<SeatIdleProbeRequested>(_onProbeRequested);
    on<SeatIdleChanged>(_onChanged);
    _subscription = (changes ?? _nativeChanges)().listen(
      (idle) => add(SeatIdleChanged(idle)),
    );
  }

  final Future<bool> Function() _probe;
  final void Function(String message) _log;
  StreamSubscription<bool>? _subscription;
  var _heardEvent = false;

  static Future<bool> _nativeProbe() => LayerShell().seatIdle();
  static Stream<bool> _nativeChanges() => LayerShell.seatIdleChanges;

  Future<void> _onProbeRequested(
    SeatIdleProbeRequested event,
    Emitter<SeatIdleState> emit,
  ) async {
    if (_heardEvent) {
      return;
    }
    bool idle;
    try {
      idle = await _probe();
    } on Object {
      idle = false;
    }
    // A native event that arrived while the probe was in flight is newer.
    if (isClosed || _heardEvent || idle == state.idle) {
      return;
    }
    emit(SeatIdleState(idle: idle));
    _log(idle ? 'trickster: seat idle' : 'trickster: seat resumed');
  }

  void _onChanged(SeatIdleChanged event, Emitter<SeatIdleState> emit) {
    _heardEvent = true;
    if (event.idle == state.idle) {
      return;
    }
    emit(SeatIdleState(idle: event.idle));
    _log(event.idle ? 'trickster: seat idle' : 'trickster: seat resumed');
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    return super.close();
  }
}
