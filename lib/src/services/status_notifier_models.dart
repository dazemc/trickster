import 'package:flutter/foundation.dart';

/// StatusNotifier item status, in ascending attention order.
enum SystemTrayStatus { passive, active, needsAttention }

/// Item interactions the host can invoke.
enum SystemTrayAction { activate, secondaryActivate, contextMenu }

/// How a menu entry toggles, mirroring `com.canonical.dbusmenu`.
enum SystemTrayMenuToggleType { none, checkmark, radio }

/// One parsed `com.canonical.dbusmenu` layout entry.
@immutable
class SystemTrayMenuEntry {
  const SystemTrayMenuEntry({
    required this.id,
    required this.label,
    required this.enabled,
    required this.visible,
    required this.separator,
    required this.toggleType,
    required this.toggleState,
    required this.destructive,
    required this.children,
  });

  final int id;
  final String label;
  final bool enabled;
  final bool visible;
  final bool separator;
  final SystemTrayMenuToggleType toggleType;
  final int toggleState;
  final bool destructive;
  final List<SystemTrayMenuEntry> children;

  @override
  bool operator ==(Object other) {
    return other is SystemTrayMenuEntry &&
        other.id == id &&
        other.label == label &&
        other.enabled == enabled &&
        other.visible == visible &&
        other.separator == separator &&
        other.toggleType == toggleType &&
        other.toggleState == toggleState &&
        other.destructive == destructive &&
        listEquals(other.children, children);
  }

  @override
  int get hashCode => Object.hash(
    id,
    label,
    enabled,
    visible,
    separator,
    toggleType,
    toggleState,
    destructive,
    Object.hashAll(children),
  );
}

/// A decoded, premultiplied RGBA icon at display size.
@immutable
class SystemTrayIconPixmap {
  // The digest is derived from the bytes, so this cannot be const.
  // ignore: prefer_const_constructors_in_immutables
  SystemTrayIconPixmap({
    required this.width,
    required this.height,
    required this.rgba,
  }) : digest = _digestBytes(rgba);

  /// Test seam for forcing a digest collision.
  @visibleForTesting
  const SystemTrayIconPixmap.withDigest({
    required this.width,
    required this.height,
    required this.rgba,
    required this.digest,
  });

  final int width;
  final int height;

  /// Premultiplied RGBA8888 pixels in row-major order.
  final Uint8List rgba;

  /// 32-bit FNV-1a digest computed once, so an unchanged icon's equality
  /// check does not rescan its pixels.
  final int digest;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! SystemTrayIconPixmap ||
        other.width != width ||
        other.height != height ||
        other.rgba.lengthInBytes != rgba.lengthInBytes) {
      return false;
    }
    if (other.digest != digest) {
      return false;
    }
    // A digest match is only a candidate; collisions still compare bytes.
    return listEquals(other.rgba, rgba);
  }

  @override
  int get hashCode => Object.hash(width, height, digest);

  static int _digestBytes(Uint8List bytes) {
    var hash = 0x811c9dc5;
    for (var index = 0; index < bytes.length; index++) {
      hash ^= bytes[index];
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

/// One StatusNotifier item tracked by the host.
@immutable
class SystemTrayItem {
  const SystemTrayItem({
    required this.id,
    required this.title,
    required this.status,
    required this.iconName,
    required this.iconThemePath,
    required this.iconPixmap,
    required this.menuAvailable,
    required this.primaryOpensMenu,
    this.menuPath = '',
  });

  final String id;
  final String title;
  final SystemTrayStatus status;
  final String iconName;
  final String iconThemePath;
  final SystemTrayIconPixmap? iconPixmap;
  final bool menuAvailable;
  final bool primaryOpensMenu;
  final String menuPath;

  @override
  bool operator ==(Object other) {
    return other is SystemTrayItem &&
        other.id == id &&
        other.title == title &&
        other.status == status &&
        other.iconName == iconName &&
        other.iconThemePath == iconThemePath &&
        other.iconPixmap == iconPixmap &&
        other.menuAvailable == menuAvailable &&
        other.primaryOpensMenu == primaryOpensMenu &&
        other.menuPath == menuPath;
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    status,
    iconName,
    iconThemePath,
    iconPixmap,
    menuAvailable,
    primaryOpensMenu,
    menuPath,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'status': status.name,
    'iconName': iconName,
    'iconThemePath': iconThemePath,
    'menuAvailable': menuAvailable,
    'primaryOpensMenu': primaryOpensMenu,
    'menuPath': menuPath,
  };

  /// Icon pixmap bytes are presentational and not serialized.
  static SystemTrayItem fromJson(Map<String, dynamic> json) => SystemTrayItem(
    id: '${json['id']}',
    title: '${json['title']}',
    status: _statusFromName('${json['status']}'),
    iconName: '${json['iconName']}',
    iconThemePath: '${json['iconThemePath']}',
    iconPixmap: null,
    menuAvailable: (json['menuAvailable'] as bool?) ?? false,
    primaryOpensMenu: (json['primaryOpensMenu'] as bool?) ?? false,
    menuPath: '${json['menuPath']}',
  );
}

SystemTrayStatus _statusFromName(String value) {
  for (final status in SystemTrayStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  return SystemTrayStatus.active;
}
