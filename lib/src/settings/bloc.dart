import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/platform/layer_shell.dart';

/// Events the settings application's bloc answers.
sealed class SettingsAppEvent extends Equatable {
  const SettingsAppEvent();

  @override
  List<Object?> get props => [];
}

class SettingsAppLoadRequested extends SettingsAppEvent {
  const SettingsAppLoadRequested();
}

class SettingsAppPreviewed extends SettingsAppEvent {
  const SettingsAppPreviewed(this.settings);

  final BarSettings settings;

  @override
  List<Object?> get props => [settings];
}

class SettingsAppSaveRequested extends SettingsAppEvent {
  const SettingsAppSaveRequested(this.settings);

  final BarSettings settings;

  @override
  List<Object?> get props => [settings];
}

class SettingsAppOutputsPreviewed extends SettingsAppEvent {
  const SettingsAppOutputsPreviewed(this.outputs);

  final OutputsConfig outputs;

  @override
  List<Object?> get props => [outputs];
}

class SettingsAppOutputsSaveRequested extends SettingsAppEvent {
  const SettingsAppOutputsSaveRequested(this.outputs);

  final OutputsConfig outputs;

  @override
  List<Object?> get props => [outputs];
}

const _unset = Object();

/// The settings document, outputs document, and host output list the settings
/// application edits.
class SettingsAppState extends Equatable {
  const SettingsAppState({
    this.settings = const BarSettings(),
    this.outputs = const OutputsConfig(),
    this.availableOutputs = const <LayerOutput>[],
    this.busy = false,
    this.loaded = false,
    this.error,
    this.outputsError,
    this.usingSocket = false,
  });

  final BarSettings settings;
  final OutputsConfig outputs;

  /// The connectors reported by the host, for the displays page.
  final List<LayerOutput> availableOutputs;
  final bool busy;

  /// Whether at least one load finished (successfully or not).
  final bool loaded;
  final String? error;
  final String? outputsError;

  /// Whether the running bar owns the document this session.
  final bool usingSocket;

  SettingsAppState copyWith({
    BarSettings? settings,
    OutputsConfig? outputs,
    List<LayerOutput>? availableOutputs,
    bool? busy,
    bool? loaded,
    Object? error = _unset,
    Object? outputsError = _unset,
    bool? usingSocket,
  }) {
    return SettingsAppState(
      settings: settings ?? this.settings,
      outputs: outputs ?? this.outputs,
      availableOutputs: availableOutputs ?? this.availableOutputs,
      busy: busy ?? this.busy,
      loaded: loaded ?? this.loaded,
      error: identical(error, _unset) ? this.error : error as String?,
      outputsError: identical(outputsError, _unset)
          ? this.outputsError
          : outputsError as String?,
      usingSocket: usingSocket ?? this.usingSocket,
    );
  }

  @override
  List<Object?> get props => [
    settings,
    outputs,
    ...availableOutputs,
    busy,
    loaded,
    error,
    outputsError,
    usingSocket,
  ];

  Map<String, Object?> toJson() => {
    'settings': settings.toJson(),
    'outputs': outputs.encode(),
    'available_outputs': [
      for (final output in availableOutputs)
        {
          'name': output.name,
          'width': output.width,
          'height': output.height,
          'scale': output.scale,
        },
    ],
    'busy': busy,
    'loaded': loaded,
    if (error != null) 'error': error,
    if (outputsError != null) 'outputs_error': outputsError,
    'using_socket': usingSocket,
  };

  static SettingsAppState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('settings app state must be an object');
    }
    final settings = json['settings'];
    final outputs = json['outputs'];
    final available = json['available_outputs'];
    return SettingsAppState(
      settings: settings is Map<String, dynamic>
          ? BarSettings.fromJson(settings)
          : const BarSettings(),
      outputs: outputs is String
          ? OutputsConfig.parse(outputs)
          : const OutputsConfig(),
      availableOutputs: available is List
          ? [
              for (final output in available)
                if (output is Map<String, dynamic>)
                  LayerOutput(
                    name: '${output['name']}',
                    width: (output['width'] as num?)?.toInt() ?? 0,
                    height: (output['height'] as num?)?.toInt() ?? 0,
                  ),
            ]
          : const <LayerOutput>[],
      busy: json['busy'] == true,
      loaded: json['loaded'] == true,
      error: json['error'] as String?,
      outputsError: json['outputs_error'] as String?,
      usingSocket: json['using_socket'] == true,
    );
  }
}

/// Loads and saves the bar's settings and outputs documents for the settings
/// application.
///
/// The running bar owns the document and serves it over the control socket;
/// when no bar answers, the app falls back to the file transport. Both paths
/// ride [NativeSettingsStore], so revision check-and-retry behaves the same
/// whether the bar is up or down.
class SettingsAppBloc extends Bloc<SettingsAppEvent, SettingsAppState> {
  SettingsAppBloc({
    SettingsDocumentTransport? socket,
    SettingsDocumentTransport? file,
    OutputsDocumentTransport? outputsSocket,
    OutputsDocumentTransport? outputsFile,
    LayerShell? layerShell,
  }) : _socket = socket ?? SocketSettingsTransport(),
       _file = file ?? FileSettingsTransport(File(ConfigPaths().settings)),
       _outputsSocket = outputsSocket ?? SocketOutputsTransport(),
       _outputsFile =
           outputsFile ?? FileOutputsTransport(File(ConfigPaths().outputs)),
       _layerShell = layerShell ?? LayerShell(),
       super(const SettingsAppState()) {
    on<SettingsAppLoadRequested>(_onLoad);
    on<SettingsAppPreviewed>(
      (event, emit) => emit(state.copyWith(settings: event.settings)),
    );
    on<SettingsAppSaveRequested>(_onSave);
    on<SettingsAppOutputsPreviewed>(
      (event, emit) => emit(state.copyWith(outputs: event.outputs)),
    );
    on<SettingsAppOutputsSaveRequested>(_onSaveOutputs);
  }

  final SettingsDocumentTransport _socket;
  final SettingsDocumentTransport _file;
  final OutputsDocumentTransport _outputsSocket;
  final OutputsDocumentTransport _outputsFile;
  final LayerShell _layerShell;

  NativeSettingsStore? _store;
  OutputsDocumentTransport? _outputsTransport;

  BarSettings get settings => state.settings;
  OutputsConfig get outputs => state.outputs;
  List<LayerOutput> get availableOutputs => state.availableOutputs;
  String? get error => state.error;
  String? get outputsError => state.outputsError;
  bool get busy => state.busy;
  bool get loaded => state.loaded;
  bool get usingSocket => state.usingSocket;

  Future<void> _onLoad(
    SettingsAppLoadRequested event,
    Emitter<SettingsAppState> emit,
  ) async {
    emit(state.copyWith(busy: true, error: null));
    var store = NativeSettingsStore(_socket);
    var usingSocket = true;
    var settings = state.settings;
    String? error;
    try {
      settings = await store.read();
    } on ControlSocketException {
      store = NativeSettingsStore(_file);
      usingSocket = false;
      try {
        settings = await store.read();
      } on Object catch (readError) {
        error = '$readError';
      }
    } on Object catch (readError) {
      error = '$readError';
    }
    _store = store;

    var outputsTransport = _outputsSocket;
    var outputs = state.outputs;
    String? outputsError;
    try {
      outputs = OutputsConfig.parse(await outputsTransport.read());
    } on ControlSocketException {
      outputsTransport = _outputsFile;
      try {
        outputs = OutputsConfig.parse(await outputsTransport.read());
      } on Object catch (readError) {
        outputsError = '$readError';
      }
    } on Object catch (readError) {
      outputsError = '$readError';
    }
    _outputsTransport = outputsTransport;

    List<LayerOutput> available;
    try {
      available = await _layerShell.outputs();
    } on Object {
      available = const <LayerOutput>[];
    }

    emit(
      SettingsAppState(
        settings: settings,
        outputs: outputs,
        availableOutputs: available,
        busy: false,
        loaded: true,
        error: error,
        outputsError: outputsError,
        usingSocket: usingSocket,
      ),
    );
  }

  Future<void> _onSave(
    SettingsAppSaveRequested event,
    Emitter<SettingsAppState> emit,
  ) async {
    final store = _store;
    if (store == null) {
      return;
    }
    emit(state.copyWith(busy: true, error: null));
    try {
      await store.write(event.settings);
      final settings = await store.read();
      emit(state.copyWith(settings: settings, busy: false, error: null));
    } on Object catch (writeError) {
      emit(state.copyWith(busy: false, error: '$writeError'));
    }
  }

  Future<void> _onSaveOutputs(
    SettingsAppOutputsSaveRequested event,
    Emitter<SettingsAppState> emit,
  ) async {
    final transport = _outputsTransport;
    if (transport == null) {
      return;
    }
    emit(state.copyWith(busy: true, outputsError: null));
    try {
      final outputs = OutputsConfig.parse(
        await transport.write(event.outputs.encode()),
      );
      emit(state.copyWith(outputs: outputs, busy: false, outputsError: null));
    } on Object catch (writeError) {
      emit(state.copyWith(busy: false, outputsError: '$writeError'));
    }
  }
}
