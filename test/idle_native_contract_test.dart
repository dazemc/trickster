import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The idle observer crosses C, CMake, the method channel, and the preflight.
/// This source contract catches a native half that would otherwise only fail
/// on a live compositor.
void main() {
  test('the runner binds an inhibitor-aware idle notification', () {
    final runner = File('linux/runner/my_application.cc').readAsStringSync();

    expect(runner, contains('ext-idle-notify-v1-client-protocol.h'));
    expect(runner, contains('ext_idle_notifier_v1_get_idle_notification'));
    expect(runner, contains('ext_idle_notification_v1_add_listener'));
    expect(runner, contains('idle_notification_idled'));
    expect(runner, contains('idle_notification_resumed'));
    expect(runner, contains('"idleChanged"'));
    expect(runner, contains('ext_idle_notification_v1_destroy'));
    expect(runner, contains('kIdleTimeoutMs = 60000'));
    expect(
      runner,
      contains('&ext_idle_notifier_v1_interface, MIN(version, 1)'),
    );
    expect(runner, contains('trickster_install_idle(self);'));
    expect(runner, contains('wl_registry_destroy(self->idle_registry)'));
    expect(runner, contains('trickster_drop_idle_notifier(self)'));
    expect(runner, contains('GPtrArray* idle_seats;'));
    expect(runner, contains('TricksterIdleSeat'));

    final settingsIndex = runner.indexOf('if (self->settings_mode)');
    final installIndex = runner.indexOf(
      'trickster_install_idle(self);',
      settingsIndex,
    );
    expect(settingsIndex, greaterThanOrEqualTo(0));
    expect(installIndex, greaterThan(settingsIndex));
    final settingsBranch =
        RegExp(
          r'if \(self->settings_mode\) \{.*?\n  \}',
          dotAll: true,
        ).firstMatch(runner)?.group(0) ??
        '';
    expect(settingsBranch, isNot(contains('trickster_install_idle')));

    // Pure observer: no input devices, no inhibitor, no v2 input-only API.
    expect(
      runner,
      isNot(contains('ext_idle_notifier_v1_get_input_idle_notification')),
    );
    expect(runner, isNot(contains('zwp_idle_inhibitor')));
    expect(runner, isNot(contains('wl_seat_get_pointer')));
    expect(runner, isNot(contains('wl_seat_get_keyboard')));
    expect(runner, isNot(contains('wl_seat_get_touch')));
  });

  test('every seat gets a notification and the aggregate is all-idle', () {
    final runner = File('linux/runner/my_application.cc').readAsStringSync();

    expect(runner, contains('GPtrArray* idle_seats;'));
    expect(runner, contains('struct wl_seat* seat;'));
    expect(runner, contains('struct ext_idle_notification_v1* notification;'));
    expect(runner, contains('gboolean idle;'));

    final add = _functionBody(runner, 'static void idle_registry_global');
    expect(add, contains('trickster_idle_seat_for(self, name)'));
    expect(add, contains('g_ptr_array_add(self->idle_seats, seat)'));
    expect(add, contains('MIN(version, 1)'));
    expect(add, contains('wl_seat_add_listener'));

    final installSeat = _functionBody(
      runner,
      'static gboolean trickster_install_seat_idle',
    );
    expect(installSeat, contains('ext_idle_notifier_v1_get_idle_notification'));
    expect(installSeat, contains('kIdleTimeoutMs'));
    expect(installSeat, contains('seat->seat'));
    expect(installSeat, contains('idle_notification_idled'));
    expect(installSeat, contains('idle_notification_resumed'));

    final aggregate = _functionBody(
      runner,
      'static gboolean trickster_idle_aggregate',
    );
    expect(aggregate, contains('self->idle_notifier == nullptr'));
    expect(aggregate, contains('self->idle_seats->len == 0'));
    expect(aggregate, contains('seat->notification == nullptr'));
    expect(aggregate, contains('!seat->idle'));
    expect(aggregate, contains('return TRUE'));
    expect(aggregate, contains('return FALSE'));
    expect(
      runner,
      contains(
        'fl_value_new_bool(trickster_idle_aggregate(self) ? TRUE : FALSE)',
      ),
    );

    final seatIdle = _functionBody(
      runner,
      'static gboolean trickster_probe_idle',
    );
    expect(seatIdle, contains('trickster_install_idle(self)'));

    final capabilities = _functionBody(
      runner,
      'static gboolean trickster_install_idle',
    );
    expect(capabilities, contains('trickster_install_seat_idle(self, seat)'));
    expect(capabilities, contains('return any'));
  });

  test('any resume and a removed seat reset the aggregate', () {
    final runner = File('linux/runner/my_application.cc').readAsStringSync();

    final resumed = _functionBody(
      runner,
      'static void idle_notification_resumed',
    );
    expect(resumed, contains('seat->idle = FALSE'));
    expect(resumed, contains('trickster_recompute_idle(seat->app)'));

    final idled = _functionBody(runner, 'static void idle_notification_idled');
    expect(idled, contains('seat->idle = TRUE'));
    expect(idled, contains('trickster_recompute_idle(seat->app)'));

    final remove = _functionBody(
      runner,
      'static void idle_registry_global_remove',
    );
    expect(remove, contains('name == self->idle_notifier_global'));
    expect(remove, contains('trickster_drop_idle_notifier(self)'));
    expect(remove, contains('g_ptr_array_remove_index(self->idle_seats, i)'));
    expect(remove, contains('trickster_reset_idle_seats(self)'));
    expect(remove, contains('trickster_recompute_idle(self)'));

    final drop = _functionBody(
      runner,
      'static void trickster_drop_idle_notifier',
    );
    expect(drop, contains('trickster_destroy_idle_notifications(self)'));
    expect(drop, contains('ext_idle_notifier_v1_destroy(self->idle_notifier)'));
    expect(drop, contains('self->idle_notifier_global = 0'));

    final reset = _functionBody(
      runner,
      'static void trickster_reset_idle_seats',
    );
    expect(reset, contains('seat->idle = FALSE'));
  });

  test('dispose releases every seat, notification, notifier, and registry', () {
    final runner = File('linux/runner/my_application.cc').readAsStringSync();
    final dispose = _functionBody(runner, 'static void my_application_dispose');
    expect(
      dispose,
      contains('g_clear_pointer(&self->idle_seats, g_ptr_array_unref)'),
    );
    expect(
      dispose,
      contains('ext_idle_notifier_v1_destroy(self->idle_notifier)'),
    );
    expect(dispose, contains('wl_registry_destroy(self->idle_registry)'));

    final free = _functionBody(runner, 'static void trickster_idle_seat_free');
    expect(
      free,
      contains('ext_idle_notification_v1_destroy(seat->notification)'),
    );
    expect(free, contains('wl_seat_destroy(seat->seat)'));
    expect(free, contains('g_free(seat)'));
    expect(
      runner,
      contains(
        'self->idle_seats = g_ptr_array_new_with_free_func('
        'trickster_idle_seat_free)',
      ),
    );
  });

  test('the generated protocol and CMake source are committed', () {
    expect(
      File('linux/runner/ext-idle-notify-v1-client-protocol.h').existsSync(),
      isTrue,
    );
    expect(
      File('linux/runner/ext-idle-notify-v1-client-protocol.c').existsSync(),
      isTrue,
    );
    final cmake = File('linux/runner/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('"ext-idle-notify-v1-client-protocol.c"'));
  });

  test('the preflight reports idle-notify with a graceful fallback', () {
    final main = File('lib/main.dart').readAsStringSync();
    final idleOk = RegExp(r"ok\('idle-notify'").allMatches(main).length;
    final idleBad = RegExp(r"bad\('idle-notify'").allMatches(main).length;
    expect(idleOk, 2);
    expect(idleBad, 0);
    expect(main, contains('idleSupported()'));
    expect(main, contains('samplers keep running'));
    expect(main, contains('initialSeatIdle'));
    final initial = main.indexOf(
      'final initialSeatIdle = await _probeSeatIdle();',
    );
    expect(initial, greaterThanOrEqualTo(0));
    expect(main.indexOf('  runWidget(', initial), greaterThan(initial));
    final blur = main.indexOf("ok('blur'");
    final idle = main.indexOf("ok('idle-notify'");
    final outputs = main.indexOf('final outputs =');
    expect(blur, greaterThanOrEqualTo(0));
    expect(idle, greaterThan(blur));
    expect(outputs, greaterThan(idle));
  });
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
