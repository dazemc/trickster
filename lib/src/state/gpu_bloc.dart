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
  const GpuStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class GpuPaused extends GpuEvent {
  const GpuPaused();
}

class GpuResumed extends GpuEvent {
  const GpuResumed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle or sample
/// events are ignored, and `close()` remains safe without disposing twice.
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
  GpuBloc({
    GpuSampler? sampler,
    GpuState initial = const GpuState(),
    bool includeUsage = true,
    bool includeMemory = true,
  }) : _sampler =
           sampler ??
           GpuSampler(includeUsage: includeUsage, includeMemory: includeMemory),
       super(initial) {
    on<GpuStarted>(_onStarted);
    on<GpuPaused>(_onPaused);
    on<GpuResumed>(_onResumed);
    on<GpuStopped>(_onStopped);
    on<GpuSampled>((event, emit) {
      if (!_stopped) {
        emit(GpuState(event.loads));
      }
    });
  }

  final GpuSampler _sampler;
  StreamSubscription<List<GpuLoad>>? _subscription;
  var _stopped = false;

  void _onStarted(GpuStarted event, Emitter<GpuState> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (loads) => add(GpuSampled(loads)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(GpuPaused event, Emitter<GpuState> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(GpuResumed event, Emitter<GpuState> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  Future<void> _onStopped(GpuStopped event, Emitter<GpuState> emit) async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    await _sampler.dispose();
  }

  @override
  Future<void> close() async {
    final wasStopped = _stopped;
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    if (!wasStopped) {
      await _sampler.dispose();
    }
    return super.close();
  }
}
