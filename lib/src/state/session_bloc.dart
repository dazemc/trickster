import 'package:bloc/bloc.dart';

import '../config/session.dart';

sealed class SessionEvent {
  const SessionEvent();
}

class SessionLoaded extends SessionEvent {
  const SessionLoaded(this.config);

  final SessionConfig config;
}

class SessionBloc extends Bloc<SessionEvent, SessionConfig> {
  SessionBloc([super.initialState = const SessionConfig()]) {
    on<SessionLoaded>((event, emit) => emit(event.config));
  }
}
