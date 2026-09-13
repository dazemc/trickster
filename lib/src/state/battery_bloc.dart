import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../services/battery.dart';

sealed class BatteryEvent extends Equatable {
  const BatteryEvent();

  @override
  List<Object?> get props => [];
}

class BatteryStarted extends BatteryEvent {
  const BatteryStarted();
}

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
    on<BatteryStopped>(_onStopped);
    on<BatterySampled>((event, emit) => emit(event.status));
  }

  final BatterySampler _sampler;
  StreamSubscription<BatteryStatus>? _subscription;

  void _onStarted(BatteryStarted event, Emitter<BatteryStatus> emit) {
    _subscription ??= _sampler.snapshots.listen(
      (status) => add(BatterySampled(status)),
    );
    _sampler.start();
  }

  Future<void> _onStopped(
    BatteryStopped event,
    Emitter<BatteryStatus> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = null;
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _sampler.dispose();
    return super.close();
  }
}
