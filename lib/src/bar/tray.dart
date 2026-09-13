import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/status_notifier.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class TrayPill extends StatelessWidget {
  const TrayPill({
    required this.accent,
    required this.items,
    required this.onActivate,
    super.key,
  });

  final WallpaperAccent accent;
  final List<SystemTrayItem> items;
  final void Function(SystemTrayItem item, Offset position) onActivate;

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
    super.key,
  });

  static const double hitExtent = 22;
  static const double iconExtent = 18;

  final WallpaperAccent accent;
  final SystemTrayItem item;
  final void Function(SystemTrayItem item, Offset position) onActivate;

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

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final attention = item.status == SystemTrayStatus.needsAttention;
    final passive = item.status == SystemTrayStatus.passive;
    final label = item.title.isNotEmpty
        ? item.title
        : item.iconName.isNotEmpty
        ? item.iconName
        : 'System tray';
    return Semantics(
      button: true,
      label: label,
      value: _statusSemantics(item.status),
      onTap: () => widget.onActivate(item, _center()),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _primaryPosition = details.globalPosition,
          onTap: () => widget.onActivate(item, _primaryPosition ?? _center()),
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

String _statusSemantics(SystemTrayStatus status) => switch (status) {
  SystemTrayStatus.passive => 'Passive',
  SystemTrayStatus.active => 'Active',
  SystemTrayStatus.needsAttention => 'Needs attention',
};
