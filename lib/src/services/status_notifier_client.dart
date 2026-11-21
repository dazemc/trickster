import 'dart:async';
import 'dart:ui' show Offset;

import 'package:trickster/src/services/status_notifier_models.dart';

/// The tray surface shared by the local service and, later, a worker proxy.
///
/// Implementations expose item snapshots and the cached list, accept item
/// actions, menu reads, menu clicks, and dispose. The interface names no D-Bus
/// type so the UI can depend on it without constructing a client.
abstract interface class StatusNotifierClient {
  Stream<List<SystemTrayItem>> get snapshots;

  List<SystemTrayItem> get current;

  Future<void> start();

  Future<bool> invoke(
    SystemTrayItem item,
    SystemTrayAction action,
    Offset position,
  );

  Future<List<SystemTrayMenuEntry>?> loadMenu(SystemTrayItem item);

  Future<bool> activateMenuEntry(SystemTrayItem item, int entryId);

  Future<void> dispose();
}
