import 'dart:async';

import 'package:flutter/material.dart'
    show
        ButtonStyle,
        Divider,
        MenuAnchor,
        MenuController,
        MenuItemButton,
        MenuStyle,
        RoundedRectangleBorder,
        SubmenuButton,
        WidgetStatePropertyAll;
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/state/tray_bloc.dart';
import 'package:trickster/src/state/tray_menu.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

/// The contents of one tray menu surface: a fullscreen transparent overlay
/// with the panel anchored at the strip's inner edge. Material's tap-region
/// dismissal covers the whole output because the surface does.
class TrayMenuSurface extends StatefulWidget {
  const TrayMenuSurface({
    required this.session,
    required this.controller,
    super.key,
  });

  final TrayMenuSession session;
  final TrayMenuController controller;

  @override
  State<TrayMenuSurface> createState() => _TrayMenuSurfaceState();
}

class _TrayMenuSurfaceState extends State<TrayMenuSurface> {
  final MenuController _menuController = MenuController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'tray-menu');
  late final TrayBloc _trayBloc;

  @override
  void initState() {
    super.initState();
    // Read the bloc up front: selection runs after the menu has closed and
    // this widget may already be deactivated by then.
    _trayBloc = context.read<TrayBloc>();
    // The anchor needs one layout pass before the panel can be positioned.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _menuController.open(position: Offset.zero);
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(widget.controller.close());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The strip's inner edge at the click's cross position, in output
  /// coordinates. Material's edge clamping flips the panel for bars on the
  /// bottom or right.
  Offset _anchor(Size size) {
    final session = widget.session;
    return switch (session.side) {
      SystemBarSide.top => Offset(session.click.dx, session.thickness),
      SystemBarSide.bottom => Offset(
        session.click.dx,
        size.height - session.thickness,
      ),
      SystemBarSide.left => Offset(session.thickness, session.click.dy),
      SystemBarSide.right => Offset(
        size.width - session.thickness,
        session.click.dy,
      ),
      SystemBarSide.hidden => session.click,
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final anchor = _anchor(MediaQuery.sizeOf(context));
    // Opaque so presses in the empty area reach the tap-region surface and
    // dismiss the panel.
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: anchor.dx,
            top: anchor.dy,
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              child: MenuAnchor(
                controller: _menuController,
                consumeOutsideTap: true,
                style: _menuStyle(context, session.accent),
                onClose: () => unawaited(widget.controller.close()),
                menuChildren: _buildMenuChildren(
                  context,
                  session.accent,
                  session.entries,
                ),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activate(SystemTrayMenuEntry entry) async {
    final controller = widget.controller;
    await _trayBloc.activateMenuEntry(widget.session.item, entry.id);
    await controller.close();
  }

  List<Widget> _buildMenuChildren(
    BuildContext context,
    WallpaperAccent accent,
    List<SystemTrayMenuEntry> entries,
  ) {
    final output = <Widget>[];
    for (final entry in entries.where((entry) => entry.visible)) {
      if (entry.separator) {
        output.add(
          const Divider(
            height: 9,
            thickness: 1,
            indent: 8,
            endIndent: 8,
            color: ShellMediaColors.glassSurface,
          ),
        );
        continue;
      }
      final label = entry.label.isEmpty
          ? context.l10n.trayMenuUntitled
          : entry.label;
      final children = _buildMenuChildren(context, accent, entry.children);
      final style = _menuButtonStyle(
        accent: accent,
        enabled: entry.enabled,
        destructive: entry.destructive,
      );
      final child = Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
      if (children.isNotEmpty && entry.enabled) {
        output.add(
          SubmenuButton(
            style: style,
            menuStyle: _menuStyle(context, accent),
            leadingIcon: _toggleIndicator(entry),
            menuChildren: children,
            child: child,
          ),
        );
        continue;
      }
      output.add(
        MenuItemButton(
          style: style,
          leadingIcon: _toggleIndicator(entry),
          onPressed: entry.enabled && entry.id > 0
              ? () => unawaited(_activate(entry))
              : null,
          child: child,
        ),
      );
    }
    return output;
  }

  MenuStyle _menuStyle(BuildContext context, WallpaperAccent accent) {
    final viewHeight = MediaQuery.sizeOf(context).height;
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll<Color>(accent.cardFill()),
      surfaceTintColor: const WidgetStatePropertyAll<Color>(
        ShellMediaColors.transparentDark,
      ),
      shadowColor: const WidgetStatePropertyAll<Color>(Color(0x88000000)),
      elevation: const WidgetStatePropertyAll<double>(10),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(164, 0)),
      maximumSize: WidgetStatePropertyAll<Size>(
        Size(320, (viewHeight - 16).clamp(120, 560).toDouble()),
      ),
    );
  }

  ButtonStyle _menuButtonStyle({
    required WallpaperAccent accent,
    required bool enabled,
    required bool destructive,
  }) {
    final color = !enabled
        ? ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.45)
        : destructive
        ? ShellTelemetryColors.danger
        : ShellMediaColors.lightForeground;
    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll<Color>(color),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        ShellText.systemBarValue.copyWith(color: color),
      ),
      overlayColor: WidgetStatePropertyAll<Color>(
        accent.color.withValues(alpha: 0.10),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(160, 28)),
    );
  }

  Widget? _toggleIndicator(SystemTrayMenuEntry entry) {
    if (entry.toggleType == SystemTrayMenuToggleType.none) {
      return null;
    }
    final color = entry.enabled
        ? ShellMediaColors.lightForeground
        : ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.45);
    final checked = entry.toggleState == 1;
    final icon = switch (entry.toggleType) {
      SystemTrayMenuToggleType.checkmark => checked ? LucideIcons.check : null,
      SystemTrayMenuToggleType.radio =>
        checked ? LucideIcons.circleDot : LucideIcons.circle,
      SystemTrayMenuToggleType.none => null,
    };
    return SizedBox.square(
      dimension: 12,
      child: icon == null
          ? const SizedBox.shrink()
          : Icon(icon, size: 12, color: color),
    );
  }
}
