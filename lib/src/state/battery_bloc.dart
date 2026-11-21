import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/battery.dart';

sealed class BatteryEvent extends Equatable {
  const BatteryEvent();

  @override
  List<Object?> get props => [];
}

class BatteryStarted extends BatteryEvent {
  const BatteryStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class BatteryPaused extends BatteryEvent {
  const BatteryPaused();
}

class BatteryResumed extends BatteryEvent {
  const BatteryResumed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle or sample
/// events are ignored, and `close()` remains safe without disposing twice.
class BatteryStopped extends BatteryEvent {
  const BatteryStopped();
}

class BatterySampled extends BatteryEvent {
  const BatterySampled(this.status);

  final BatteryStatus status;

  @override
  List<Object?> get props => [status];
}

class BatteryBloc extends Bloc<BatteryEvent, BatteryStatus> {
  BatteryBloc({
    BatterySampler? sampler,
    BatteryStatus initial = const BatteryStatus(),
  }) : _sampler = sampler ?? BatterySampler(),
       super(initial) {
    on<BatteryStarted>(_onStarted);
    on<BatteryPaused>(_onPaused);
    on<BatteryResumed>(_onResumed);
    on<BatteryStopped>(_onStopped);
    on<BatterySampled>((event, emit) {
      if (!_stopped) {
        emit(event.status);
      }
    });
  }

  final BatterySampler _sampler;
  StreamSubscription<BatteryStatus>? _subscription;
  var _stopped = false;

  void _onStarted(BatteryStarted event, Emitter<BatteryStatus> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (status) => add(BatterySampled(status)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(BatteryPaused event, Emitter<BatteryStatus> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(BatteryResumed event, Emitter<BatteryStatus> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  Future<void> _onStopped(
    BatteryStopped event,
    Emitter<BatteryStatus> emit,
  ) async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    _sampler.dispose();
  }

  @override
  Future<void> close() async {
    final wasStopped = _stopped;
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    if (!wasStopped) {
      _sampler.dispose();
    }
    return super.close();
  }
}
