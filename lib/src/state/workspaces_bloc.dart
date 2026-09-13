import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../services/workspaces.dart';

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

class WorkspacesBloc extends Bloc<WorkspacesEvent, WorkspacesState> {
  WorkspacesBloc({
    WorkspaceMonitor? monitor,
    WorkspacesState initial = const WorkspacesState(),
  }) : _monitor = monitor ?? WorkspaceMonitor(),
       super(initial) {
    on<WorkspacesStarted>(_onStarted);
    on<WorkspacesStopped>(_onStopped);
    on<WorkspacesSampled>(
      (event, emit) => emit(WorkspacesState(sortedWorkspaces(event.workspaces))),
    );
  }

  final WorkspaceMonitor _monitor;
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

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _monitor.dispose();
    return super.close();
  }
}
