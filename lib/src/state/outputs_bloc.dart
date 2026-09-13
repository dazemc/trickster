import 'package:bloc/bloc.dart';

import '../layout/system_bar.dart';

sealed class OutputsEvent {
  const OutputsEvent();
}

class OutputsLoaded extends OutputsEvent {
  const OutputsLoaded(this.config);

  final OutputsConfig config;
}

class OutputsBloc extends Bloc<OutputsEvent, OutputsConfig> {
  OutputsBloc([super.initialState = const OutputsConfig()]) {
    on<OutputsLoaded>((event, emit) => emit(event.config));
  }
}
