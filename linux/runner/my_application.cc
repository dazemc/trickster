#include "my_application.h"

#include <gtk-layer-shell.h>
#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

typedef struct {
  GtkWindow* window;
  FlView* view;
} TricksterSurface;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlEngine* engine;
  GPtrArray* surfaces;
  GPtrArray* menus;
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
  } else if (g_strcmp0(method, "outputs") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    GdkDisplay* display = gdk_display_get_default();
    if (display != nullptr) {
      const int count = gdk_display_get_n_monitors(display);
      for (int i = 0; i < count; i++) {
        GdkMonitor* monitor = gdk_display_get_monitor(display, i);
        GdkRectangle geometry;
        gdk_monitor_get_geometry(monitor, &geometry);
        g_autoptr(FlValue) entry = fl_value_new_map();
        const gchar* model = gdk_monitor_get_model(monitor);
        g_autofree gchar* name = g_strdup_printf("output-%d", i);
        fl_value_set_string_take(entry, "name",
                                 fl_value_new_string(model ? model : name));
        fl_value_set_string_take(entry, "width",
                                 fl_value_new_int(geometry.width));
        fl_value_set_string_take(entry, "height",
                                 fl_value_new_int(geometry.height));
        fl_value_append_take(list, fl_value_ref(entry));
      }
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

static int run_check() {
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
      g_print("ok    outputs: %d monitor(s)\n", count);
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
    *exit_status = run_check();
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
