import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/opencode.dart';

sealed class OpencodeEvent extends Equatable {
  const OpencodeEvent();

  @override
  List<Object?> get props => [];
}

class OpencodeStarted extends OpencodeEvent {
  const OpencodeStarted({this.paused = false});

  /// True when the module is created while the seat is already idle.
  final bool paused;

  @override
  List<Object?> get props => [paused];
}

class OpencodePaused extends OpencodeEvent {
  const OpencodePaused();
}

class OpencodeResumed extends OpencodeEvent {
  const OpencodeResumed();
}

/// Terminal for this bloc: the sampler is disposed, later lifecycle, sample,
/// and refresh events are ignored, and `close()` remains safe without
/// disposing twice.
class OpencodeStopped extends OpencodeEvent {
  const OpencodeStopped();
}

class OpencodeSampled extends OpencodeEvent {
  const OpencodeSampled(this.usage);

  final OpencodeUsage usage;

  @override
  List<Object?> get props => [usage];
}

class OpencodeRefreshed extends OpencodeEvent {
  const OpencodeRefreshed();
}

class OpencodeBloc extends Bloc<OpencodeEvent, OpencodeUsage> {
  OpencodeBloc({
    OpencodeSampler? sampler,
    OpencodeUsage initial = const OpencodeUsage(),
  }) : _sampler = sampler ?? OpencodeSampler(),
       super(initial) {
    on<OpencodeStarted>(_onStarted);
    on<OpencodePaused>(_onPaused);
    on<OpencodeResumed>(_onResumed);
    on<OpencodeStopped>(_onStopped);
    on<OpencodeSampled>((event, emit) {
      if (!_stopped) {
        emit(event.usage);
      }
    });
    on<OpencodeRefreshed>((event, emit) {
      if (!_stopped) {
        _sampler.refresh();
      }
    });
  }

  final OpencodeSampler _sampler;
  StreamSubscription<OpencodeUsage>? _subscription;
  var _stopped = false;

  void _onStarted(OpencodeStarted event, Emitter<OpencodeUsage> emit) {
    if (_stopped) {
      return;
    }
    _subscription ??= _sampler.snapshots.listen(
      (usage) => add(OpencodeSampled(usage)),
    );
    _sampler.start(paused: event.paused);
  }

  void _onPaused(OpencodePaused event, Emitter<OpencodeUsage> emit) {
    if (_stopped) {
      return;
    }
    _sampler.pause();
  }

  void _onResumed(OpencodeResumed event, Emitter<OpencodeUsage> emit) {
    if (_stopped) {
      return;
    }
    _sampler.resume();
  }

  Future<void> _onStopped(
    OpencodeStopped event,
    Emitter<OpencodeUsage> emit,
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
