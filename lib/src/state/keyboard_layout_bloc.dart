import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/keyboard_layout.dart';

sealed class KeyboardLayoutEvent extends Equatable {
  const KeyboardLayoutEvent();

  @override
  List<Object?> get props => [];
}

class KeyboardLayoutStarted extends KeyboardLayoutEvent {
  const KeyboardLayoutStarted();
}

/// Terminal for this bloc: the backend is disposed, later events are ignored,
/// and `close()` remains safe without disposing twice.
class KeyboardLayoutStopped extends KeyboardLayoutEvent {
  const KeyboardLayoutStopped();
}

class KeyboardLayoutChanged extends KeyboardLayoutEvent {
  const KeyboardLayoutChanged(this.state);

  final KeyboardLayoutState state;

  @override
  List<Object?> get props => [state];
}

class KeyboardLayoutBloc
    extends Bloc<KeyboardLayoutEvent, KeyboardLayoutState> {
  KeyboardLayoutBloc({
    KeyboardLayoutBackend? backend,
    KeyboardLayoutState initial = const KeyboardLayoutState(),
  }) : _backend = backend ?? HyprlandKeyboardLayout(),
       super(initial) {
    on<KeyboardLayoutStarted>(_onStarted);
    on<KeyboardLayoutStopped>(_onStopped);
    on<KeyboardLayoutChanged>((event, emit) {
      if (!_stopped) {
        emit(event.state);
      }
    });
  }

  final KeyboardLayoutBackend _backend;
  StreamSubscription<KeyboardLayoutState>? _subscription;
  var _stopped = false;

  void _onStarted(
    KeyboardLayoutStarted event,
    Emitter<KeyboardLayoutState> emit,
  ) {
    if (_stopped) {
      return;
    }
    _subscription ??= _backend.snapshots.listen(
      (state) => add(KeyboardLayoutChanged(state)),
    );
    unawaited(_backend.start());
  }

  Future<void> _onStopped(
    KeyboardLayoutStopped event,
    Emitter<KeyboardLayoutState> emit,
  ) async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    await _backend.dispose();
  }

  @override
  Future<void> close() async {
    final wasStopped = _stopped;
    _stopped = true;
    await _subscription?.cancel();
    _subscription = null;
    if (!wasStopped) {
      await _backend.dispose();
    }
    return super.close();
  }
}
