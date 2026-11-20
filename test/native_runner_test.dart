import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// GTK copies the region into a widget's input-shape state, so the caller
/// owns its reference and must release it. A tooltip is rebuilt per open and
/// the bootstrap once per process, so an unpaired region leaks per surface.
void main() {
  final source = _withoutComments(
    File('linux/runner/my_application.cc').readAsStringSync(),
  );

  test('every cairo input region is destroyed', () {
    final creates = _count(source, 'cairo_region_create(');
    final destroys = _count(source, 'cairo_region_destroy(');
    expect(creates, greaterThan(0), reason: 'no input region is created');
    expect(
      destroys,
      creates,
      reason: 'every input region must be released by its creator',
    );
  });

  test('the outputs method reports each monitor global position', () {
    expect(source, contains('fl_value_new_int(geometry.x)'));
    expect(source, contains('fl_value_new_int(geometry.y)'));
    expect(source, contains('fl_value_new_int(geometry.width)'));
    expect(source, contains('fl_value_new_int(geometry.height)'));
  });

  test('connector lookups are cached per monitor and freed', () {
    expect(source, contains('self->connector_cache = g_hash_table_new_full('));
    expect(source, contains('g_direct_hash, g_direct_equal, nullptr, g_free'));
    final lookup = _functionBody(
      source,
      'static gchar* trickster_connector_for_monitor',
    );
    expect(
      lookup,
      contains('g_hash_table_lookup(self->connector_cache, monitor)'),
    );
    expect(lookup, contains('g_hash_table_insert(self->connector_cache'));
    expect(lookup, contains('g_strdup("")'));
    expect(lookup, contains('g_strdup(found)'));

    final added = _functionBody(source, 'static void monitor_added_cb');
    expect(
      added,
      contains('g_hash_table_remove(self->connector_cache, monitor)'),
    );
    final removed = _functionBody(source, 'static void monitor_removed_cb');
    expect(
      removed,
      contains('g_hash_table_remove(self->connector_cache, monitor)'),
    );
    expect(
      source,
      contains('g_clear_pointer(&self->connector_cache, g_hash_table_unref)'),
    );
    expect(
      _count(source, 'trickster_connector_for_monitor(self, monitor)'),
      greaterThanOrEqualTo(3),
    );
  });

  test('overlay surfaces track their monitor or refuse a null monitor', () {
    final body = _functionBody(
      source,
      'static TricksterSurface* trickster_overlay_surface_new',
    );
    final guard = body.indexOf('monitor == nullptr');
    final allocation = body.indexOf('g_new0(TricksterSurface');
    expect(guard, isNonNegative);
    expect(allocation, isNonNegative);
    expect(guard, lessThan(allocation));
    expect(body, contains('surface->monitor = monitor;'));
    expect(body, contains('return nullptr;'));
  });

  test('monitor removal destroys tracked menu and tooltip overlays', () {
    final helper = _functionBody(
      source,
      'static void trickster_destroy_overlays_for_monitor',
    );
    expect(helper, contains('self->menus'));
    expect(helper, contains('self->tooltips'));
    expect(helper, contains('gtk_widget_destroy'));
    expect(helper, contains('g_ptr_array_remove_index'));
    expect(
      helper,
      contains('ext_background_effect_surface_v1_destroy(surface->blur)'),
    );

    final removed = _functionBody(source, 'static void monitor_removed_cb');
    expect(
      removed,
      contains('trickster_destroy_overlays_for_monitor(self, monitor);'),
    );
  });

  test('overlay open callers handle a refused untracked surface', () {
    expect(source, contains('if (menu != nullptr)'));
    expect(source, contains('g_ptr_array_add(self->menus, menu);'));
    expect(source, contains('if (tooltip != nullptr)'));
    expect(source, contains('g_ptr_array_add(self->tooltips, tooltip);'));
  });

  test('the blur registry persists and records the manager global', () {
    expect(source, contains('struct wl_registry* blur_registry;'));
    expect(source, contains('uint32_t blur_manager_global;'));

    final probe = _functionBody(source, 'static gboolean trickster_probe_blur');
    expect(probe, contains('self->blur_registry = registry;'));
    expect(
      probe,
      isNot(contains('wl_registry_destroy(registry)')),
      reason: 'the registry must stay alive to observe a later manager global',
    );

    final global = _functionBody(source, 'static void blur_registry_global');
    expect(global, contains('self->blur_manager_global = name;'));
    expect(global, contains('ext_background_effect_manager_v1_add_listener'));

    final remove = _functionBody(
      source,
      'static void blur_registry_global_remove',
    );
    expect(remove, contains('name != self->blur_manager_global'));
  });

  test('blur manager removal clears every surface array', () {
    final remove = _functionBody(
      source,
      'static void blur_registry_global_remove',
    );
    expect(remove, contains('trickster_drop_blur_manager(self);'));
    expect(remove, contains('self->blur_rebinding = TRUE;'));
    expect(remove, contains('trickster_emit_blur_changed(self, FALSE);'));

    final drop = _functionBody(
      source,
      'static void trickster_drop_blur_manager',
    );
    expect(drop, contains('trickster_clear_blur_effects(self, TRUE);'));
    expect(
      drop,
      contains('ext_background_effect_manager_v1_destroy(self->blur_manager)'),
    );
    expect(drop, contains('self->blur_manager_global = 0;'));
    expect(drop, contains('self->blur_supported = FALSE;'));

    final clear = _functionBody(
      source,
      'static void trickster_clear_blur_effects',
    );
    expect(clear, contains('self->surfaces'));
    expect(clear, contains('self->menus'));
    expect(clear, contains('self->tooltips'));
    expect(clear, contains('self->settings_blur'));
    expect(
      clear,
      contains('ext_background_effect_surface_v1_destroy(surface->blur)'),
    );
    expect(
      clear,
      contains('ext_background_effect_surface_v1_destroy(self->settings_blur)'),
    );
  });

  test('a lost blur capability clears every surface array', () {
    final capabilities = _functionBody(source, 'static void blur_capabilities');
    expect(capabilities, contains('if (!supported)'));
    expect(
      capabilities,
      contains('trickster_clear_blur_effects(self, FALSE);'),
    );
    expect(
      capabilities,
      contains('trickster_emit_blur_changed(self, supported);'),
    );
  });

  test('a re-advertised blur manager rebinds and re-announces blur', () {
    final global = _functionBody(source, 'static void blur_registry_global');
    expect(global, contains('if (self->blur_rebinding)'));
    expect(global, contains('self->blur_rebinding = FALSE;'));
    expect(global, contains('self->blur_supported = TRUE;'));
    expect(global, contains('trickster_emit_blur_changed(self, TRUE);'));
  });

  test('dispose destroys the blur registry and every effect', () {
    final dispose = _functionBody(source, 'static void my_application_dispose');
    expect(dispose, contains('trickster_drop_blur_manager(self);'));
    expect(dispose, contains('wl_registry_destroy(self->blur_registry);'));
    expect(dispose, contains('self->blur_registry = nullptr;'));
  });

  test('both click-through windows route through the helper', () {
    final helper = RegExp(
      r'static void trickster_make_click_through\(GtkWidget\* widget\)'
      r'\s*\{([^}]*)\}',
    ).firstMatch(source);
    expect(helper, isNotNull, reason: 'click-through helper not found');

    final body = helper!.group(1)!;
    expect(_count(body, 'cairo_region_create('), 1);
    expect(_count(body, 'gtk_widget_input_shape_combine_region('), 1);
    expect(_count(body, 'cairo_region_destroy('), 1);

    final outsideHelper = source.replaceFirst(helper.group(0)!, '');
    expect(
      _count(outsideHelper, 'trickster_make_click_through('),
      2,
      reason: 'the tooltip and bootstrap windows both need the helper',
    );
    expect(
      _count(outsideHelper, 'gtk_widget_input_shape_combine_region('),
      0,
      reason: 'input regions belong in the helper only',
    );
  });
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

int _count(String source, String token) {
  var count = 0;
  var index = source.indexOf(token);
  while (index != -1) {
    count++;
    index = source.indexOf(token, index + token.length);
  }
  return count;
}

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
