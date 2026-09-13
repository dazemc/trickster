import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../layout/system_bar.dart';
import '../locale.dart';
import '../services/status_notifier.dart';
import '../state/tray_bloc.dart';
import '../state/tray_menu.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class TrayPill extends StatelessWidget {
  const TrayPill({
    required this.accent,
    required this.items,
    required this.onActivate,
    this.side = SystemBarSide.top,
    this.thickness = 32,
    super.key,
  });

  final WallpaperAccent accent;
  final List<SystemTrayItem> items;
  final void Function(SystemTrayItem item, Offset position) onActivate;

  /// Which edge the strip sits on; menus open toward the output's interior.
  final SystemBarSide side;

  /// Cross-axis size of the strip band, used to keep menus off the bar.
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return SystemBarCard(
      accent: accent,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            TrayItemButton(
              key: ValueKey<String>('tray-item-${items[i].id}'),
              accent: accent,
              item: items[i],
              onActivate: onActivate,
              side: side,
              thickness: thickness,
            ),
          ],
        ],
      ),
    );
  }
}

class TrayItemButton extends StatefulWidget {
  const TrayItemButton({
    required this.accent,
    required this.item,
    required this.onActivate,
    this.side = SystemBarSide.top,
    this.thickness = 32,
    super.key,
  });

  static const double hitExtent = 22;
  static const double iconExtent = 18;

  final WallpaperAccent accent;
  final SystemTrayItem item;
  final void Function(SystemTrayItem item, Offset position) onActivate;
  final SystemBarSide side;
  final double thickness;

  @override
  State<TrayItemButton> createState() => _TrayItemButtonState();
}

class _TrayItemButtonState extends State<TrayItemButton> {
  Offset? _primaryPosition;

  Offset _center() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return Offset.zero;
    }
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Future<void> _openContextMenu(Offset position) async {
    final menu = TrayMenuScope.maybeOf(context);
    final bloc = context.read<TrayBloc>();
    if (menu == null) {
      await bloc.invoke(widget.item, SystemTrayAction.contextMenu, position);
      return;
    }
    if (menu.isOpen) {
      await menu.close();
      return;
    }
    final entries = await bloc.loadMenu(widget.item);
    if (!mounted) {
      return;
    }
    final visible = entries
        ?.where((entry) => entry.visible)
        .toList(growable: false);
    if (visible == null || visible.isEmpty) {
      await bloc.invoke(widget.item, SystemTrayAction.contextMenu, position);
      return;
    }
    final opened = await menu.show(
      barViewId: View.of(context).viewId,
      item: widget.item,
      entries: visible,
      accent: widget.accent,
      click: position,
      side: widget.side,
      thickness: widget.thickness,
    );
    if (!opened) {
      await bloc.invoke(widget.item, SystemTrayAction.contextMenu, position);
    }
  }

  Future<void> _activatePrimary(Offset position) async {
    if (widget.item.primaryOpensMenu) {
      await _openContextMenu(position);
      return;
    }
    widget.onActivate(widget.item, position);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final attention = item.status == SystemTrayStatus.needsAttention;
    final passive = item.status == SystemTrayStatus.passive;
    final l10n = context.l10n;
    final label = item.title.isNotEmpty
        ? item.title
        : item.iconName.isNotEmpty
        ? item.iconName
        : l10n.trayItemFallbackLabel;
    return Semantics(
      button: true,
      label: label,
      value: switch (item.status) {
        SystemTrayStatus.passive => l10n.trayStatusPassive,
        SystemTrayStatus.active => l10n.trayStatusActive,
        SystemTrayStatus.needsAttention => l10n.trayStatusNeedsAttention,
      },
      onTap: () => unawaited(_activatePrimary(_center())),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _primaryPosition = details.globalPosition,
          onTap: () =>
              unawaited(_activatePrimary(_primaryPosition ?? _center())),
          onSecondaryTapDown: (details) =>
              unawaited(_openContextMenu(details.globalPosition)),
          child: SizedBox.square(
            dimension: TrayItemButton.hitExtent,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Opacity(
                    opacity: passive ? 0.52 : 1,
                    child: RepaintBoundary(
                      child: SizedBox.square(
                        dimension: TrayItemButton.iconExtent,
                        child: _TrayIcon(item: item),
                      ),
                    ),
                  ),
                ),
                if (attention)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.accent.color,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 4),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrayIcon extends StatelessWidget {
  const _TrayIcon({required this.item});

  final SystemTrayItem item;

  @override
  Widget build(BuildContext context) {
    final pixmap = item.iconPixmap;
    return pixmap == null
        ? const _TrayIconPlaceholder()
        : _RawTrayIcon(pixmap: pixmap);
  }
}

class _RawTrayIcon extends StatefulWidget {
  const _RawTrayIcon({required this.pixmap});

  final SystemTrayIconPixmap pixmap;

  @override
  State<_RawTrayIcon> createState() => _RawTrayIconState();
}

class _RawTrayIconState extends State<_RawTrayIcon> {
  ui.Image? _decoded;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void didUpdateWidget(covariant _RawTrayIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pixmap.width != widget.pixmap.width ||
        oldWidget.pixmap.height != widget.pixmap.height ||
        !listEquals(oldWidget.pixmap.rgba, widget.pixmap.rgba)) {
      unawaited(_decode());
    }
  }

  Future<void> _decode() async {
    final generation = ++_generation;
    final pixmap = widget.pixmap;
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(pixmap.rgba);
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: pixmap.width,
        height: pixmap.height,
        rowBytes: pixmap.width * 4,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      codec = await descriptor.instantiateCodec();
      decoded = (await codec.getNextFrame()).image;
    } on Object {
      decoded?.dispose();
      decoded = null;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
    if (!mounted || generation != _generation) {
      decoded?.dispose();
      return;
    }
    final previous = _decoded;
    setState(() => _decoded = decoded);
    previous?.dispose();
  }

  @override
  void dispose() {
    _generation += 1;
    _decoded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _decoded;
    if (image == null) {
      return const _TrayIconPlaceholder();
    }
    return RawImage(
      image: image,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _TrayIconPlaceholder extends StatelessWidget {
  const _TrayIconPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        border: Border.all(
          color: ShellMediaColors.lightForegroundSecondary.withValues(
            alpha: 0.5,
          ),
        ),
      ),
    );
  }
}
