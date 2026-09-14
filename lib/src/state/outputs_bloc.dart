import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/layout/system_bar.dart';

sealed class OutputsEvent extends Equatable {
  const OutputsEvent();

  @override
  List<Object?> get props => [];
}

class OutputsLoaded extends OutputsEvent {
  const OutputsLoaded(this.config);

  final OutputsConfig config;

  @override
  List<Object?> get props => [config];
}

class OutputsBloc extends Bloc<OutputsEvent, OutputsConfig> {
  OutputsBloc([super.initialState = const OutputsConfig()]) {
    on<OutputsLoaded>((event, emit) => emit(event.config));
  }
}
