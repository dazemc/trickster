import 'package:flutter/widgets.dart';

import 'package:trickster/src/settings/controller.dart';

/// Exposes the settings application's [SettingsAppController] to the pages.
class SettingsAppScope extends InheritedNotifier<SettingsAppController> {
  const SettingsAppScope({
    required SettingsAppController super.notifier,
    required super.child,
    super.key,
  });

  static SettingsAppController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SettingsAppScope>();
    assert(scope != null, 'SettingsAppScope is missing above this context');
    return scope!.notifier!;
  }
}
