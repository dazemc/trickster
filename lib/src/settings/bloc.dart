import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/paths.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/layout/system_bar.dart';
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
  const SettingsAppSaveRequested(this.settings, {this.completion});

  final BarSettings settings;

  /// Completed when this save (success or surfaced error) leaves the bloc.
  /// Flush waits on it so close cannot outrun the write.
  final Completer<void>? completion;

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
  const SettingsAppOutputsSaveRequested(this.outputs, {this.completion});

  final OutputsConfig outputs;
  final Completer<void>? completion;

  @override
  List<Object?> get props => [outputs];
}

/// The settings document changed underneath the application (the bar wrote
/// it); re-read it so an open window reflects bar-side edits.
class SettingsAppDocumentChanged extends SettingsAppEvent {
  const SettingsAppDocumentChanged();
}

/// The outputs document changed underneath the application; refresh the
/// displays page unless it owns an unsaved preview.
class SettingsAppOutputsChanged extends SettingsAppEvent {
  const SettingsAppOutputsChanged();
}

const _unset = Object();

/// Starts [future] and converts either its value or its error into a record,
/// so independent startup reads can run together without an unhandled error
/// from the ones that are awaited later.
Future<(T?, String?)> _settle<T>(Future<T> future) async {
  try {
    return (await future, null);
  } on Object catch (error) {
    return (null, '$error');
  }
}

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
          'view_id': output.viewId,
          'x': output.x,
          'y': output.y,
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
                    viewId: (output['view_id'] as num?)?.toInt() ?? -1,
                    x: (output['x'] as num?)?.toInt() ?? 0,
                    y: (output['y'] as num?)?.toInt() ?? 0,
                    width: (output['width'] as num?)?.toInt() ?? 0,
                    height: (output['height'] as num?)?.toInt() ?? 0,
                    scale: (output['scale'] as num?)?.toInt().clamp(1, 8) ?? 1,
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
/// ride [NativeSettingsStore], so a revision conflict keeps the latest disk
/// document and surfaces an explicit error whether the bar is up or down.
class SettingsAppBloc extends Bloc<SettingsAppEvent, SettingsAppState> {
  SettingsAppBloc({
    SettingsDocumentTransport? socket,
    SettingsDocumentTransport? file,
    OutputsDocumentTransport? outputsSocket,
    OutputsDocumentTransport? outputsFile,
    LayerShell? layerShell,
  }) : _settingsTransport = FallbackSettingsTransport(
         socket: socket ?? SocketSettingsTransport(),
         file: file ?? FileSettingsTransport(File(ConfigPaths().settings)),
       ),
       _outputsTransport = FallbackOutputsTransport(
         socket: outputsSocket ?? SocketOutputsTransport(),
         file: outputsFile ?? FileOutputsTransport(File(ConfigPaths().outputs)),
       ),
       _layerShell = layerShell ?? LayerShell(),
       super(const SettingsAppState()) {
    on<SettingsAppLoadRequested>(
      (event, emit) => _serial(() => _onLoad(event, emit)),
    );
    on<SettingsAppPreviewed>(
      (event, emit) => _serial(() async {
        emit(state.copyWith(settings: event.settings));
      }),
    );
    on<SettingsAppSaveRequested>(
      (event, emit) => _serial(() => _onSave(event, emit)),
    );
    on<SettingsAppOutputsPreviewed>(
      (event, emit) => _serial(() async {
        _outputsDraft = true;
        emit(state.copyWith(outputs: event.outputs));
      }),
    );
    on<SettingsAppOutputsSaveRequested>(
      (event, emit) => _serial(() => _onSaveOutputs(event, emit)),
    );
    on<SettingsAppDocumentChanged>(
      (event, emit) => _serial(() => _onDocumentChanged(event, emit)),
    );
    on<SettingsAppOutputsChanged>(
      (event, emit) => _serial(() => _onOutputsChanged(event, emit)),
    );
  }

  final FallbackSettingsTransport _settingsTransport;
  final FallbackOutputsTransport _outputsTransport;
  final LayerShell _layerShell;

  NativeSettingsStore? _store;

  /// Serializes load/save/reload/preview emissions. Bloc handlers are
  /// concurrent by default; without this a slow socket write could emit an
  /// older document after a newer preview or watcher reload.
  Future<void> _queue = Future<void>.value();
  var _outputsDraft = false;

  Future<void> _serial(Future<void> Function() action) {
    final next = _queue.then((_) async {
      if (!isClosed) {
        await action();
      }
    });
    _queue = next.catchError((Object _) {});
    return next;
  }

  /// Completes when every event queued so far has run. Close waits on this
  /// after flushing the debounced edit.
  Future<void> get settled => _queue;

  /// Writes [settings] through the serialized save path; used by the flush
  /// hook before the window closes.
  Future<void> saveNow(BarSettings settings) {
    final completion = Completer<void>();
    add(SettingsAppSaveRequested(settings, completion: completion));
    return completion.future;
  }

  /// Writes the previewed outputs now, if the page has an unsaved draft.
  Future<void> flushOutputs() {
    if (!_outputsDraft) {
      return settled;
    }
    final completion = Completer<void>();
    add(SettingsAppOutputsSaveRequested(state.outputs, completion: completion));
    return completion.future;
  }

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
    final store = NativeSettingsStore(_settingsTransport);
    _store = store;
    // The documents and the host output list are independent; start all
    // three before awaiting any so a slow control socket does not add its
    // latency to the other reads.
    final settingsRead = _settle(store.read());
    final outputsRead = _settle(
      _outputsTransport.read().then(OutputsConfig.parse),
    );
    final availableRead = _settle(_layerShell.outputs());

    final (settingsValue, error) = await settingsRead;
    final (outputsValue, outputsError) = await outputsRead;
    final (availableValue, _) = await availableRead;

    _outputsDraft = false;
    emit(
      SettingsAppState(
        settings: settingsValue ?? state.settings,
        outputs: outputsValue ?? state.outputs,
        availableOutputs: availableValue ?? const <LayerOutput>[],
        busy: false,
        loaded: true,
        error: error,
        outputsError: outputsError,
        usingSocket: _settingsTransport.usingSocket,
      ),
    );
  }

  Future<void> _onSave(
    SettingsAppSaveRequested event,
    Emitter<SettingsAppState> emit,
  ) async {
    final store = _store;
    if (store == null) {
      event.completion?.complete();
      return;
    }
    emit(state.copyWith(busy: true, error: null));
    try {
      final written = await store.write(event.settings);
      final settings = BarSettings.decode(written.json);
      emit(
        state.copyWith(
          settings: settings,
          busy: false,
          error: null,
          usingSocket: _settingsTransport.usingSocket,
        ),
      );
    } on SettingsRevisionConflict catch (conflict) {
      // Keep the other writer's document. The edit stays unapplied; the user
      // can see the current values and retry deliberately.
      var latest = state.settings;
      try {
        latest = await store.read();
      } on Object {
        // Keep the in-memory editor if even the reload fails.
      }
      emit(
        state.copyWith(
          settings: latest,
          busy: false,
          error: '${conflict.message}; reloaded the latest settings',
          usingSocket: _settingsTransport.usingSocket,
        ),
      );
    } on Object catch (writeError) {
      emit(
        state.copyWith(
          busy: false,
          error: '$writeError',
          usingSocket: _settingsTransport.usingSocket,
        ),
      );
    } finally {
      event.completion?.complete();
    }
  }

  Future<void> _onSaveOutputs(
    SettingsAppOutputsSaveRequested event,
    Emitter<SettingsAppState> emit,
  ) async {
    emit(state.copyWith(busy: true, outputsError: null));
    try {
      final outputs = OutputsConfig.parse(
        await _outputsTransport.write(event.outputs.encode()),
      );
      _outputsDraft = false;
      emit(state.copyWith(outputs: outputs, busy: false, outputsError: null));
    } on Object catch (writeError) {
      _outputsDraft = true;
      emit(state.copyWith(busy: false, outputsError: '$writeError'));
    } finally {
      event.completion?.complete();
    }
  }

  /// A bar-side write arrives as a file event; reading through the same store
  /// keeps the revision line and never touches outputs or the busy flag.
  Future<void> _onDocumentChanged(
    SettingsAppDocumentChanged event,
    Emitter<SettingsAppState> emit,
  ) async {
    final store = _store;
    if (store == null) {
      return;
    }
    try {
      emit(
        state.copyWith(
          settings: await store.read(),
          usingSocket: _settingsTransport.usingSocket,
        ),
      );
    } on Object {
      // Transient read failure: keep the editor on the current document.
    }
  }

  /// A file event may be the bar or a hand edit. An unsaved preview owns the
  /// page until its debounce lands; do not overwrite it from disk.
  Future<void> _onOutputsChanged(
    SettingsAppOutputsChanged event,
    Emitter<SettingsAppState> emit,
  ) async {
    if (_outputsDraft) {
      return;
    }
    try {
      final outputs = OutputsConfig.parse(await _outputsTransport.read());
      emit(state.copyWith(outputs: outputs, outputsError: null));
    } on Object {
      // Transient read failure: keep the current outputs.
    }
  }
}
