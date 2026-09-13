import 'dart:ui';

import 'package:bloc/bloc.dart';

import '../config/settings.dart';

sealed class SettingsEvent {
  const SettingsEvent();
}

class SettingsLoaded extends SettingsEvent {
  const SettingsLoaded(this.settings);

  final BarSettings settings;
}

class SettingsModulesChanged extends SettingsEvent {
  const SettingsModulesChanged(this.modules);

  final List<String> modules;
}

class SettingsAccentChanged extends SettingsEvent {
  const SettingsAccentChanged(this.accent);

  final Color? accent;
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
