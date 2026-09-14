import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cli.dart';
import '../config/outputs_store.dart';
import '../config/store.dart';
import '../state/battery_bloc.dart';
import '../state/clock_bloc.dart';
import '../state/cpu_bloc.dart';
import '../state/gpu_bloc.dart';
import '../state/media_bloc.dart';
import '../state/outputs_bloc.dart';
import '../state/session_bloc.dart';
import '../state/settings_bloc.dart';
import '../state/tray_bloc.dart';
import '../state/workspaces_bloc.dart';

/// The bar's control request dispatcher: `version`, `status`, and the
/// settings document transport used by `tricksterctl` and future clients.
Future<Map<String, Object?>> handleControlRequest({
  required BuildContext context,
  required FileSettingsTransport settings,
  required OutputsDocumentTransport outputs,
  required String? Function() reload,
  required Map<String, Object?> request,
}) async {
  switch (request['command']) {
    case 'version':
      return <String, Object?>{
        'ok': true,
        'version': Cli.appVersion,
        'protocol': 1,
      };
    case 'status':
      if (!context.mounted) {
        return <String, Object?>{
          'ok': false,
          'error': 'trickster is shutting down',
        };
      }
      final session = context.read<SessionBloc>().state;
      return <String, Object?>{
        'ok': true,
        'version': Cli.appVersion,
        'pid': pid,
        'modules': context.read<SettingsBloc>().state.modules,
        'outputs': context.read<OutputsBloc>().state.toJson(),
        'session': <String, Object?>{
          'layer': session.layer.name,
          'namespace': session.namespace,
          'keyboard': session.keyboard.name,
          'accent': session.accent,
        },
        'state': <String, Object?>{
          if (_read<ClockBloc>(context) case final bloc?)
            'clock': bloc.state.toJson(),
          if (_read<CpuBloc>(context) case final bloc?)
            'cpu': bloc.state.toJson(),
          if (_read<GpuBloc>(context) case final bloc?)
            'gpu': bloc.state.toJson(),
          if (_read<BatteryBloc>(context) case final bloc?)
            'battery': bloc.state.toJson(),
          if (_read<WorkspacesBloc>(context) case final bloc?)
            'workspaces': bloc.state.toJson(),
          if (_read<TrayBloc>(context) case final bloc?)
            'tray': bloc.state.toJson(),
          if (_read<MediaBloc>(context) case final bloc?)
            'media': bloc.state.toJson(),
        },
      };
    case 'reload':
      final error = reload();
      return error == null
          ? <String, Object?>{'ok': true}
          : <String, Object?>{'ok': false, 'error': error};
    case 'settings.read':
      final document = await settings.read();
      return <String, Object?>{
        'ok': true,
        'revision': document.revision,
        'document': document.json,
      };
    case 'settings.write':
      final expected = request['expectedRevision'];
      final document = request['document'];
      if (expected is! int || document is! String) {
        return <String, Object?>{
          'ok': false,
          'error': 'expectedRevision and document are required',
        };
      }
      try {
        final written = await settings.write(
          expectedRevision: expected,
          document: document,
        );
        return <String, Object?>{
          'ok': true,
          'revision': written.revision,
          'document': written.json,
        };
      } on StateError catch (error) {
        return <String, Object?>{'ok': false, 'error': error.message};
      }
    case 'outputs.read':
      try {
        return <String, Object?>{'ok': true, 'document': await outputs.read()};
      } on Object catch (error) {
        return <String, Object?>{'ok': false, 'error': '$error'};
      }
    case 'outputs.write':
      final document = request['document'];
      if (document is! String) {
        return <String, Object?>{'ok': false, 'error': 'document is required'};
      }
      try {
        return <String, Object?>{
          'ok': true,
          'document': await outputs.write(document),
        };
      } on FormatException catch (error) {
        return <String, Object?>{'ok': false, 'error': error.message};
      } on Object catch (error) {
        return <String, Object?>{'ok': false, 'error': '$error'};
      }
    default:
      return <String, Object?>{
        'ok': false,
        'error': 'unknown command: ${request['command']}',
      };
  }
}

T? _read<T extends Object>(BuildContext context) {
  try {
    return context.read<T>();
  } on Object {
    return null;
  }
}
