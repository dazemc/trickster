import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../config/settings.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class SettingsLoaded extends SettingsEvent {
  const SettingsLoaded(this.settings);

  final BarSettings settings;

  @override
  List<Object?> get props => [settings];
}

class SettingsModulesChanged extends SettingsEvent {
  const SettingsModulesChanged(this.modules);

  final List<String> modules;

  @override
  List<Object?> get props => [...modules];
}

class SettingsAccentChanged extends SettingsEvent {
  const SettingsAccentChanged(this.accent);

  final Color? accent;

  @override
  List<Object?> get props => [accent];
}

class SettingsBloc extends Bloc<SettingsEvent, BarSettings> {
  SettingsBloc([super.initialState = const BarSettings()]) {
    on<SettingsLoaded>((event, emit) => emit(event.settings));
    on<SettingsModulesChanged>(
      (event, emit) => emit(state.copyWith(modules: event.modules)),
    );
    on<SettingsAccentChanged>(
      (event, emit) => emit(state.copyWith(accent: event.accent)),
    );
  }
}
