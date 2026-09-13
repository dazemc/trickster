import 'package:flutter/widgets.dart';

/// Whether pill cards sit on a compositor-blurred backdrop. Absent means
/// false, so widget tests and hosts without the protocol keep opaque fills.
class BackdropBlur extends InheritedWidget {
  const BackdropBlur({required this.enabled, required super.child, super.key});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackdropBlur>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(BackdropBlur oldWidget) =>
      oldWidget.enabled != enabled;
}
