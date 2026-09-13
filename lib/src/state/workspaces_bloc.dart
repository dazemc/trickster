import 'dart:async';

import 'package:bloc/bloc.dart';

import '../services/workspaces.dart';

sealed class WorkspacesEvent {
  const WorkspacesEvent();
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
}

class WorkspacesBloc extends Bloc<WorkspacesEvent, List<Workspace>> {
  WorkspacesBloc({WorkspaceMonitor? monitor})
    : _monitor = monitor ?? WorkspaceMonitor(),
      super(const []) {
    on<WorkspacesStarted>(_onStarted);
    on<WorkspacesStopped>(_onStopped);
    on<WorkspacesSampled>((event, emit) => emit(event.workspaces));
  }

  final WorkspaceMonitor _monitor;
  StreamSubscription<List<Workspace>>? _subscription;

  Future<void> _onStarted(
    WorkspacesStarted event,
    Emitter<List<Workspace>> emit,
  ) async {
    _subscription ??= _monitor.snapshots.listen(
      (workspaces) => add(WorkspacesSampled(workspaces)),
    );
    await _monitor.start();
  }

  Future<void> _onStopped(
    WorkspacesStopped event,
    Emitter<List<Workspace>> emit,
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
