import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:trickster/src/cli.dart';
import 'package:trickster/src/config/outputs_store.dart';
import 'package:trickster/src/config/store.dart';
import 'package:trickster/src/state/battery_bloc.dart';
import 'package:trickster/src/state/brightness_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/state/cpu_bloc.dart';
import 'package:trickster/src/state/disk_bloc.dart';
import 'package:trickster/src/state/gpu_bloc.dart';
import 'package:trickster/src/state/keyboard_layout_bloc.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/network_bloc.dart';
import 'package:trickster/src/state/opencode_bloc.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/ram_bloc.dart';
import 'package:trickster/src/state/seat_idle_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/sink_volume_bloc.dart';
import 'package:trickster/src/state/temperature_bloc.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/visualizer_bloc.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/state/workspaces_bloc.dart';

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
      final settings = context.read<SettingsBloc>().state;
      // Do not force-create the idle service on a bar with neither sampler
      // configured; it is a shared observer, not a queued module.
      final seatIdle =
          settings.includes('cpu') ||
              settings.includes('ram') ||
              settings.includes('temperature') ||
              settings.includes('disk') ||
              settings.includes('brightness') ||
              settings.includes('network') ||
              settings.includes('gpu') ||
              settings.includes('vram') ||
              settings.includes('battery') ||
              settings.includes('opencode')
          ? _read<SeatIdleBloc>(context)
          : null;
      return <String, Object?>{
        'ok': true,
        'version': Cli.appVersion,
        'pid': pid,
        'modules': settings.modules,
        'outputs': context.read<OutputsBloc>().state.toJson(),
        // SessionConfig.toJson serializes the accent as a hex string; putting
        // the raw Color in the reply makes jsonEncode throw and leaves the
        // control client without a response.
        'session': session.toJson(),
        'state': <String, Object?>{
          if (_read<WallpaperAccentBloc>(context) case final bloc?)
            'wallpaper': bloc.state.toJson(),
          if (_read<ClockBloc>(context) case final bloc?)
            'clock': bloc.state.toJson(),
          if (_read<CpuBloc>(context) case final bloc?)
            'cpu': bloc.state.toJson(),
          if (_read<RamBloc>(context) case final bloc?)
            'ram': bloc.state.toJson(),
          if (_read<TemperatureBloc>(context) case final bloc?)
            'temperature': bloc.state.toJson(),
          if (_read<DiskBloc>(context) case final bloc?)
            'disk': bloc.state.toJson(),
          if (_read<BrightnessBloc>(context) case final bloc?)
            'brightness': bloc.state.toJson(),
          if (_read<NetworkBloc>(context) case final bloc?)
            'network': bloc.state.toJson(),
          if (_read<KeyboardLayoutBloc>(context) case final bloc?)
            'keyboard_layout': bloc.state.toJson(),
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
          if (_read<OpencodeBloc>(context) case final bloc?)
            'opencode': bloc.state.toJson(),
          if (_read<VisualizerBloc>(context) case final bloc?)
            'visualizer': bloc.state.toJson(),
          if (_read<SinkVolumeBloc>(context) case final bloc?)
            'sink_volume': bloc.state.toJson(),
          if (seatIdle != null) 'seat_idle': seatIdle.state.toJson(),
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
      } on SettingsRevisionConflict catch (error) {
        return <String, Object?>{'ok': false, 'error': error.message};
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
        final written = await outputs.write(document);
        // A settings-app save can land in an outputs override outside the
        // bar's watched config root. Apply the document now instead of
        // waiting for a file event the default watcher would never receive;
        // the outputs watcher still covers file fallback and hand edits.
        reload();
        return <String, Object?>{'ok': true, 'document': written};
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
