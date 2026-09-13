import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Opens the focused tray item's context menu. Registered by
/// `TrayItemButton`; bound by the shell keymap below.
class TrayMenuIntent extends Intent {
  const TrayMenuIntent();
}

/// The shell keymap: `WidgetsApp`'s defaults plus the tray menu keys.
///
/// The bar has no `WidgetsApp`, so the app root installs this map by hand
/// (Tab and arrow traversal, Enter/Space activation, Escape dismissal), and
/// the Menu key or Shift+F10 opens the focused tray item's context menu.
final Map<ShortcutActivator, Intent> shellShortcuts =
    <ShortcutActivator, Intent>{
      ...WidgetsApp.defaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.contextMenu):
          const TrayMenuIntent(),
      const SingleActivator(LogicalKeyboardKey.f10, shift: true):
          const TrayMenuIntent(),
    };
