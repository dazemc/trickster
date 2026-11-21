import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart' show Offset;

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/settings/availability.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/saver.dart';

const _unset = Object();

/// Keeps the options inspector open only while its module still renders a
/// gear. An enabled module moves to the Unavailable row without one; a
/// disabled module keeps its gear in Disabled, reason note and all.
String? pruneOptions(
  String? module,
  BarSettings settings,
  List<ModuleAvailability> unavailable,
) {
  if (module == null || !BarSettings.knownModules.contains(module)) {
    return null;
  }
  final hidden = <String>{for (final entry in unavailable) entry.module};
  if (settings.includes(module) && hidden.contains(module)) {
    return null;
  }
  return module;
}

/// The configured modules per zone, in strip order; [exclude] removes the
/// row currently in flight.
Map<ModuleZone, List<String>> moduleGroups(
  BarSettings settings,
  List<ModuleAvailability> unavailable, {
  String? exclude,
}) {
  final missing = <String>{for (final entry in unavailable) entry.module};
  final configured = BarSettings.renderableModules(settings.modules);
  return <ModuleZone, List<String>>{
    for (final zone in ModuleZone.values)
      zone: [
        for (final module in configured)
          if (module != exclude &&
              !missing.contains(module) &&
              settings.zoneFor(module) == zone)
            module,
      ],
  };
}

/// Events the settings modules page dispatches.
sealed class ModulesEvent extends Equatable {
  const ModulesEvent();

  @override
  List<Object?> get props => [];
}

class ModulesToggled extends ModulesEvent {
  const ModulesToggled({required this.module, required this.enabled});

  final String module;
  final bool enabled;

  @override
  List<Object?> get props => [module, enabled];
}

class ModulesOptionsToggled extends ModulesEvent {
  const ModulesOptionsToggled(this.module);

  final String module;

  @override
  List<Object?> get props => [module];
}

/// Dismisses the options inspector, returning focus to its gear.
class ModulesOptionsClosed extends ModulesEvent {
  const ModulesOptionsClosed();
}

/// Asks the injected async loader for the bar's live availability.
class ModulesAvailabilityRequested extends ModulesEvent {
  const ModulesAvailabilityRequested();
}

/// Applies a fresh availability list and prunes panels that can no longer
/// render.
class ModulesAvailabilityLoaded extends ModulesEvent {
  const ModulesAvailabilityLoaded(this.unavailable);

  final List<ModuleAvailability> unavailable;

  @override
  List<Object?> get props => unavailable;
}

class ModulesMovedWithinZone extends ModulesEvent {
  const ModulesMovedWithinZone({required this.module, required this.delta});

  final String module;
  final int delta;

  @override
  List<Object?> get props => [module, delta];
}

class ModulesMovedZoneBy extends ModulesEvent {
  const ModulesMovedZoneBy({required this.module, required this.delta});

  final String module;
  final int delta;

  @override
  List<Object?> get props => [module, delta];
}

class ModulesDragStarted extends ModulesEvent {
  const ModulesDragStarted({required this.module, required this.zone});

  final String module;
  final ModuleZone zone;

  @override
  List<Object?> get props => [module, zone];
}

class ModulesDragPreviewed extends ModulesEvent {
  const ModulesDragPreviewed({
    required this.zone,
    required this.index,
    required this.position,
  });

  final ModuleZone? zone;
  final int index;
  final Offset position;

  @override
  List<Object?> get props => [zone, index, position];
}

class ModulesDragEnded extends ModulesEvent {
  const ModulesDragEnded({required this.accepted, required this.withinSegment});

  final bool accepted;
  final bool withinSegment;

  @override
  List<Object?> get props => [accepted, withinSegment];
}

class ModulesDroppedOnDisabled extends ModulesEvent {
  const ModulesDroppedOnDisabled(this.module);

  final String module;

  @override
  List<Object?> get props => [module];
}

class ModulesReset extends ModulesEvent {
  const ModulesReset();
}

/// The modules page's availability, inspector, and drag state.
class ModulesState extends Equatable {
  const ModulesState({
    this.unavailable = const <ModuleAvailability>[],
    this.optionsModule,
    this.dragging,
    this.previewZone,
    this.previewIndex = 0,
    this.lastPointer,
    this.dropHandled = false,
  });

  /// Hardware this machine cannot run, with the reason.
  final List<ModuleAvailability> unavailable;

  /// The module whose options inspector is open, if any.
  final String? optionsModule;

  /// The module currently lifted by a drag.
  final String? dragging;
  final ModuleZone? previewZone;
  final int previewIndex;
  final Offset? lastPointer;
  final bool dropHandled;

  ModulesState copyWith({
    List<ModuleAvailability>? unavailable,
    Object? optionsModule = _unset,
    Object? dragging = _unset,
    Object? previewZone = _unset,
    int? previewIndex,
    Object? lastPointer = _unset,
    bool? dropHandled,
  }) {
    return ModulesState(
      unavailable: unavailable ?? this.unavailable,
      optionsModule: identical(optionsModule, _unset)
          ? this.optionsModule
          : optionsModule as String?,
      dragging: identical(dragging, _unset)
          ? this.dragging
          : dragging as String?,
      previewZone: identical(previewZone, _unset)
          ? this.previewZone
          : previewZone as ModuleZone?,
      previewIndex: previewIndex ?? this.previewIndex,
      lastPointer: identical(lastPointer, _unset)
          ? this.lastPointer
          : lastPointer as Offset?,
      dropHandled: dropHandled ?? this.dropHandled,
    );
  }

  @override
  List<Object?> get props => [
    ...unavailable.map((entry) => Object.hash(entry.module, entry.reason)),
    optionsModule,
    dragging,
    previewZone,
    previewIndex,
    lastPointer,
    dropHandled,
  ];

  Map<String, Object?> toJson() => {
    'unavailable': [
      for (final entry in unavailable)
        {'module': entry.module, 'reason': entry.reason.name},
    ],
    if (optionsModule != null) 'options_module': optionsModule,
    if (dragging != null) 'dragging': dragging,
    if (previewZone != null) 'preview_zone': previewZone!.wire,
    'preview_index': previewIndex,
    if (lastPointer != null)
      'last_pointer': {'dx': lastPointer!.dx, 'dy': lastPointer!.dy},
    'drop_handled': dropHandled,
  };

  static ModulesState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('modules state must be an object');
    }
    final unavailable = json['unavailable'];
    final optionsModule = json['options_module'];
    final pointer = json['last_pointer'];
    final zone = json['preview_zone'];
    ModuleZone? previewZone;
    if (zone is String) {
      try {
        previewZone = ModuleZone.parse(zone);
      } on FormatException {
        previewZone = null;
      }
    }
    return ModulesState(
      unavailable: unavailable is List
          ? [
              for (final entry in unavailable)
                if (entry is Map<String, dynamic>)
                  ModuleAvailability(
                    module: '${entry['module']}',
                    reason: ModuleUnavailableReason.values.firstWhere(
                      (reason) => reason.name == entry['reason'],
                      orElse: () => ModuleUnavailableReason.noBattery,
                    ),
                  ),
            ]
          : const <ModuleAvailability>[],
      optionsModule: optionsModule is String ? optionsModule : null,
      dragging: json['dragging'] as String?,
      previewZone: previewZone,
      previewIndex: (json['preview_index'] as num?)?.toInt() ?? 0,
      lastPointer: pointer is Map<String, dynamic>
          ? Offset(
              (pointer['dx'] as num?)?.toDouble() ?? 0,
              (pointer['dy'] as num?)?.toDouble() ?? 0,
            )
          : null,
      dropHandled: json['drop_handled'] == true,
    );
  }
}

/// The modules page's decisions: which modules are enabled and where they
/// sit, the availability probe, the options panels, and the drag session.
class ModulesBloc extends Bloc<ModulesEvent, ModulesState> {
  ModulesBloc({
    required SettingsAppBloc settings,
    List<ModuleAvailability> Function()? availabilityProbe,
    Future<List<ModuleAvailability>> Function(BarSettings settings)?
    availabilityLoader,
  }) : _settings = settings,
       _availabilityLoader = availabilityLoader,
       super(
         ModulesState(
           unavailable:
               availabilityProbe?.call() ??
               probeModuleAvailability(settings: settings.settings),
         ),
       ) {
    on<ModulesToggled>(_onToggled);
    on<ModulesOptionsToggled>(_onOptionsToggled);
    on<ModulesOptionsClosed>(_onOptionsClosed);
    on<ModulesAvailabilityRequested>(_onAvailabilityRequested);
    on<ModulesAvailabilityLoaded>(_onAvailabilityLoaded);
    on<ModulesMovedWithinZone>(_onMovedWithinZone);
    on<ModulesMovedZoneBy>(_onMovedZoneBy);
    on<ModulesDragStarted>(_onDragStarted);
    on<ModulesDragPreviewed>(_onDragPreviewed);
    on<ModulesDragEnded>(_onDragEnded);
    on<ModulesDroppedOnDisabled>(_onDroppedOnDisabled);
    on<ModulesReset>(_onReset);
    if (availabilityLoader != null) {
      add(const ModulesAvailabilityRequested());
    }
  }

  final SettingsAppBloc _settings;
  final Future<List<ModuleAvailability>> Function(BarSettings settings)?
  _availabilityLoader;
  DebouncedSaver? _saver;

  /// The latest pointer position. This is deliberately outside
  /// [ModulesState]: a pointer move inside the same preview slot must not
  /// rebuild every module row, but the drop fallback still needs the exact
  /// release position.
  Offset? _lastPointer;

  Offset? get lastPointer => _lastPointer;

  BarSettings get _document => _settings.settings;

  /// Applies [change] as a live preview and saves it after the debounce.
  void _apply(BarSettings Function(BarSettings) change) {
    (_saver ??= DebouncedSaver(_settings)).apply(change);
  }

  /// The configured modules per zone, in strip order; [exclude] removes the
  /// row currently in flight.
  Map<ModuleZone, List<String>> _groupsFor(
    BarSettings settings, {
    String? exclude,
  }) {
    return moduleGroups(settings, state.unavailable, exclude: exclude);
  }

  void _onToggled(ModulesToggled event, Emitter<ModulesState> emit) {
    if (!event.enabled && state.optionsModule == event.module) {
      emit(state.copyWith(optionsModule: null));
    }
    _apply((settings) {
      final modules = List<String>.of(settings.modules);
      if (event.enabled) {
        if (!modules.contains(event.module)) {
          modules.add(event.module);
        }
      } else {
        modules.remove(event.module);
      }
      return settings.copyWith(modules: modules);
    });
  }

  void _onOptionsToggled(
    ModulesOptionsToggled event,
    Emitter<ModulesState> emit,
  ) {
    emit(
      state.copyWith(
        optionsModule: state.optionsModule == event.module
            ? null
            : event.module,
      ),
    );
  }

  void _onOptionsClosed(
    ModulesOptionsClosed event,
    Emitter<ModulesState> emit,
  ) {
    if (state.optionsModule == null) {
      return;
    }
    emit(state.copyWith(optionsModule: null));
  }

  Future<void> _onAvailabilityRequested(
    ModulesAvailabilityRequested event,
    Emitter<ModulesState> emit,
  ) async {
    final loader = _availabilityLoader;
    if (loader == null) {
      return;
    }
    final unavailable = await loader(_document);
    if (isClosed) {
      return;
    }
    add(ModulesAvailabilityLoaded(unavailable));
  }

  void _onAvailabilityLoaded(
    ModulesAvailabilityLoaded event,
    Emitter<ModulesState> emit,
  ) {
    emit(
      state.copyWith(
        unavailable: event.unavailable,
        optionsModule: pruneOptions(
          state.optionsModule,
          _document,
          event.unavailable,
        ),
      ),
    );
  }

  /// Keyboard reorder within a zone: swaps the module with its neighbour.
  void _onMovedWithinZone(
    ModulesMovedWithinZone event,
    Emitter<ModulesState> emit,
  ) {
    _apply((settings) {
      final zone = settings.zoneFor(event.module);
      final missing = <String>{
        for (final unavailable in state.unavailable) unavailable.module,
      };
      final segment = [
        for (final candidate in BarSettings.renderableModules(settings.modules))
          if (!missing.contains(candidate) &&
              settings.zoneFor(candidate) == zone)
            candidate,
      ];
      final index = segment.indexOf(event.module);
      final target = index + event.delta;
      if (index < 0 || target < 0 || target >= segment.length) {
        return settings;
      }
      final modules = List<String>.of(settings.modules);
      final other = segment[target];
      final a = modules.indexOf(event.module);
      final b = modules.indexOf(other);
      modules[a] = other;
      modules[b] = event.module;
      return settings.copyWith(modules: modules);
    });
  }

  /// Places [dragged] at [index] within [zone] (clamped); the rest of the
  /// strip keeps its order.
  void _dropOn({
    required String dragged,
    required ModuleZone zone,
    required int index,
  }) {
    _apply((settings) {
      final placement = Map<String, ModuleZone>.of(settings.modulePlacement);
      if (zone == defaultModuleZone(dragged)) {
        placement.remove(dragged);
      } else {
        placement[dragged] = zone;
      }
      final modules = List<String>.of(settings.modules)..remove(dragged);
      // Only rows the page actually renders count here: platform-unavailable
      // modules stay in the document but are hidden, so they must not shift
      // the insertion index the preview promised.
      final missing = <String>{
        for (final unavailable in state.unavailable) unavailable.module,
      };
      final inZone = [
        for (final candidate in BarSettings.renderableModules(modules))
          if (!missing.contains(candidate) &&
              (placement[candidate] ?? defaultModuleZone(candidate)) == zone)
            candidate,
      ];
      final at = index.clamp(0, inZone.length);
      final insertAt = inZone.isEmpty
          ? modules.length
          : at < inZone.length
          ? modules.indexOf(inZone[at])
          : modules.indexOf(inZone.last) + 1;
      modules.insert(insertAt, dragged);
      return settings.copyWith(modulePlacement: placement, modules: modules);
    });
  }

  void _onMovedZoneBy(ModulesMovedZoneBy event, Emitter<ModulesState> emit) {
    final current = _document.zoneFor(event.module);
    final next = ModuleZone.values.indexOf(current) + event.delta;
    if (next < 0 || next >= ModuleZone.values.length) {
      return;
    }
    final target = ModuleZone.values[next];
    final groups = _groupsFor(_document, exclude: event.module);
    _dropOn(
      dragged: event.module,
      zone: target,
      index: groups[target]?.length ?? 0,
    );
  }

  void _onDragStarted(ModulesDragStarted event, Emitter<ModulesState> emit) {
    final current = _groupsFor(_document)[event.zone] ?? const <String>[];
    _lastPointer = null;
    emit(
      state.copyWith(
        optionsModule: null,
        dragging: event.module,
        previewZone: event.zone,
        previewIndex: current.indexOf(event.module).clamp(0, current.length),
        lastPointer: null,
        dropHandled: false,
      ),
    );
  }

  void _onDragPreviewed(
    ModulesDragPreviewed event,
    Emitter<ModulesState> emit,
  ) {
    _lastPointer = event.position;
    if (event.zone == state.previewZone && event.index == state.previewIndex) {
      return;
    }
    emit(
      state.copyWith(
        previewZone: event.zone,
        previewIndex: event.index,
        lastPointer: event.position,
      ),
    );
  }

  void _onDragEnded(ModulesDragEnded event, Emitter<ModulesState> emit) {
    final module = state.dragging;
    final zone = state.previewZone;
    final index = state.previewIndex;
    final handled = state.dropHandled;
    _lastPointer = null;
    emit(
      state.copyWith(
        dragging: null,
        previewZone: null,
        lastPointer: null,
        dropHandled: false,
      ),
    );
    if (handled || module == null || zone == null) {
      return;
    }
    // The target usually accepts; fall back to the release position so a
    // first drag never silently reverts.
    if (!event.accepted && !event.withinSegment) {
      return;
    }
    _dropOn(dragged: module, zone: zone, index: index);
  }

  void _onDroppedOnDisabled(
    ModulesDroppedOnDisabled event,
    Emitter<ModulesState> emit,
  ) {
    emit(
      state.copyWith(
        dropHandled: true,
        optionsModule: state.optionsModule == event.module
            ? null
            : state.optionsModule,
      ),
    );
    _apply((settings) {
      final modules = List<String>.of(settings.modules)..remove(event.module);
      return settings.copyWith(modules: modules);
    });
  }

  void _onReset(ModulesReset event, Emitter<ModulesState> emit) {
    _apply(
      (settings) => settings.copyWith(
        modules: BarSettings.knownModules,
        modulePlacement: const <String, ModuleZone>{},
      ),
    );
  }

  @override
  Future<void> close() async {
    _saver?.dispose();
    return super.close();
  }
}
