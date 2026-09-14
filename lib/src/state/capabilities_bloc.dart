import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/platform/layer_shell.dart';

/// Host capabilities probed once at startup.
class Capabilities extends Equatable {
  const Capabilities({this.blur = false});

  /// Whether the compositor advertises `ext-background-effect-v1`.
  final bool blur;

  Map<String, Object?> toJson() => {'blur': blur};

  static Capabilities fromJson(Map<String, dynamic> json) =>
      Capabilities(blur: json['blur'] as bool? ?? false);

  @override
  List<Object?> get props => [blur];
}

sealed class CapabilitiesEvent extends Equatable {
  const CapabilitiesEvent();

  @override
  List<Object?> get props => [];
}

class CapabilitiesProbeRequested extends CapabilitiesEvent {
  const CapabilitiesProbeRequested();
}

class CapabilitiesBloc extends Bloc<CapabilitiesEvent, Capabilities> {
  CapabilitiesBloc({Future<bool> Function()? probe, Capabilities? initial})
    : _probe = probe ?? _nativeProbe,
      super(initial ?? const Capabilities()) {
    on<CapabilitiesProbeRequested>(_onProbeRequested);
  }

  final Future<bool> Function() _probe;

  static Future<bool> _nativeProbe() => LayerShell().blurSupported();

  Future<void> _onProbeRequested(
    CapabilitiesProbeRequested event,
    Emitter<Capabilities> emit,
  ) async {
    bool blur;
    try {
      blur = await _probe();
    } on Object {
      blur = false;
    }
    emit(Capabilities(blur: blur));
  }
}
