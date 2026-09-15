import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/workspaces.dart';

sealed class WorkspacesEvent extends Equatable {
  const WorkspacesEvent();

  @override
  List<Object?> get props => [];
}

class WorkspacesStarted extends WorkspacesEvent {
  const WorkspacesStarted();
}

class WorkspacesStopped extends WorkspacesEvent {
  const WorkspacesStopped();
}

class WorkspacesSampled extends WorkspacesEvent {
  const WorkspacesSampled(this.workspaces);

  final List<Workspace> workspaces;

  @override
  List<Object?> get props => [...workspaces];
}

class WorkspacesFocusRequested extends WorkspacesEvent {
  const WorkspacesFocusRequested(this.workspace);

  final Workspace workspace;

  @override
  List<Object?> get props => [workspace];
}

class WorkspacesBloc extends Bloc<WorkspacesEvent, WorkspacesState> {
  WorkspacesBloc({
    WorkspaceMonitor? monitor,
    WorkspacesState initial = const WorkspacesState(),
    void Function(String message)? log,
  }) : _monitor = monitor ?? WorkspaceMonitor(),
       _log = log ?? _stderrLog,
       super(initial) {
    on<WorkspacesStarted>(_onStarted);
    on<WorkspacesStopped>(_onStopped);
    on<WorkspacesSampled>(
      (event, emit) =>
          emit(WorkspacesState(sortedWorkspaces(event.workspaces))),
    );
    on<WorkspacesFocusRequested>(_onFocusRequested);
  }

  final WorkspaceMonitor _monitor;
  final void Function(String message) _log;
  StreamSubscription<List<Workspace>>? _subscription;

  Future<void> _onStarted(
    WorkspacesStarted event,
    Emitter<WorkspacesState> emit,
  ) async {
    _subscription ??= _monitor.snapshots.listen(
      (workspaces) => add(WorkspacesSampled(workspaces)),
    );
    await _monitor.start();
  }

  Future<void> _onStopped(
    WorkspacesStopped event,
    Emitter<WorkspacesState> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onFocusRequested(
    WorkspacesFocusRequested event,
    Emitter<WorkspacesState> emit,
  ) async {
    final focused = await _monitor.focusWorkspace(event.workspace);
    if (!focused) {
      _log('trickster: could not focus workspace ${event.workspace.name}');
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _monitor.dispose();
    return super.close();
  }
}

void _stderrLog(String message) => stderr.writeln(message);
