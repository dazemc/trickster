import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/brightness.dart';

sealed class BrightnessEvent extends Equatable {
  const BrightnessEvent();

  @override
  List<Object?> get props => [];
}

class BrightnessStarted extends BrightnessEvent {
  const BrightnessStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class BrightnessPaused extends BrightnessEvent {
  const BrightnessPaused();
}

class BrightnessResumed extends BrightnessEvent {
  const BrightnessResumed();
}

/// Re-probes sysfs after a settings reload.
class BrightnessRefreshed extends BrightnessEvent {
  const BrightnessRefreshed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle or sample
/// events are ignored, and `close()` remains safe without disposing twice.
class BrightnessStopped extends BrightnessEvent {
  const BrightnessStopped();
}

class BrightnessSampled extends BrightnessEvent {
  const BrightnessSampled(this.sample);

  final BrightnessSample sample;

  @override
  List<Object?> get props => [sample];
}

class BrightnessBloc extends Bloc<BrightnessEvent, BrightnessSample> {
  BrightnessBloc({
    BrightnessSampler? sampler,
    BrightnessSample initial = const BrightnessSample(),
  }) : _sampler = sampler ?? BrightnessSampler(),
       super(initial) {
    on<BrightnessStarted>(_onStarted);
    on<BrightnessPaused>(_onPaused);
    on<BrightnessResumed>(_onResumed);
    on<BrightnessRefreshed>(_onRefreshed);
    on<BrightnessStopped>(_onStopped);
    on<BrightnessSampled>((event, emit) {
      if (!_stopped) {
        emit(event.sample);
      }
    });
  }

  final BrightnessSampler _sampler;
  StreamSubscription<BrightnessSample>? _subscription;
  var _stopped = false;

  void _onStarted(BrightnessStarted event, Emitter<BrightnessSample> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (sample) => add(BrightnessSampled(sample)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(BrightnessPaused event, Emitter<BrightnessSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(BrightnessResumed event, Emitter<BrightnessSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  void _onRefreshed(BrightnessRefreshed event, Emitter<BrightnessSample> emit) {
    if (_stopped) {
      return;
    }
    _sampler.refresh();
  }

  Future<void> _onStopped(
    BrightnessStopped event,
    Emitter<BrightnessSample> emit,
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
