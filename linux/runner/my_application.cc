#include "my_application.h"

#include <cairo.h>
#include <gdk/gdkwayland.h>

#include "ext-background-effect-v1-client-protocol.h"

#include <gtk-layer-shell.h>
#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

typedef struct {
  GtkWindow* window;
  FlView* view;
  GdkMonitor* monitor;
  gchar* connector;
  struct ext_background_effect_surface_v1* blur;
  gboolean blur_enabled;
  FlValue* blur_regions;
  gint thickness;
  gboolean horizontal;
} TricksterSurface;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlEngine* engine;
  GPtrArray* surfaces;
  GPtrArray* menus;
  GPtrArray* tooltips;
  gboolean settings_mode;
  GtkWindow* settings_window;
  FlView* settings_view;
  struct ext_background_effect_surface_v1* settings_blur;
  GtkWindow* bootstrap_window;
  FlView* bootstrap_view;
  gboolean blur_checked;
  gboolean blur_supported;
  struct wl_compositor* compositor;
  struct ext_background_effect_manager_v1* blur_manager;
  gchar* side;
  gint thickness;
  gchar* layer;
  gchar* layer_namespace;
  gchar* keyboard;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void trickster_surface_free(gpointer data) {
  TricksterSurface* surface = (TricksterSurface*)data;
  g_free(surface->connector);
  if (surface->blur_regions != nullptr) {
    fl_value_unref(surface->blur_regions);
  }
  g_free(surface);
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
  const gboolean horizontal =
      g_strcmp0(side, "left") != 0 && g_strcmp0(side, "right") != 0;
  // Horizontal strips stretch between the left and right edges; vertical
  // strips stretch between the top and bottom edges.
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP,
                       g_strcmp0(side, "top") == 0 || !horizontal);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM,
                       g_strcmp0(side, "bottom") == 0 || !horizontal);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT,
                       g_strcmp0(side, "left") == 0 || horizontal);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT,
                       g_strcmp0(side, "right") == 0 || horizontal);
  // The exclusive zone always equals the strip. Menus never resize this
  // surface: they live on their own overlay surfaces, so the strip cannot be
  // stretched by a resize while an old frame is still current.
  gtk_layer_set_exclusive_zone(window, thickness);
  // A hidden config (thickness 0) releases the zone; the surface is unmapped
  // right after.
  if (thickness <= 0) {
    gtk_layer_set_exclusive_zone(window, 0);
    return;
  }
  surface->thickness = thickness;
  surface->horizontal = horizontal;
  if (!horizontal) {
    gtk_widget_set_size_request(GTK_WIDGET(window), thickness, -1);
  } else {
    gtk_widget_set_size_request(GTK_WIDGET(window), -1, thickness);
  }
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
                                 FlValue* regions);
static TricksterSurface* trickster_surface_new(MyApplication* self,
                                               GdkMonitor* monitor);
static void trickster_surface_configure(TricksterSurface* surface,
                                        FlView* view);

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

static gboolean region_rect(FlValue* item, int32_t* x, int32_t* y,
                            int32_t* width, int32_t* height) {
  if (item == nullptr || fl_value_get_type(item) != FL_VALUE_TYPE_MAP) {
    return FALSE;
  }
  FlValue* fx = fl_value_lookup_string(item, "x");
  FlValue* fy = fl_value_lookup_string(item, "y");
  FlValue* fw = fl_value_lookup_string(item, "width");
  FlValue* fh = fl_value_lookup_string(item, "height");
  if (fx == nullptr || fy == nullptr || fw == nullptr || fh == nullptr) {
    return FALSE;
  }
  const FlValueType xt = fl_value_get_type(fx);
  const FlValueType yt = fl_value_get_type(fy);
  const FlValueType wt = fl_value_get_type(fw);
  const FlValueType ht = fl_value_get_type(fh);
  if ((xt != FL_VALUE_TYPE_INT && xt != FL_VALUE_TYPE_FLOAT) ||
      (yt != FL_VALUE_TYPE_INT && yt != FL_VALUE_TYPE_FLOAT) ||
      (wt != FL_VALUE_TYPE_INT && wt != FL_VALUE_TYPE_FLOAT) ||
      (ht != FL_VALUE_TYPE_INT && ht != FL_VALUE_TYPE_FLOAT)) {
    return FALSE;
  }
  *x = (int32_t)(xt == FL_VALUE_TYPE_INT ? fl_value_get_int(fx)
                                         : fl_value_get_float(fx));
  *y = (int32_t)(yt == FL_VALUE_TYPE_INT ? fl_value_get_int(fy)
                                         : fl_value_get_float(fy));
  *width = (int32_t)(wt == FL_VALUE_TYPE_INT ? fl_value_get_int(fw)
                                             : fl_value_get_float(fw));
  *height = (int32_t)(ht == FL_VALUE_TYPE_INT ? fl_value_get_int(fh)
                                              : fl_value_get_float(fh));
  return *width > 0 && *height > 0;
}

// Blurs exactly the pill rectangles: the protocol takes axis-aligned rects,
// so each card's bounds becomes a region entry and the gaps stay sharp. The
// list is cached so a remap (which destroys the wl_surface) can re-apply it.
static void trickster_apply_blur(MyApplication* self, TricksterSurface* surface,
                                 FlValue* regions) {
  if (surface->blur_regions != nullptr) {
    fl_value_unref(surface->blur_regions);
  }
  surface->blur_regions =
      regions != nullptr ? fl_value_ref(regions) : nullptr;
  const gboolean enabled =
      regions != nullptr && fl_value_get_type(regions) == FL_VALUE_TYPE_LIST &&
      fl_value_get_length(regions) > 0;
  surface->blur_enabled = enabled;
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
    wl_surface_commit(wl_surface);
    return;
  }
  if (self->compositor == nullptr) {
    return;
  }
  struct wl_region* region = wl_compositor_create_region(self->compositor);
  if (region == nullptr) {
    return;
  }
  for (size_t i = 0; i < fl_value_get_length(regions); i++) {
    int32_t x = 0, y = 0, width = 0, height = 0;
    if (region_rect(fl_value_get_list_value(regions, i), &x, &y, &width,
                    &height)) {
      wl_region_add(region, x, y, width, height);
    }
  }
  ext_background_effect_surface_v1_set_blur_region(surface->blur, region);
  wl_region_destroy(region);
  // The region is double-buffered surface state; commit so it applies even
  // when no new frame is scheduled.
  wl_surface_commit(wl_surface);
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

// Creates the fullscreen overlay surface hosting one transient shelf panel:
// a tray menu or a tray tooltip. It starts hidden: Dart maps it after the
// session is ready, so the overlay never shows a default frame. The window's
// RGBA visual and transparent background match the strip surfaces.
//
// The surface is anchored to the edge opposite the strip and sized to the
// whole monitor: layer-shell places a surface inside the area left over by
// other surfaces' exclusive zones, so anchoring the strip's own edge would
// leave the bar band uncovered and clicks there would never dismiss a menu.
//
// Menus are modal (exclusive keyboard, full input). Tooltips are decorative:
// no keyboard and an empty input region, so hovering one can never steal the
// pointer from the tray item that spawned it. The semantics tree is the
// accessible path.
static TricksterSurface* trickster_overlay_surface_new(MyApplication* self,
                                                      GdkMonitor* monitor,
                                                      const gchar* side,
                                                      gboolean tooltip) {
  TricksterSurface* surface = g_new0(TricksterSurface, 1);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  surface->window = window;

  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_title(window, tooltip ? "trickster-tooltip" : "trickster-menu");
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
    gtk_layer_set_namespace(window,
                            tooltip ? "trickster-tooltip" : "trickster-menu");
    // A menu is modal: it holds the keyboard while mapped and covers the
    // output so Material's tap-region dismissal catches presses anywhere.
    gtk_layer_set_keyboard_mode(
        window, tooltip ? GTK_LAYER_SHELL_KEYBOARD_MODE_NONE
                        : GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
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

  if (tooltip) {
    // An empty input region makes the tooltip click-through entirely.
    gtk_widget_input_shape_combine_region(GTK_WIDGET(window),
                                          cairo_region_create());
  }

  return surface;
}

/// The monitor hosting the bar surface [bar_view_id], for overlay placement.
static GdkMonitor* trickster_monitor_for_bar(MyApplication* self,
                                             gint64 bar_view_id) {
  for (guint i = 0; i < self->surfaces->len; i++) {
    TricksterSurface* bar =
        (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
    if (bar->view == nullptr || bar->window == nullptr ||
        fl_view_get_id(bar->view) != bar_view_id) {
      continue;
    }
    GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(bar->window));
    if (gdk_window != nullptr) {
      return gdk_display_get_monitor_at_window(
          gtk_widget_get_display(GTK_WIDGET(bar->window)), gdk_window);
    }
    return nullptr;
  }
  return nullptr;
}

// The settings window's image chooser: a modal GTK dialog parented to the
// settings toplevel. Returns a newly allocated path, or null on dismissal.
static gchar* trickster_pick_image(MyApplication* self) {
  GtkWidget* dialog = gtk_file_chooser_dialog_new(
      "Choose pip image", self->settings_window, GTK_FILE_CHOOSER_ACTION_OPEN,
      "_Cancel", GTK_RESPONSE_CANCEL, "_Open", GTK_RESPONSE_ACCEPT, nullptr);
  GtkFileFilter* filter = gtk_file_filter_new();
  gtk_file_filter_set_name(filter, "Images");
  gtk_file_filter_add_pixbuf_formats(filter);
  gtk_file_filter_add_pattern(filter, "*.svg");
  gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), filter);
  gchar* path = nullptr;
  if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
  }
  gtk_widget_destroy(dialog);
  return path;
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
  } else if (g_strcmp0(method, "surfaceThickness") == 0) {
    // The strip grows and shrinks with its wrapped content: the exclusive
    // zone always equals the laid-out band.
    const gint64 view_id = method_arg_int(method_call, "viewId");
    const gint64 thickness = method_arg_int(method_call, "thickness");
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* surface =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (surface->view == nullptr ||
          fl_view_get_id(surface->view) != view_id ||
          surface->window == nullptr) {
        continue;
      }
      if (thickness <= 0 || thickness == surface->thickness) {
        break;
      }
      surface->thickness = (gint)thickness;
      gtk_layer_set_exclusive_zone(surface->window, (gint)thickness);
      if (surface->horizontal) {
        gtk_widget_set_size_request(GTK_WIDGET(surface->window), -1,
                                    (gint)thickness);
      } else {
        gtk_widget_set_size_request(GTK_WIDGET(surface->window),
                                    (gint)thickness, -1);
      }
      break;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "pickImageFile") == 0) {
    g_autoptr(FlValue) result = nullptr;
    gchar* path = trickster_pick_image(self);
    if (path != nullptr) {
      result = fl_value_new_string(path);
      g_free(path);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "setBlur") == 0) {
    const gint64 view_id = method_arg_int(method_call, "viewId");
    FlValue* regions = nullptr;
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "regions");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_LIST) {
        regions = value;
      }
    }
    trickster_probe_blur(self);
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* surface =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (surface->view == nullptr || fl_view_get_id(surface->view) != view_id) {
        continue;
      }
      trickster_apply_blur(self, surface, regions);
      break;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "outputs") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    GdkDisplay* display = gdk_display_get_default();
    if (display != nullptr) {
      const int count = gdk_display_get_n_monitors(display);
      for (int i = 0; i < count; i++) {
        GdkMonitor* monitor = gdk_display_get_monitor(display, i);
        GdkRectangle geometry;
        gdk_monitor_get_geometry(monitor, &geometry);
        gint64 view_id = -1;
        const gchar* connector = nullptr;
        for (guint j = 0; j < self->surfaces->len; j++) {
          TricksterSurface* surface =
              (TricksterSurface*)g_ptr_array_index(self->surfaces, j);
          if (surface->monitor != monitor) {
            continue;
          }
          connector = surface->connector;
          if (surface->view != nullptr) {
            view_id = fl_view_get_id(surface->view);
          }
          break;
        }
        g_autofree gchar* resolved =
            connector != nullptr ? nullptr
                                 : trickster_connector_for_monitor(monitor);
        const gchar* model = gdk_monitor_get_model(monitor);
        g_autoptr(FlValue) entry = fl_value_new_map();
        fl_value_set_string_take(
            entry, "name",
            fl_value_new_string(
                connector != nullptr
                    ? connector
                    : resolved != nullptr
                          ? resolved
                          : model != nullptr ? model : "output"));
        fl_value_set_string_take(entry, "width",
                                 fl_value_new_int(geometry.width));
        fl_value_set_string_take(entry, "height",
                                 fl_value_new_int(geometry.height));
        fl_value_set_string_take(entry, "viewId", fl_value_new_int(view_id));
        fl_value_set_string_take(
            entry, "scale",
            fl_value_new_int(gdk_monitor_get_scale_factor(monitor)));
        fl_value_append_take(list, fl_value_ref(entry));
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (g_strcmp0(method, "surfaceVisible") == 0) {
    const gint64 view_id = method_arg_int(method_call, "viewId");
    gboolean visible = TRUE;
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "visible");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL) {
        visible = fl_value_get_bool(value) ? TRUE : FALSE;
      }
    }
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* surface =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (surface->view == nullptr ||
          fl_view_get_id(surface->view) != view_id) {
        continue;
      }
      if (visible) {
        gtk_widget_show(GTK_WIDGET(surface->window));
        if (surface->blur_enabled) {
          // Unmapping destroys the window's wl_surface, so the effect bound
          // to it is stale; build a fresh one and re-apply the cached pill
          // rectangles.
          trickster_apply_blur(self, surface, surface->blur_regions);
        }
      } else {
        if (surface->blur != nullptr) {
          ext_background_effect_surface_v1_destroy(surface->blur);
          surface->blur = nullptr;
        }
        gtk_widget_hide(GTK_WIDGET(surface->window));
      }
      break;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "surfaceDestroy") == 0) {
    const gint64 view_id = method_arg_int(method_call, "viewId");
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* surface =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (surface->view == nullptr ||
          fl_view_get_id(surface->view) != view_id ||
          fl_view_get_id(surface->view) == 0) {
        continue;
      }
      if (surface->blur != nullptr) {
        ext_background_effect_surface_v1_destroy(surface->blur);
      }
      gtk_widget_destroy(GTK_WIDGET(surface->window));
      g_ptr_array_remove_index(self->surfaces, i);
      break;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "surfaceCreate") == 0) {
    gchar* connector = nullptr;
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "connector");
      if (value != nullptr &&
          fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
        connector = g_strdup(fl_value_get_string(value));
      }
    }
    gint64 new_view_id = -1;
    GdkDisplay* display = gdk_display_get_default();
    if (connector != nullptr && display != nullptr) {
      const int count = gdk_display_get_n_monitors(display);
      for (int i = 0; i < count; i++) {
        GdkMonitor* monitor = gdk_display_get_monitor(display, i);
        g_autofree gchar* name = trickster_connector_for_monitor(monitor);
        const gchar* model = gdk_monitor_get_model(monitor);
        const gchar* resolved =
            name != nullptr ? name : model != nullptr ? model : "output";
        if (g_strcmp0(resolved, connector) != 0) {
          continue;
        }
        gboolean exists = FALSE;
        for (guint j = 0; j < self->surfaces->len; j++) {
          TricksterSurface* surface =
              (TricksterSurface*)g_ptr_array_index(self->surfaces, j);
          if (surface->monitor == monitor) {
            exists = TRUE;
            break;
          }
        }
        if (!exists) {
          TricksterSurface* surface = trickster_surface_new(self, monitor);
          g_ptr_array_add(self->surfaces, surface);
          if (self->engine != nullptr) {
            trickster_surface_configure(surface,
                                        fl_view_new_for_engine(self->engine));
          }
          if (surface->view != nullptr) {
            new_view_id = fl_view_get_id(surface->view);
          }
        }
        break;
      }
    }
    g_free(connector);
    g_autoptr(FlValue) result = fl_value_new_int(new_view_id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
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
    g_free(self->side);
    self->side = g_strdup(side);
    g_free(self->layer);
    self->layer = g_strdup(layer);
    g_free(self->layer_namespace);
    self->layer_namespace = g_strdup(name);
    g_free(self->keyboard);
    self->keyboard = g_strdup(keyboard);
    self->thickness = thickness;
    for (guint i = 0; i < self->surfaces->len; i++) {
      TricksterSurface* surface =
          (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
      if (surface->window != nullptr && surface->monitor != nullptr) {
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
    TricksterSurface* menu = trickster_overlay_surface_new(
        self, trickster_monitor_for_bar(self, bar_view_id), side, FALSE);
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
      GdkRGBA background_color;
      gdk_rgba_parse(&background_color, "#00000000");
      fl_view_set_background_color(menu->view, &background_color);
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
  } else if (g_strcmp0(method, "tooltipOpen") == 0) {
    const gint64 bar_view_id = method_arg_int(method_call, "barViewId");
    const gchar* side = "top";
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "side");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
        side = fl_value_get_string(value);
      }
    }
    TricksterSurface* tooltip = trickster_overlay_surface_new(
        self, trickster_monitor_for_bar(self, bar_view_id), side, TRUE);
    g_ptr_array_add(self->tooltips, tooltip);
    g_autoptr(FlValue) result =
        fl_value_new_int(fl_view_get_id(tooltip->view));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "tooltipShow") == 0) {
    const gint64 view_id = method_arg_int(method_call, "viewId");
    for (guint i = 0; i < self->tooltips->len; i++) {
      TricksterSurface* tooltip =
          (TricksterSurface*)g_ptr_array_index(self->tooltips, i);
      if (tooltip->view == nullptr || fl_view_get_id(tooltip->view) != view_id) {
        continue;
      }
      gtk_widget_show(GTK_WIDGET(tooltip->window));
      GdkRGBA background_color;
      gdk_rgba_parse(&background_color, "#00000000");
      fl_view_set_background_color(tooltip->view, &background_color);
      break;
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "settingsClose") == 0) {
    if (self->settings_window != nullptr) {
      gtk_widget_destroy(GTK_WIDGET(self->settings_window));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "tooltipClose") == 0) {
    const gint64 view_id = method_arg_int(method_call, "viewId");
    for (guint i = 0; i < self->tooltips->len; i++) {
      TricksterSurface* tooltip =
          (TricksterSurface*)g_ptr_array_index(self->tooltips, i);
      if (tooltip->view == nullptr || fl_view_get_id(tooltip->view) != view_id) {
        continue;
      }
      gtk_widget_destroy(GTK_WIDGET(tooltip->window));
      g_ptr_array_remove(self->tooltips, tooltip);
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
  surface->connector = trickster_connector_for_monitor(monitor);

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
    apply_layer_shell(surface, self->side, self->thickness, self->layer,
                      self->layer_namespace, self->keyboard);
    // Mapping is deferred to trickster_surface_configure, which runs right
    // after the strip's Flutter view is realized: a mapped window with no
    // view makes GTK wait for a GL frame that never comes. The strips are
    // still mapped synchronously before Dart can issue compositor IPC, so
    // the initial-configure handshake race stays closed. Contract:
    // `.llm/performance.md` -> Hyprland IPC.
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
  // The view can produce frames now; map the strip.
  gtk_widget_show(GTK_WIDGET(surface->window));
}

static void monitor_added_cb(GdkDisplay* display, GdkMonitor* monitor,
                             gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  for (guint i = 0; i < self->surfaces->len; i++) {
    TricksterSurface* surface =
        (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
    if (surface->monitor == monitor) {
      return;
    }
  }
  TricksterSurface* surface = trickster_surface_new(self, monitor);
  g_ptr_array_add(self->surfaces, surface);
  if (self->engine != nullptr) {
    trickster_surface_configure(surface,
                                fl_view_new_for_engine(self->engine));
  }
}

static void monitor_removed_cb(GdkDisplay* display, GdkMonitor* monitor,
                               gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  for (guint i = 0; i < self->surfaces->len; i++) {
    TricksterSurface* surface =
        (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
    if (surface->monitor != monitor) {
      continue;
    }
    if (surface->blur != nullptr) {
      ext_background_effect_surface_v1_destroy(surface->blur);
      surface->blur = nullptr;
    }
    if (surface->view != nullptr && fl_view_get_id(surface->view) == 0) {
      // The implicit view cannot be removed without stopping the engine;
      // hide it so the dead output's zone is released.
      gtk_widget_hide(GTK_WIDGET(surface->window));
      surface->monitor = nullptr;
    } else {
      gtk_widget_destroy(GTK_WIDGET(surface->window));
      g_ptr_array_remove_index(self->surfaces, i);
    }
    break;
  }
}

// The settings window is a plain toplevel, not a layer surface: the
// settings application is a normal Wayland client of the host compositor.
static void trickster_settings_destroy_cb(GtkWidget* widget, gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  if (self->settings_blur != nullptr) {
    ext_background_effect_surface_v1_destroy(self->settings_blur);
    self->settings_blur = nullptr;
  }
  self->settings_window = nullptr;
  self->settings_view = nullptr;
  g_application_quit(G_APPLICATION(self));
}

// The settings toplevel asks the compositor to blur behind it; the Flutter
// side paints translucent surfaces on top and falls back to opaque fills
// when the manager is absent.
static void trickster_settings_apply_blur(MyApplication* self) {
  if (self->settings_window == nullptr) {
    return;
  }
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(self->settings_window));
  if (gdk_window == nullptr) {
    return;
  }
  struct wl_surface* wl_surface = gdk_wayland_window_get_wl_surface(gdk_window);
  if (wl_surface == nullptr) {
    return;
  }
  if (self->settings_blur == nullptr) {
    if (self->blur_manager == nullptr || self->compositor == nullptr) {
      return;
    }
    self->settings_blur = ext_background_effect_manager_v1_get_background_effect(
        self->blur_manager, wl_surface);
    if (self->settings_blur == nullptr) {
      return;
    }
  }
  const int width =
      gtk_widget_get_allocated_width(GTK_WIDGET(self->settings_window));
  const int height =
      gtk_widget_get_allocated_height(GTK_WIDGET(self->settings_window));
  if (width <= 0 || height <= 0) {
    return;
  }
  struct wl_region* region = wl_compositor_create_region(self->compositor);
  if (region == nullptr) {
    return;
  }
  wl_region_add(region, 0, 0, width, height);
  ext_background_effect_surface_v1_set_blur_region(self->settings_blur, region);
  wl_region_destroy(region);
  wl_surface_commit(wl_surface);
}

static void trickster_settings_realize_cb(GtkWidget* widget, gpointer data) {
  trickster_settings_apply_blur(MY_APPLICATION(data));
}

static void trickster_settings_size_allocate_cb(GtkWidget* widget,
                                                GtkAllocation* allocation,
                                                gpointer data) {
  trickster_settings_apply_blur(MY_APPLICATION(data));
}

// The RGBA visual only pays off with a cleared, transparent window backing.
static gboolean trickster_window_draw_cb(GtkWidget* widget, cairo_t* cr,
                                         gpointer data) {
  cairo_set_source_rgba(cr, 0, 0, 0, 0);
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_paint(cr);
  return FALSE;
}

static void trickster_settings_show(MyApplication* self,
                                    FlDartProject* project) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  gtk_window_set_title(window, "Trickster Settings");
  gtk_window_set_default_size(window, 980, 720);
  g_signal_connect(window, "destroy", G_CALLBACK(trickster_settings_destroy_cb),
                   self);

  // Only a translucent toplevel is worth compositing a backdrop behind; with
  // no manager the window stays opaque and the Dart fills match.
  const gboolean blur = trickster_probe_blur(self);
  if (blur) {
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
    GdkScreen* screen = gtk_window_get_screen(window);
    GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
    if (visual != nullptr) {
      gtk_widget_set_visual(GTK_WIDGET(window), visual);
    }
    g_signal_connect(window, "draw", G_CALLBACK(trickster_window_draw_cb),
                     self);
    g_signal_connect(window, "realize",
                     G_CALLBACK(trickster_settings_realize_cb), self);
    g_signal_connect(window, "size-allocate",
                     G_CALLBACK(trickster_settings_size_allocate_cb), self);
  }

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  self->settings_window = window;
  self->settings_view = view;
  self->engine = fl_view_get_engine(view);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_show(GTK_WIDGET(window));
}

static void trickster_install_method_channel(MyApplication* self) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(self->engine),
      "org.trickster.bar/layer_shell", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, self,
                                            nullptr);
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);
  if (self->settings_mode) {
    trickster_settings_show(self, project);
    trickster_install_method_channel(self);
    return;
  }

  GdkDisplay* display = gdk_display_get_default();
  int monitor_count = display != nullptr ? gdk_display_get_n_monitors(display)
                                         : 0;
  if (monitor_count <= 0) {
    monitor_count = 1;
  }

  if (display != nullptr) {
    g_signal_connect(display, "monitor-added", G_CALLBACK(monitor_added_cb),
                     self);
    g_signal_connect(display, "monitor-removed",
                     G_CALLBACK(monitor_removed_cb), self);
  }
  // Map every layer surface before the engine starts; see
  // trickster_surface_new for why the initial-configure handshake must finish
  // first.
  for (int i = 0; i < monitor_count; i++) {
    GdkMonitor* monitor =
        display != nullptr ? gdk_display_get_monitor(display, i) : nullptr;
    g_ptr_array_add(self->surfaces, trickster_surface_new(self, monitor));
  }

  // The engine's implicit view lives on a mapped 1x1 background surface,
  // never on a strip: the engine refuses to remove its implicit view, and a
  // strip must be destroyable for disruptive config changes (edge,
  // thickness) to rebuild surfaces. One engine, one isolate, one FlView per
  // surface; plugins register once on the bootstrap view. The strips are
  // configured (mapped) synchronously below, before Dart can issue
  // compositor IPC.
  GtkWindow* bootstrap_window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  gtk_window_set_title(bootstrap_window, "trickster-engine");
  gtk_window_set_decorated(bootstrap_window, FALSE);
  gtk_widget_set_app_paintable(GTK_WIDGET(bootstrap_window), TRUE);
  GdkVisual* bootstrap_visual = gdk_screen_get_rgba_visual(
      gtk_window_get_screen(bootstrap_window));
  if (bootstrap_visual != nullptr) {
    gtk_widget_set_visual(GTK_WIDGET(bootstrap_window), bootstrap_visual);
  }
  if (gtk_layer_is_supported()) {
    gtk_layer_init_for_window(bootstrap_window);
    gtk_layer_set_layer(bootstrap_window, GTK_LAYER_SHELL_LAYER_BACKGROUND);
    gtk_layer_set_namespace(bootstrap_window, "trickster-engine");
    gtk_layer_set_keyboard_mode(bootstrap_window,
                                GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
    gtk_layer_set_exclusive_zone(bootstrap_window, 0);
    gtk_layer_set_anchor(bootstrap_window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(bootstrap_window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_widget_set_size_request(GTK_WIDGET(bootstrap_window), 1, 1);
  } else {
    gtk_window_set_default_size(bootstrap_window, 1, 1);
  }
  self->bootstrap_window = bootstrap_window;
  FlView* bootstrap_view = fl_view_new(project);
  self->bootstrap_view = bootstrap_view;
  self->engine = fl_view_get_engine(bootstrap_view);
  GdkRGBA bootstrap_background;
  gdk_rgba_parse(&bootstrap_background, "#00000000");
  fl_view_set_background_color(bootstrap_view, &bootstrap_background);
  gtk_widget_show(GTK_WIDGET(bootstrap_view));
  gtk_container_add(GTK_CONTAINER(bootstrap_window), GTK_WIDGET(bootstrap_view));
  gtk_widget_realize(GTK_WIDGET(bootstrap_view));
  // Fully transparent and click-through: the bootstrap exists only to host
  // the engine's implicit view, never to be seen or hit.
  gtk_widget_set_opacity(GTK_WIDGET(bootstrap_window), 0.0);
  gtk_widget_input_shape_combine_region(GTK_WIDGET(bootstrap_window),
                                        cairo_region_create());
  gtk_widget_show(GTK_WIDGET(bootstrap_window));
  fl_register_plugins(FL_PLUGIN_REGISTRY(bootstrap_view));

  for (guint i = 0; i < self->surfaces->len; i++) {
    TricksterSurface* surface =
        (TricksterSurface*)g_ptr_array_index(self->surfaces, i);
    trickster_surface_configure(surface, fl_view_new_for_engine(self->engine));
  }

  trickster_install_method_channel(self);

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
  gboolean want_settings = FALSE;
  for (int i = 1; argv[i] != nullptr; i++) {
    if (g_strcmp0(argv[i], "--version") == 0) {
      want_version = TRUE;
    } else if (g_strcmp0(argv[i], "--settings") == 0) {
      want_settings = TRUE;
    }
  }
  if (want_version) {
    g_print("trickster 0.2.0\n");
    *exit_status = 0;
    return TRUE;
  }

  // The trickster-settings symlink is the same binary in settings mode.
  g_autofree gchar* program = g_path_get_basename(argv[0]);
  const gboolean by_name =
      g_strcmp0(program, "trickster-settings") == 0;
  self->settings_mode = want_settings || by_name;
  if (self->settings_mode) {
    // Dart branches on --settings; inject it when the symlink supplied it.
    const guint argc = g_strv_length(argv);
    gchar** dart_args = g_new0(gchar*, argc + 1);
    dart_args[0] = g_strdup("--settings");
    for (guint i = 1; i < argc; i++) {
      dart_args[i] = g_strdup(argv[i]);
    }
    dart_args[argc] = nullptr;
    self->dart_entrypoint_arguments = dart_args;
  } else {
    self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
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
  g_clear_pointer(&self->tooltips, g_ptr_array_unref);
  g_clear_pointer(&self->side, g_free);
  g_clear_pointer(&self->layer, g_free);
  g_clear_pointer(&self->layer_namespace, g_free);
  g_clear_pointer(&self->keyboard, g_free);
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
  self->tooltips = g_ptr_array_new_with_free_func(trickster_surface_free);
  self->settings_mode = FALSE;
  self->side = g_strdup("top");
  self->thickness = 32;
  self->layer = g_strdup("top");
  self->layer_namespace = g_strdup("trickster");
  self->keyboard = g_strdup("on_demand");
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
