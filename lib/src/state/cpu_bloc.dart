import 'dart:async';

import 'package:bloc/bloc.dart';

import '../services/cpu.dart';

sealed class CpuEvent {
  const CpuEvent();
}

class CpuStarted extends CpuEvent {
  const CpuStarted();
}

class CpuStopped extends CpuEvent {
  const CpuStopped();
}

class CpuSampled extends CpuEvent {
  const CpuSampled(this.sample);

  final CpuSample sample;
}

class CpuBloc extends Bloc<CpuEvent, CpuSample> {
  CpuBloc({CpuSampler? sampler})
    : _sampler = sampler ?? CpuSampler(),
      super(const CpuSample(null)) {
    on<CpuStarted>(_onStarted);
    on<CpuStopped>(_onStopped);
    on<CpuSampled>((event, emit) => emit(event.sample));
  }

  final CpuSampler _sampler;
  StreamSubscription<CpuSample>? _subscription;

  void _onStarted(CpuStarted event, Emitter<CpuSample> emit) {
    _subscription ??= _sampler.snapshots.listen(
      (sample) => add(CpuSampled(sample)),
    );
    _sampler.start();
  }

  Future<void> _onStopped(CpuStopped event, Emitter<CpuSample> emit) async {
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
