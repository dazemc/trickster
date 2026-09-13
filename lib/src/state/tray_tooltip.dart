import 'package:flutter/widgets.dart';

import '../layout/system_bar.dart';
import '../platform/layer_shell.dart';
import '../theme/accent.dart';

/// One visible tray tooltip: the label to paint, where the hovered item sat,
/// and the overlay surface hosting it.
@immutable
class TrayTooltipSession {
  const TrayTooltipSession({
    required this.viewId,
    required this.itemId,
    required this.label,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  /// The Flutter view of the overlay surface hosting this tooltip.
  final int viewId;
  final String itemId;
  final String label;
  final WallpaperAccent accent;

  /// Hovered item center in the bar surface's coordinate space.
  final Offset click;
  final SystemBarSide side;
  final double thickness;
}

/// Owns the tooltip lifecycle: it opens a click-through overlay surface on
/// the bar's output, retargets it as hover moves between items, and destroys
/// it when the pointer leaves. The strip surface never changes size.
class TrayTooltipController extends ChangeNotifier {
  TrayTooltipController({required LayerShell layerShell})
    : _layerShell = layerShell;

  final LayerShell _layerShell;
  final Set<int> _tooltipViewIds = <int>{};
  TrayTooltipSession? _session;
  var _generation = 0;

  TrayTooltipSession? get session => _session;
  bool get isOpen => _session != null;

  /// Whether [viewId] belongs to a tooltip surface (open or closing). Kept
  /// until the view is gone so the surface never renders a strip mid-teardown.
  bool isTooltipView(int viewId) => _tooltipViewIds.contains(viewId);

  /// Shows [label] for [itemId] near the hovered item. A surface already
  /// open on the same edge is retargeted in place, so moving between tray
  /// items never churns Wayland surfaces.
  Future<void> show({
    required int barViewId,
    required String itemId,
    required String label,
    required WallpaperAccent accent,
    required Offset click,
    required SystemBarSide side,
    required double thickness,
  }) async {
    final existing = _session;
    if (existing != null) {
      if (existing.itemId == itemId && existing.label == label) {
        return;
      }
      if (existing.side == side) {
        _session = TrayTooltipSession(
          viewId: existing.viewId,
          itemId: itemId,
          label: label,
          accent: accent,
          click: click,
          side: side,
          thickness: thickness,
        );
        notifyListeners();
        return;
      }
    }
    final generation = ++_generation;
    if (existing != null) {
      _session = null;
      notifyListeners();
      await _layerShell.closeTooltipSurface(viewId: existing.viewId);
    }
    final viewId = await _layerShell.openTooltipSurface(
      barViewId: barViewId,
      side: side.name,
    );
    if (viewId == null || generation != _generation) {
      if (viewId != null) {
        await _layerShell.closeTooltipSurface(viewId: viewId);
      }
      return;
    }
    _tooltipViewIds.add(viewId);
    _session = TrayTooltipSession(
      viewId: viewId,
      itemId: itemId,
      label: label,
      accent: accent,
      click: click,
      side: side,
      thickness: thickness,
    );
    notifyListeners();
    await _layerShell.showTooltipSurface(viewId: viewId);
  }

  /// Dismisses the tooltip. When [itemId] names the hovered item the request
  /// is ignored otherwise, so a stale exit cannot hide a newer tooltip.
  Future<void> close({String? itemId}) async {
    final session = _session;
    if (session == null || (itemId != null && session.itemId != itemId)) {
      return;
    }
    _session = null;
    _generation += 1;
    notifyListeners();
    await _layerShell.closeTooltipSurface(viewId: session.viewId);
  }

  /// Drops remembered surfaces that no longer exist on the engine.
  void retainViews(Set<int> viewIds) {
    _tooltipViewIds.retainWhere(viewIds.contains);
  }
}

/// Exposes the [TrayTooltipController] to the strip and tooltip surfaces.
class TrayTooltipScope extends InheritedNotifier<TrayTooltipController> {
  const TrayTooltipScope({
    required TrayTooltipController super.notifier,
    required super.child,
    super.key,
  });

  static TrayTooltipController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TrayTooltipScope>()
        ?.notifier;
  }
}
