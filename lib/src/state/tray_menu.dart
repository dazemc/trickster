import 'package:flutter/widgets.dart';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/theme/accent.dart';

/// One open tray menu: the entries to render, where the strip was clicked,
/// and the overlay surface hosting the panel.
@immutable
class TrayMenuSession {
  const TrayMenuSession({
    required this.viewId,
    required this.item,
    required this.entries,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  /// The Flutter view of the overlay surface hosting this menu.
  final int viewId;
  final SystemTrayItem item;
  final List<SystemTrayMenuEntry> entries;
  final WallpaperAccent accent;

  /// Click position in the bar surface's coordinate space.
  final Offset click;
  final SystemBarSide side;
  final double thickness;
}

/// Owns the menu lifecycle: it opens a fullscreen overlay surface on the
/// bar's output, hands the session to the menu view, and destroys the
/// surface on dismissal. The bar's own surface never changes size, so an
/// open menu cannot stretch the strip.
class TrayMenuController extends ChangeNotifier {
  TrayMenuController({required LayerShell layerShell})
    : _layerShell = layerShell;

  final LayerShell _layerShell;
  final Set<int> _menuViewIds = <int>{};
  TrayMenuSession? _session;
  var _generation = 0;

  TrayMenuSession? get session => _session;
  bool get isOpen => _session != null;

  /// Whether [viewId] belongs to a menu surface (open or closing). Kept until
  /// the view is gone so the surface never renders a bar strip mid-teardown.
  bool isMenuView(int viewId) => _menuViewIds.contains(viewId);

  /// Opens [entries] for [item] on the bar surface [barViewId]. Returns false
  /// when the overlay surface could not be created.
  Future<bool> show({
    required int barViewId,
    required SystemTrayItem item,
    required List<SystemTrayMenuEntry> entries,
    required WallpaperAccent accent,
    required Offset click,
    required SystemBarSide side,
    required double thickness,
  }) async {
    final generation = ++_generation;
    final previous = _session;
    if (previous != null) {
      _session = null;
      notifyListeners();
      await _layerShell.closeMenuSurface(viewId: previous.viewId);
    }
    final viewId = await _layerShell.openMenuSurface(
      barViewId: barViewId,
      side: side.name,
    );
    if (viewId == null || generation != _generation) {
      if (viewId != null) {
        await _layerShell.closeMenuSurface(viewId: viewId);
      }
      return false;
    }
    _menuViewIds.add(viewId);
    _session = TrayMenuSession(
      viewId: viewId,
      item: item,
      entries: entries,
      accent: accent,
      click: click,
      side: side,
      thickness: thickness,
    );
    notifyListeners();
    await _layerShell.showMenuSurface(viewId: viewId);
    return true;
  }

  /// Dismisses the open menu and destroys its surface. Safe to call twice.
  Future<void> close() async {
    final session = _session;
    _session = null;
    _generation += 1;
    if (session != null) {
      notifyListeners();
      await _layerShell.closeMenuSurface(viewId: session.viewId);
    }
  }

  /// Drops remembered surfaces that no longer exist on the engine.
  void retainViews(Set<int> viewIds) {
    _menuViewIds.retainWhere(viewIds.contains);
  }
}

/// Exposes the [TrayMenuController] to the strip and to menu surfaces.
class TrayMenuScope extends InheritedNotifier<TrayMenuController> {
  const TrayMenuScope({
    required TrayMenuController super.notifier,
    required super.child,
    super.key,
  });

  static TrayMenuController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TrayMenuScope>()
        ?.notifier;
  }
}
