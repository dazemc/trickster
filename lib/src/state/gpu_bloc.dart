import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/gpu.dart';

sealed class GpuEvent extends Equatable {
  const GpuEvent();

  @override
  List<Object?> get props => [];
}

class GpuStarted extends GpuEvent {
  const GpuStarted();
}

class GpuStopped extends GpuEvent {
  const GpuStopped();
}

class GpuSampled extends GpuEvent {
  const GpuSampled(this.loads);

  final List<GpuLoad> loads;

  @override
  List<Object?> get props => [...loads];
}

class GpuBloc extends Bloc<GpuEvent, GpuState> {
  GpuBloc({GpuSampler? sampler, GpuState initial = const GpuState()})
    : _sampler = sampler ?? GpuSampler(),
      super(initial) {
    on<GpuStarted>(_onStarted);
    on<GpuStopped>(_onStopped);
    on<GpuSampled>((event, emit) => emit(GpuState(event.loads)));
  }

  final GpuSampler _sampler;
  StreamSubscription<List<GpuLoad>>? _subscription;

  void _onStarted(GpuStarted event, Emitter<GpuState> emit) {
    _subscription ??= _sampler.snapshots.listen(
      (loads) => add(GpuSampled(loads)),
    );
    _sampler.start();
  }

  Future<void> _onStopped(GpuStopped event, Emitter<GpuState> emit) async {
    await _subscription?.cancel();
    _subscription = null;
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _sampler.dispose();
    return super.close();
  }
}
