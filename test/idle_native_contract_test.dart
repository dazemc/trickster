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
    expect(runner, contains('trickster_drop_idle_notification(self)'));

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
