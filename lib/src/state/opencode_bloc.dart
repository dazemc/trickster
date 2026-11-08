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
  const OpencodeStarted();
}

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
    on<OpencodeStopped>(_onStopped);
    on<OpencodeSampled>((event, emit) => emit(event.usage));
    on<OpencodeRefreshed>((event, emit) => _sampler.refresh());
  }

  final OpencodeSampler _sampler;
  StreamSubscription<OpencodeUsage>? _subscription;

  void _onStarted(OpencodeStarted event, Emitter<OpencodeUsage> emit) {
    _subscription ??= _sampler.snapshots.listen(
      (usage) => add(OpencodeSampled(usage)),
    );
    _sampler.start();
  }

  Future<void> _onStopped(
    OpencodeStopped event,
    Emitter<OpencodeUsage> emit,
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
