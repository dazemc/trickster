import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart'
    show
        ButtonStyle,
        MenuAnchor,
        MenuController,
        MenuItemButton,
        MenuStyle,
        RoundedRectangleBorder,
        WidgetStatePropertyAll;
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/state/bar_menu_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

/// The contents of one bar menu surface: a fullscreen transparent overlay
/// with a small glass panel anchored at the empty strip area that was
/// right-clicked. Material's tap-region dismissal covers the whole output
/// because the surface does. Pressing Escape dismisses it too.
class BarMenuSurface extends StatefulWidget {
  const BarMenuSurface({required this.session, super.key});

  final BarMenuSession session;

  @override
  State<BarMenuSurface> createState() => _BarMenuSurfaceState();
}

class _BarMenuSurfaceState extends State<BarMenuSurface> {
  final MenuController _menuController = MenuController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'bar-menu');
  var _selected = false;

  @override
  void initState() {
    super.initState();
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

  void _dismiss() => context.read<BarMenuBloc>().add(const BarMenuDismissed());

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Selects once; the bloc dismisses the surface before starting the
  /// settings process, so a second tap can neither relaunch nor reopen.
  void _selectSettings() {
    if (_selected) {
      return;
    }
    _selected = true;
    context.read<BarMenuBloc>().add(const BarMenuSettingsSelected());
  }

  /// The strip's inner edge at the click's cross position, in output
  /// coordinates; mirrors the tray menu's anchor.
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
    final l10n = context.l10n;
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
              key: const ValueKey<String>('bar-menu-focus'),
              focusNode: _focusNode,
              onKeyEvent: _handleKeyEvent,
              child: MenuAnchor(
                controller: _menuController,
                consumeOutsideTap: true,
                style: _menuStyle(context, session.accent),
                onClose: _dismiss,
                menuChildren: [
                  MenuItemButton(
                    key: const ValueKey<String>('bar-menu-settings'),
                    style: _menuButtonStyle(session.accent),
                    // The bloc owns the dismissal order: close first, then
                    // launch. Letting Material close the overlay first would
                    // drop the session before the selection reaches the bloc.
                    closeOnActivate: false,
                    leadingIcon: const Icon(
                      LucideIcons.settings,
                      size: 13,
                      color: ShellMediaColors.lightForeground,
                    ),
                    onPressed: _selectSettings,
                    child: Text(
                      l10n.barMenuSettings,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The tray menu's panel language: compact, rounded, accent-tinted card
  /// fill with a soft shadow, clamped inside the output.
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

  ButtonStyle _menuButtonStyle(WallpaperAccent accent) {
    return ButtonStyle(
      foregroundColor: const WidgetStatePropertyAll<Color>(
        ShellMediaColors.lightForeground,
      ),
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        ShellText.systemBarValue,
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
}

/// Opens the bar menu with the accent the strip resolved, so the panel glass
/// matches the pills on that output.
void openBarMenu({
  required BuildContext context,
  required WallpaperAccent accent,
  required Offset click,
  required SystemBarSide side,
  required double thickness,
}) {
  final menu = context.read<BarMenuBloc>();
  // A fullscreen overlay already owns the pointer; ignore duplicate events
  // instead of stacking a second native surface.
  if (menu.state.isOpen) {
    return;
  }
  menu.add(
    BarMenuRequested(
      barViewId: View.of(context).viewId,
      accent: accent,
      click: click,
      side: side,
      thickness: thickness,
    ),
  );
}
