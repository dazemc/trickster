import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/config/session.dart';

sealed class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

class SessionLoaded extends SessionEvent {
  const SessionLoaded(this.config);

  final SessionConfig config;

  @override
  List<Object?> get props => [config];
}

class SessionBloc extends Bloc<SessionEvent, SessionConfig> {
  SessionBloc([super.initialState = const SessionConfig()]) {
    on<SessionLoaded>((event, emit) => emit(event.config));
  }
}
