#include "my_application.h"

#include <gdk/gdkwayland.h>

#include "ext-background-effect-v1-client-protocol.h"

#include <gtk-layer-shell.h>
#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

typedef struct {
  GtkWindow* window;
  FlView* view;
  GdkMonitor* monitor;
  struct ext_background_effect_surface_v1* blur;
} TricksterSurface;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlEngine* engine;
  GPtrArray* surfaces;
  GPtrArray* menus;
  gboolean blur_checked;
  gboolean blur_supported;
  struct wl_compositor* compositor;
  struct ext_background_effect_manager_v1* blur_manager;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void trickster_surface_free(gpointer data) {
  g_free(data);
}

static int trickster_layer(const gchar* value) {
  if (g_strcmp0(value, "background") == 0) {
    return GTK_LAYER_SHELL_LAYER_BACKGROUND;
  }
  if (g_strcmp0(value, "bottom") == 0) {
    return GTK_LAYER_SHELL_LAYER_BOTTOM;
  }
  if (g_strcmp0(value, "overlay") == 0) {
    return GTK_LAYER_SHELL_LAYER_OVERLAY;
  }
  return GTK_LAYER_SHELL_LAYER_TOP;
}

static int trickster_keyboard(const gchar* value) {
  if (g_strcmp0(value, "none") == 0) {
    return GTK_LAYER_SHELL_KEYBOARD_MODE_NONE;
  }
  if (g_strcmp0(value, "exclusive") == 0) {
    return GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE;
  }
  return GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND;
}

static void apply_layer_shell(TricksterSurface* surface, const gchar* side,
                              gint thickness, const gchar* layer,
                              const gchar* name, const gchar* keyboard) {
  if (!gtk_layer_is_supported()) {
    return;
  }
  GtkWindow* window = surface->window;
  gtk_layer_set_layer(window, (GtkLayerShellLayer)trickster_layer(layer));
  gtk_layer_set_namespace(window, name != nullptr ? name : "trickster");
  gtk_layer_set_keyboard_mode(
      window, (GtkLayerShellKeyboardMode)trickster_keyboard(keyboard));
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP,
                       g_strcmp0(side, "top") == 0);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM,
                       g_strcmp0(side, "bottom") == 0);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT,
                       g_strcmp0(side, "left") == 0 ||
                           g_strcmp0(side, "top") == 0 ||
                           g_strcmp0(side, "bottom") == 0);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT,
                       g_strcmp0(side, "right") == 0 ||
                           g_strcmp0(side, "top") == 0 ||
                           g_strcmp0(side, "bottom") == 0);
  // The exclusive zone always equals the strip. Menus never resize this
  // surface: they live on their own overlay surfaces, so the strip cannot be
  // stretched by a resize while an old frame is still current.
  gtk_layer_set_exclusive_zone(window, thickness);
  if (g_strcmp0(side, "left") == 0 || g_strcmp0(side, "right") == 0) {
    gtk_widget_set_size_request(GTK_WIDGET(window), thickness, -1);
  } else {
    gtk_widget_set_size_request(GTK_WIDGET(window), -1, thickness);
  }
  // gtk-layer-shell's documented way to apply a changed size request: the
  // request on axes anchored to opposite edges is ignored, and the resize
  // hint must stay bogus so GTK does not allocate an intermediate size.
  gtk_window_resize(window, 1, 1);
}

struct _MyApplication;
typedef struct {
  struct wl_output* proxy;
  gchar* name;
  gint x;
  gint y;
} TricksterOutputInfo;

static void output_info_free(gpointer data) {
  TricksterOutputInfo* info = (TricksterOutputInfo*)data;
  if (info->proxy != nullptr) {
    wl_output_destroy(info->proxy);
  }
  g_free(info->name);
  g_free(info);
}

static void output_name_cb(void* data, struct wl_output* output,
                           const char* name) {
  TricksterOutputInfo* info = (TricksterOutputInfo*)data;
  g_free(info->name);
  info->name = g_strdup(name);
}

static void output_geometry_cb(void* data, struct wl_output* output, gint32 x,
                               gint32 y, gint32 physical_width,
                               gint32 physical_height, gint32 subpixel,
                               const char* make, const char* model,
                               gint32 transform) {
  TricksterOutputInfo* info = (TricksterOutputInfo*)data;
  info->x = x;
  info->y = y;
}

static void output_mode_cb(void* data, struct wl_output* output, guint32 flags,
                           gint32 width, gint32 height, gint32 refresh) {}

static void output_scale_cb(void* data, struct wl_output* output, gint32 factor) {
}

static void output_done_cb(void* data, struct wl_output* output) {}

static void output_description_cb(void* data, struct wl_output* output,
                                  const char* description) {}

static const struct wl_output_listener output_listener = {
    output_geometry_cb, output_mode_cb,     output_done_cb,
    output_scale_cb,    output_name_cb,     output_description_cb};

static void output_registry_global(void* data, struct wl_registry* registry,
                                   uint32_t name, const char* interface,
                                   uint32_t version) {
  if (g_strcmp0(interface, wl_output_interface.name) != 0) {
    return;
  }
  GPtrArray* outputs = (GPtrArray*)data;
  TricksterOutputInfo* info = g_new0(TricksterOutputInfo, 1);
  info->proxy = (struct wl_output*)wl_registry_bind(
      registry, name, &wl_output_interface, MIN(version, 4));
  wl_output_add_listener(info->proxy, &output_listener, info);
  g_ptr_array_add(outputs, info);
}

static void output_registry_global_remove(void* data,
                                          struct wl_registry* registry,
                                          uint32_t name) {}

// The connector name (HDMI-A-1) of [monitor], or null. GDK only exposes the
// EDID model, so the name comes from a fresh wl_output enumeration matched
// by compositor-space position.
static gchar* trickster_connector_for_monitor(GdkMonitor* monitor) {
  if (monitor == nullptr) {
    return nullptr;
  }
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_WAYLAND_DISPLAY(display)) {
    return nullptr;
  }
  struct wl_display* wl = gdk_wayland_display_get_wl_display(display);
  if (wl == nullptr) {
    return nullptr;
  }
  struct wl_registry* registry = wl_display_get_registry(wl);
  if (registry == nullptr) {
    return nullptr;
  }
  g_autoptr(GPtrArray) outputs =
      g_ptr_array_new_with_free_func(output_info_free);
  static const struct wl_registry_listener listener = {
      output_registry_global, output_registry_global_remove};
  wl_registry_add_listener(registry, &listener, outputs);
  wl_display_roundtrip(wl);
  wl_display_roundtrip(wl);
  wl_registry_destroy(registry);

  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);
  for (guint i = 0; i < outputs->len; i++) {
    TricksterOutputInfo* info =
        (TricksterOutputInfo*)g_ptr_array_index(outputs, i);
    if (info->name != nullptr && info->x == geometry.x && info->y == geometry.y) {
      return g_strdup(info->name);
    }
  }
  return nullptr;
}

static void blur_registry_global(void* data, struct wl_registry* registry,
                                 uint32_t name, const char* interface,
                                 uint32_t version);
static void blur_registry_global_remove(void* data, struct wl_registry* registry,
                                        uint32_t name);
static gboolean trickster_probe_blur(MyApplication* self);
static void trickster_apply_blur(MyApplication* self, TricksterSurface* surface,
                                 gboolean enabled);

static void blur_registry_global(void* data, struct wl_registry* registry,
                                 uint32_t name, const char* interface,
                                 uint32_t version) {
  MyApplication* self = MY_APPLICATION(data);
  if (g_strcmp0(interface, wl_compositor_interface.name) == 0) {
    if (self->compositor == nullptr) {
      self->compositor = (struct wl_compositor*)wl_registry_bind(
          registry, name, &wl_compositor_interface, MIN(version, 4));
    }
  } else if (g_strcmp0(interface,
                       ext_background_effect_manager_v1_interface.name) == 0) {
    self->blur_supported = TRUE;
    if (self->blur_manager == nullptr) {
      self->blur_manager =
          (struct ext_background_effect_manager_v1*)wl_registry_bind(
              registry, name, &ext_background_effect_manager_v1_interface, 1);
    }
  }
}

static void blur_registry_global_remove(void* data, struct wl_registry* registry,
                                        uint32_t name) {}

// One registry roundtrip on GDK's Wayland connection, binding the compositor
// and the background-effect manager; cached for the process.
static gboolean trickster_probe_blur(MyApplication* self) {
  if (self->blur_checked) {
    return self->blur_supported;
  }
  self->blur_checked = TRUE;
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_WAYLAND_DISPLAY(display)) {
    return FALSE;
  }
  struct wl_display* wl = gdk_wayland_display_get_wl_display(display);
  if (wl == nullptr) {
    return FALSE;
  }
  struct wl_registry* registry = wl_display_get_registry(wl);
  if (registry == nullptr) {
    return FALSE;
  }
  static const struct wl_registry_listener listener = {
      blur_registry_global, blur_registry_global_remove};
  wl_registry_add_listener(registry, &listener, self);
  wl_display_roundtrip(wl);
  wl_registry_destroy(registry);
  return self->blur_supported;
}

// Blurs the whole strip surface: the pills are the only opaque content, and
// the protocol takes axis-aligned rects, so the rounded card shape cannot be
// a region of its own.
static void trickster_apply_blur(MyApplication* self, TricksterSurface* surface,
                                 gboolean enabled) {
  if (self->blur_manager == nullptr || surface->window == nullptr) {
    return;
  }
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(surface->window));
  if (gdk_window == nullptr) {
    return;
  }
  struct wl_surface* wl_surface = gdk_wayland_window_get_wl_surface(gdk_window);
  if (wl_surface == nullptr) {
    return;
  }
  if (surface->blur == nullptr) {
    surface->blur = ext_background_effect_manager_v1_get_background_effect(
        self->blur_manager, wl_surface);
  }
  if (surface->blur == nullptr) {
    return;
  }
  if (!enabled) {
    ext_background_effect_surface_v1_set_blur_region(surface->blur, nullptr);
    return;
  }
  if (self->compositor == nullptr) {
    return;
  }
  struct wl_region* region = wl_compositor_create_region(self->compositor);
  if (region == nullptr) {
    return;
  }
  GtkAllocation allocation;
  gtk_widget_get_allocation(GTK_WIDGET(surface->window), &allocation);
  wl_region_add(region, 0, 0, allocation.width, allocation.height);
  ext_background_effect_surface_v1_set_blur_region(surface->blur, region);
  wl_region_destroy(region);
}

static gint64 method_arg_int(FlMethodCall* method_call, const gchar* name) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return -1;
  }
  FlValue* value = fl_value_lookup_string(args, name);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return -1;
  }
  return fl_value_get_int(value);
}

// Creates the fullscreen overlay surface hosting one tray menu. It starts
// hidden: Dart maps it after the session is ready, so the overlay never shows
// a default frame. The window's RGBA visual and transparent background match
// the strip surfaces.
//
// The surface is anchored to the edge opposite the strip and sized to the
// whole monitor: layer-shell places a surface inside the area left over by
// other surfaces' exclusive zones, so anchoring the strip's own edge would
// leave the bar band uncovered and clicks there would never dismiss the menu.
static TricksterSurface* trickster_menu_surface_new(MyApplication* self,
                                                    GdkMonitor* monitor,
                                                    const gchar* side) {
  TricksterSurface* surface = g_new0(TricksterSurface, 1);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  surface->window = window;

  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_title(window, "trickster-menu");
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }

  if (gtk_layer_is_supported()) {
    gtk_layer_init_for_window(window);
    if (monitor != nullptr) {
      gtk_layer_set_monitor(window, monitor);
    }
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_namespace(window, "trickster-menu");
    // A menu is modal: it holds the keyboard while mapped and covers the
    // output so Material's tap-region dismissal catches presses anywhere.
    gtk_layer_set_keyboard_mode(window,
                                GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
    gtk_layer_set_exclusive_zone(window, 0);
    if (g_strcmp0(side, "top") == 0) {
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    } else if (g_strcmp0(side, "bottom") == 0) {
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    } else if (g_strcmp0(side, "left") == 0) {
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    } else {
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
      gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    }
    if (monitor != nullptr) {
      GdkRectangle geometry;
      gdk_monitor_get_geometry(monitor, &geometry);
      gtk_widget_set_size_request(GTK_WIDGET(window), geometry.width,
                                  geometry.height);
      gtk_window_resize(window, 1, 1);
    }
  }

  FlView* view = fl_view_new_for_engine(self->engine);
  surface->view = view;
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  gtk_widget_realize(GTK_WIDGET(view));

  return surface;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "supported") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(gtk_layer_is_supported() ? TRUE : FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "blur") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(trickster_probe_blur(self) ? TRUE : FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "setBlur") == 0) {
    const gint64 view_id = method_arg_int(method_call, "viewId");
    gboolean enabled = FALSE;
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "enabled");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL) {
        enabled = fl_value_get_bool(value) ? TRUE : FALSE;
      }
    }
    trickster_probe_blur(self);
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* surface =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (surface->view == nullptr || fl_view_get_id(surface->view) != view_id) {
        continue;
      }
      trickster_apply_blur(self, surface, enabled);
      break;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "outputs") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* surface =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (surface->window == nullptr) {
        continue;
      }
      GdkMonitor* monitor = surface->monitor;
      if (monitor == nullptr) {
        GdkDisplay* display = gdk_display_get_default();
        if (display != nullptr) {
          monitor = gdk_display_get_primary_monitor(display);
        }
      }
      if (monitor == nullptr) {
        continue;
      }
      GdkRectangle geometry;
      gdk_monitor_get_geometry(monitor, &geometry);
      g_autofree gchar* connector = trickster_connector_for_monitor(monitor);
      const gchar* model = gdk_monitor_get_model(monitor);
      g_autoptr(FlValue) entry = fl_value_new_map();
      fl_value_set_string_take(
          entry, "name",
          fl_value_new_string(connector != nullptr ? connector
                               : model != nullptr ? model
                                                  : "output"));
      fl_value_set_string_take(entry, "width",
                               fl_value_new_int(geometry.width));
      fl_value_set_string_take(entry, "height",
                               fl_value_new_int(geometry.height));
      fl_value_set_string_take(
          entry, "viewId",
          fl_value_new_int(surface->view != nullptr
                               ? fl_view_get_id(surface->view)
                               : -1));
      fl_value_append_take(list, fl_value_ref(entry));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (g_strcmp0(method, "configure") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* side = "top";
    const gchar* layer = "top";
    const gchar* name = "trickster";
    const gchar* keyboard = "on_demand";
    gint thickness = 32;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "side");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
        side = fl_value_get_string(value);
      }
      value = fl_value_lookup_string(args, "layer");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
        layer = fl_value_get_string(value);
      }
      value = fl_value_lookup_string(args, "namespace");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
        name = fl_value_get_string(value);
      }
      value = fl_value_lookup_string(args, "keyboard");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
        keyboard = fl_value_get_string(value);
      }
      value = fl_value_lookup_string(args, "thickness");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
        thickness = (gint)fl_value_get_int(value);
      }
    }
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* surface =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (surface->window != nullptr) {
        apply_layer_shell(surface, side, thickness, layer, name, keyboard);
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "menuOpen") == 0) {
    const gint64 bar_view_id = method_arg_int(method_call, "barViewId");
    const gchar* side = "top";
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "side");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
        side = fl_value_get_string(value);
      }
    }
    GdkMonitor* monitor = nullptr;
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* bar =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (bar->view == nullptr || bar->window == nullptr ||
          fl_view_get_id(bar->view) != bar_view_id) {
        continue;
      }
      GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(bar->window));
      if (gdk_window != nullptr) {
        monitor = gdk_display_get_monitor_at_window(
            gtk_widget_get_display(GTK_WIDGET(bar->window)), gdk_window);
      }
      break;
    }
    TricksterSurface* menu = trickster_menu_surface_new(self, monitor, side);
    g_ptr_array_add(self->menus, menu);
    g_autoptr(FlValue) result = fl_value_new_int(fl_view_get_id(menu->view));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "menuShow") == 0) {
    const gint64 view_id = method_arg_int(method_call, "viewId");
    for (guint i = 0; i < self->menus->len; i++) {
      TricksterSurface* menu =
          (TricksterSurface*)g_ptr_array_index(self->menus, i);
      if (menu->view == nullptr || fl_view_get_id(menu->view) != view_id) {
        continue;
      }
      gtk_widget_show(GTK_WIDGET(menu->window));
      break;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "menuClose") == 0) {
    const gint64 view_id = method_arg_int(method_call, "viewId");
    for (guint i = 0; i < self->menus->len; i++) {
      TricksterSurface* menu =
          (TricksterSurface*)g_ptr_array_index(self->menus, i);
      if (menu->view == nullptr || fl_view_get_id(menu->view) != view_id) {
        continue;
      }
      gtk_widget_destroy(GTK_WIDGET(menu->window));
      g_ptr_array_remove(self->menus, menu);
      break;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static TricksterSurface* trickster_surface_new(MyApplication* self,
                                               GdkMonitor* monitor) {
  TricksterSurface* surface = g_new0(TricksterSurface, 1);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  surface->window = window;
  surface->monitor = monitor;

  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_title(window, "trickster");
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }

  if (gtk_layer_is_supported()) {
    gtk_layer_init_for_window(window);
    if (monitor != nullptr) {
      gtk_layer_set_monitor(window, monitor);
    }
    apply_layer_shell(surface, "top", 32, "top", "trickster", "on_demand");
    // Map the layer surface and finish the initial-configure handshake before
    // the engine starts. Dart modules open sockets to the compositor as soon
    // as they run; a request in flight while gtk-layer-shell blocks on the
    // initial configure stalls compositors that service IPC on their main
    // loop (Hyprland accepts a connection and blocks in poll() until the
    // command arrives), which pushes the configure past the map timeout and
    // tears the surface down. Starting the engine after the handshake makes
    // the race impossible.
    gtk_widget_show(GTK_WIDGET(window));
  } else {
    gtk_window_set_default_size(window, 1280, 32);
    gtk_widget_show(GTK_WIDGET(window));
  }
  return surface;
}

static void trickster_surface_configure(TricksterSurface* surface,
                                        FlView* view) {
  surface->view = view;
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(surface->window), GTK_WIDGET(view));
  gtk_widget_realize(GTK_WIDGET(view));
}

static int run_check(MyApplication* self) {
  int failed = 0;
  const gchar* wayland = g_getenv("WAYLAND_DISPLAY");
  if (wayland == nullptr || wayland[0] == '\0') {
    g_printerr("fail  wayland: WAYLAND_DISPLAY is unset\n");
    failed = 1;
  } else {
    g_print("ok    wayland: %s\n", wayland);
  }
  if (gtk_layer_is_supported()) {
    g_print("ok    layer-shell: zwlr_layer_shell_v1 advertised\n");
  } else {
    g_printerr("fail  layer-shell: compositor does not advertise zwlr_layer_shell_v1\n");
    failed = 1;
  }
  if (trickster_probe_blur(self)) {
    g_print("ok    blur: ext-background-effect advertised\n");
  } else {
    g_print("ok    blur: not advertised (translucent fill)\n");
  }
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr) {
    g_printerr("fail  outputs: no display\n");
    failed = 1;
  } else {
    const int count = gdk_display_get_n_monitors(display);
    if (count <= 0) {
      g_printerr("fail  outputs: no monitors reported\n");
      failed = 1;
    } else {
      g_autoptr(GString) names = g_string_new(nullptr);
      for (int i = 0; i < count; i++) {
        GdkMonitor* monitor = gdk_display_get_monitor(display, i);
        g_autofree gchar* connector =
            trickster_connector_for_monitor(monitor);
        const gchar* model = gdk_monitor_get_model(monitor);
        if (i > 0) {
          g_string_append(names, ", ");
        }
        g_string_append_printf(names, "%s",
                               connector != nullptr
                                   ? connector
                                   : model != nullptr ? model : "output");
      }
      g_print("ok    outputs: %s\n", names->str);
    }
  }
  return failed;
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GdkDisplay* display = gdk_display_get_default();
  int monitor_count = display != nullptr ? gdk_display_get_n_monitors(display)
                                         : 0;
  if (monitor_count <= 0) {
    monitor_count = 1;
  }

  // Map every layer surface before the engine starts; see
  // trickster_surface_new for why the initial-configure handshake must finish
  // first.
  for (int i = 0; i < monitor_count; i++) {
    GdkMonitor* monitor =
        display != nullptr ? gdk_display_get_monitor(display, i) : nullptr;
    g_ptr_array_add(self->surfaces, trickster_surface_new(self, monitor));
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  // The first view bootstraps the engine; every further surface attaches to
  // that same engine with fl_view_new_for_engine. One engine, one isolate,
  // one FlView per layer surface. Plugins are engine-scoped, so they register
  // once on the first view. Note: fl_engine_new produces a handle that this
  // embedder rejects at AddView ("Engine handle was invalid"), so the
  // single-view bootstrap is the only working entry point.
  FlEngine* engine = nullptr;
  for (guint i = 0; i < self->surfaces->len; i++) {
    TricksterSurface* surface =
        (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
    if (engine == nullptr) {
      FlView* view = fl_view_new(project);
      engine = fl_view_get_engine(view);
      self->engine = engine;
      trickster_surface_configure(surface, view);
      fl_register_plugins(FL_PLUGIN_REGISTRY(view));
    } else {
      trickster_surface_configure(surface, fl_view_new_for_engine(engine));
    }
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(self->engine),
      "org.trickster.bar/layer_shell", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, self,
                                            nullptr);

  if (self->surfaces->len > 0) {
    TricksterSurface* first =
        (TricksterSurface*)g_ptr_array_index(self->surfaces, 0);
    if (first->view != nullptr) {
      gtk_widget_grab_focus(GTK_WIDGET(first->view));
    }
  }
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  gchar** argv = *arguments;
  gboolean want_version = FALSE;
  gboolean want_check = FALSE;
  for (int i = 1; argv[i] != nullptr; i++) {
    if (g_strcmp0(argv[i], "--version") == 0) {
      want_version = TRUE;
    } else if (g_strcmp0(argv[i], "--check") == 0) {
      want_check = TRUE;
    }
  }
  if (want_version) {
    g_print("trickster 0.1.0\n");
    *exit_status = 0;
    return TRUE;
  }

  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (want_check) {
    *exit_status = run_check(self);
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  for (guint i = 0; i < self->surfaces->len; i++) {
    TricksterSurface* surface =
        (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
    if (surface->blur != nullptr) {
      ext_background_effect_surface_v1_destroy(surface->blur);
      surface->blur = nullptr;
    }
  }
  for (guint i = 0; i < self->menus->len; i++) {
    TricksterSurface* menu = (TricksterSurface*)g_ptr_array_index(self->menus, i);
    if (menu->blur != nullptr) {
      ext_background_effect_surface_v1_destroy(menu->blur);
      menu->blur = nullptr;
    }
  }
  if (self->blur_manager != nullptr) {
    ext_background_effect_manager_v1_destroy(self->blur_manager);
    self->blur_manager = nullptr;
  }
  if (self->compositor != nullptr) {
    wl_compositor_destroy(self->compositor);
    self->compositor = nullptr;
  }
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->surfaces, g_ptr_array_unref);
  g_clear_pointer(&self->menus, g_ptr_array_unref);
  self->engine = nullptr;
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->surfaces = g_ptr_array_new_with_free_func(trickster_surface_free);
  self->menus = g_ptr_array_new_with_free_func(trickster_surface_free);
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
