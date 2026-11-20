import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Native source contracts for the PipeWire volume watcher. The behavior is
/// exercised against a live PipeWire graph separately; these assertions pin
/// the proxy/global lifetime rules that prevent a hotplug double-destroy.
void main() {
  final source = _withoutComments(
    File('linux/runner/pipewire_volume.cc').readAsStringSync(),
  );

  test('tracks the metadata, node, and device registry ids', () {
    expect(source, contains('guint32 metadata_id;'));
    expect(source, contains('guint32 node_id;'));
    expect(source, contains('guint32 device_global_id;'));
    expect(source, contains('TricksterVolumeProxyWatch metadata_watch;'));
    expect(source, contains('TricksterVolumeProxyWatch node_watch;'));
    expect(source, contains('TricksterVolumeProxyWatch device_watch;'));
  });

  test('proxy watches report server removal and destroy', () {
    final events = _functionBody(
      source,
      'static const struct pw_proxy_events trickster_volume_proxy_events',
    );
    expect(events, contains('.destroy = trickster_volume_proxy_destroyed'));
    expect(events, contains('.removed = trickster_volume_proxy_removed'));

    final removed = _functionBody(
      source,
      'static void trickster_volume_proxy_removed',
    );
    expect(removed, contains('pw_proxy_destroy(watch->proxy)'));

    final destroyed = _functionBody(
      source,
      'static void trickster_volume_proxy_destroyed',
    );
    expect(destroyed, contains('watch->proxy = nullptr'));
    expect(destroyed, contains('self->metadata = nullptr'));
    expect(destroyed, contains('self->metadata_id = 0'));
    expect(destroyed, contains('self->node = nullptr'));
    expect(destroyed, contains('self->node_id = 0'));
    expect(destroyed, contains('self->device = nullptr'));
    expect(destroyed, contains('self->device_global_id = 0'));
    expect(destroyed, contains('trickster_volume_clear_node_state(self)'));
    expect(destroyed, contains('trickster_volume_clear_device_state(self)'));
  });

  test(
    'global removal clears identity and state without destroying a proxy',
    () {
      final removal = _functionBody(
        source,
        'static void trickster_volume_registry_global_remove',
      );
      expect(removal, contains('g_hash_table_iter_remove'));
      expect(removal, contains('id == self->metadata_id'));
      expect(removal, contains('self->metadata = nullptr'));
      expect(removal, contains('self->metadata_id = 0'));
      expect(removal, contains('id == self->node_id'));
      expect(removal, contains('self->node = nullptr'));
      expect(removal, contains('self->node_id = 0'));
      expect(removal, contains('trickster_volume_clear_node_state(self)'));
      expect(removal, contains('id == self->device_global_id'));
      expect(removal, contains('self->device = nullptr'));
      expect(removal, contains('self->device_global_id = 0'));
      expect(removal, contains('trickster_volume_clear_device_state(self)'));
      expect(
        removal,
        isNot(contains('pw_proxy_destroy')),
        reason: 'the server-destroyed proxy must be left to its watch',
      );
    },
  );

  test('a re-advertised global binds a fresh watched proxy', () {
    final global = _functionBody(
      source,
      'static void trickster_volume_registry_global',
    );
    expect(global, contains('self->metadata == nullptr'));
    expect(global, contains('trickster_volume_bind_metadata(self, id)'));
    expect(global, contains('trickster_volume_bind_sink(self, name)'));

    for (final (signature, drop) in <(String, String)>[
      (
        'static void trickster_volume_bind_metadata',
        'trickster_volume_drop_metadata(self)',
      ),
      (
        'static void trickster_volume_bind_sink',
        'trickster_volume_drop_node(self)',
      ),
      (
        'static void trickster_volume_bind_device',
        'trickster_volume_drop_device(self)',
      ),
    ]) {
      expect(_functionBody(source, signature), contains(drop));
    }

    final watch = _functionBody(
      source,
      'static void trickster_volume_watch_proxy',
    );
    expect(watch, contains('watch->proxy = proxy'));
    expect(watch, contains('pw_proxy_add_listener(proxy, &watch->listener'));
  });

  test('stop drops watches before disconnecting the core', () {
    final stop = _functionBody(source, 'void trickster_volume_stop');
    final lock = stop.indexOf('pw_thread_loop_lock');
    final metadata = stop.indexOf('trickster_volume_drop_metadata');
    final node = stop.indexOf('trickster_volume_drop_node');
    final device = stop.indexOf('trickster_volume_drop_device');
    final core = stop.indexOf('pw_core_disconnect');
    final loopStop = stop.indexOf('pw_thread_loop_stop');
    expect(lock, isNonNegative);
    expect(metadata, greaterThan(lock));
    expect(node, greaterThan(metadata));
    expect(device, greaterThan(node));
    expect(core, greaterThan(device));
    expect(loopStop, greaterThan(core));
    expect(stop, contains('spa_hook_remove(&self->registry_listener)'));
    expect(stop, contains('spa_hook_remove(&self->core_listener)'));
    expect(stop, contains('g_source_remove(source)'));
    expect(stop, contains('self->metadata_watch.proxy = nullptr'));
    expect(stop, contains('self->node_watch.proxy = nullptr'));
    expect(stop, contains('self->device_watch.proxy = nullptr'));
    expect(stop, contains('self->metadata_id = 0'));
    expect(stop, contains('self->node_id = 0'));
    expect(stop, contains('self->device_global_id = 0'));
    expect(stop, contains('g_hash_table_remove_all(self->sinks)'));
  });
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _functionBody(String source, String signature) {
  int? open;
  var search = 0;
  while (search < source.length) {
    final candidate = source.indexOf(signature, search);
    if (candidate < 0) {
      break;
    }
    final body = source.indexOf('{', candidate);
    final declarationEnd = source.indexOf(';', candidate);
    if (body >= 0 && (declarationEnd < 0 || body < declarationEnd)) {
      open = body;
      break;
    }
    search = candidate + signature.length;
  }
  expect(open, isNotNull, reason: 'missing definition: $signature');
  final bodyStart = open!;
  var depth = 0;
  for (var index = bodyStart; index < source.length; index++) {
    if (source[index] == '{') {
      depth += 1;
    } else if (source[index] == '}') {
      depth -= 1;
      if (depth == 0) {
        return source.substring(bodyStart, index + 1);
      }
    }
  }
  fail('unterminated body for: $signature');
}
