#include "pipewire_volume.h"

#include <math.h>

#include <pipewire/extensions/metadata.h>
#include <pipewire/pipewire.h>
#include <spa/param/props.h>
#include <spa/param/route.h>
#include <spa/pod/builder.h>
#include <spa/pod/iter.h>
#include <spa/utils/result.h>

#define TRICKSTER_VOLUME_MAX_CHANNELS 64

// The system volume is the default sink device's active route; WirePlumber's
// mixer API (wpctl) writes the route's linear channel volumes and displays
// the cubic root of the first channel. A sink without a device route (a
// virtual sink) falls back to the node's own Props.
struct _TricksterVolume {
  FlMethodChannel* channel;
  pw_thread_loop* loop;
  pw_context* context;
  pw_core* core;
  pw_registry* registry;
  pw_metadata* metadata;
  pw_node* node;
  pw_device* device;
  struct spa_hook core_listener;
  struct spa_hook registry_listener;
  struct spa_hook metadata_listener;
  struct spa_hook node_listener;
  struct spa_hook device_listener;
  GHashTable* sinks;  // sink node name -> registry id
  gchar* default_sink;
  guint32 device_id;       // the sink node's device.id, 0 when none
  gint32 route_device;     // card.profile.device of the active route
  gint32 route_index;
  gboolean has_route;
  GMutex mutex;
  gfloat volumes[TRICKSTER_VOLUME_MAX_CHANNELS];
  guint32 channels;
  gboolean muted;
  gboolean has_volume;
  gboolean running;
  guint push_source;
};

// WirePlumber stores the default sink as JSON: {"name":"alsa_output..."}.
static gchar* trickster_volume_parse_sink(const gchar* value) {
  if (value == nullptr) {
    return nullptr;
  }
  const gchar* key = g_strstr_len(value, -1, "\"name\"");
  if (key == nullptr) {
    return nullptr;
  }
  const gchar* colon = strchr(key, ':');
  const gchar* start = colon != nullptr ? strchr(colon, '"') : nullptr;
  const gchar* end = start != nullptr ? strchr(start + 1, '"') : nullptr;
  if (start == nullptr || end == nullptr) {
    return nullptr;
  }
  return g_strndup(start + 1, (gsize)(end - start - 1));
}

static void trickster_volume_bind_sink(TricksterVolume* self,
                                       const gchar* name);
static void trickster_volume_bind_device(TricksterVolume* self);
static void trickster_volume_schedule_push(TricksterVolume* self);
static void trickster_volume_node_param(void* data, int seq, uint32_t id,
                                        uint32_t index, uint32_t next,
                                        const struct spa_pod* param);
static void trickster_volume_node_info(void* data,
                                       const struct pw_node_info* info);
static void trickster_volume_device_param(void* data, int seq, uint32_t id,
                                          uint32_t index, uint32_t next,
                                          const struct spa_pod* param);
static void trickster_volume_device_info(void* data,
                                         const struct pw_device_info* info);
static int trickster_volume_metadata_property(void* data, uint32_t subject,
                                              const char* key, const char* type,
                                              const char* value);
static void trickster_volume_registry_global(void* data, uint32_t id,
                                             uint32_t permissions,
                                             const char* type,
                                             uint32_t version,
                                             const struct spa_dict* props);
static void trickster_volume_registry_global_remove(void* data, uint32_t id);

static const struct pw_node_events trickster_volume_node_events = {
    .version = PW_VERSION_NODE_EVENTS,
    .info = trickster_volume_node_info,
    .param = trickster_volume_node_param,
};

static const struct pw_device_events trickster_volume_device_events = {
    .version = PW_VERSION_DEVICE_EVENTS,
    .info = trickster_volume_device_info,
    .param = trickster_volume_device_param,
};

static const struct pw_metadata_events trickster_volume_metadata_events = {
    .version = PW_VERSION_METADATA_EVENTS,
    .property = trickster_volume_metadata_property,
};

static const struct pw_registry_events trickster_volume_registry_events = {
    .version = PW_VERSION_REGISTRY_EVENTS,
    .global = trickster_volume_registry_global,
    .global_remove = trickster_volume_registry_global_remove,
};

static void trickster_volume_core_error(void* data, uint32_t id, int seq,
                                        int res, const char* message) {
  if (res < 0) {
    g_warning("trickster: pipewire volume error: %s", message);
  }
}

static const struct pw_core_events trickster_volume_core_events = {
    .version = PW_VERSION_CORE_EVENTS,
    .error = trickster_volume_core_error,
};

static gboolean trickster_volume_push(gpointer data);

static void trickster_volume_schedule_push(TricksterVolume* self) {
  g_mutex_lock(&self->mutex);
  if (self->push_source == 0) {
    self->push_source = g_idle_add_full(G_PRIORITY_DEFAULT_IDLE,
                                        trickster_volume_push, self, nullptr);
  }
  g_mutex_unlock(&self->mutex);
}

// Reads channelVolumes/mute/volume out of a Props object; the caller holds
// the mutex.
static void trickster_volume_read_props(TricksterVolume* self,
                                        const struct spa_pod* props) {
  if (props == nullptr || SPA_POD_TYPE(props) != SPA_TYPE_Object) {
    return;
  }
  const struct spa_pod_object* object = (const struct spa_pod_object*)props;
  const struct spa_pod_prop* prop = nullptr;
  SPA_POD_OBJECT_FOREACH(object, prop) {
    switch (prop->key) {
      case SPA_PROP_channelVolumes: {
        gfloat values[TRICKSTER_VOLUME_MAX_CHANNELS];
        const uint32_t count =
            spa_pod_copy_array(&prop->value, SPA_TYPE_Float, values,
                               TRICKSTER_VOLUME_MAX_CHANNELS);
        if (count > 0) {
          self->channels = count;
          for (uint32_t i = 0; i < count; i++) {
            self->volumes[i] = values[i];
          }
          self->has_volume = TRUE;
        }
        break;
      }
      case SPA_PROP_volume: {
        gfloat value = 0;
        if (spa_pod_get_float(&prop->value, &value) == 0 && !self->has_volume) {
          self->channels = 1;
          self->volumes[0] = value;
          self->has_volume = TRUE;
        }
        break;
      }
      case SPA_PROP_mute: {
        bool muted = false;
        if (spa_pod_get_bool(&prop->value, &muted) == 0) {
          self->muted = muted;
        }
        break;
      }
      default:
        break;
    }
  }
}

static void trickster_volume_bind_sink(TricksterVolume* self,
                                       const gchar* name) {
  gpointer id = g_hash_table_lookup(self->sinks, name);
  if (id == nullptr) {
    return;
  }
  if (self->node != nullptr) {
    spa_hook_remove(&self->node_listener);
    pw_proxy_destroy((struct pw_proxy*)self->node);
    self->node = nullptr;
  }
  self->node = (pw_node*)pw_registry_bind(self->registry, GPOINTER_TO_UINT(id),
                                          PW_TYPE_INTERFACE_Node,
                                          PW_VERSION_NODE, 0);
  if (self->node == nullptr) {
    return;
  }
  spa_zero(self->node_listener);
  pw_node_add_listener(self->node, &self->node_listener,
                       &trickster_volume_node_events, self);
  guint32 ids[1] = {SPA_PARAM_Props};
  pw_node_subscribe_params(self->node, ids, 1);
  pw_node_enum_params(self->node, 1, SPA_PARAM_Props, 0, -1, nullptr);
}

static void trickster_volume_bind_device(TricksterVolume* self) {
  if (self->device != nullptr) {
    spa_hook_remove(&self->device_listener);
    pw_proxy_destroy((struct pw_proxy*)self->device);
    self->device = nullptr;
  }
  g_mutex_lock(&self->mutex);
  self->has_route = FALSE;
  self->route_index = -1;
  g_mutex_unlock(&self->mutex);
  if (self->device_id == 0) {
    return;
  }
  self->device = (pw_device*)pw_registry_bind(
      self->registry, self->device_id, PW_TYPE_INTERFACE_Device,
      PW_VERSION_DEVICE, 0);
  if (self->device == nullptr) {
    return;
  }
  spa_zero(self->device_listener);
  pw_device_add_listener(self->device, &self->device_listener,
                         &trickster_volume_device_events, self);
  guint32 ids[1] = {SPA_PARAM_Route};
  pw_device_subscribe_params(self->device, ids, 1);
  pw_device_enum_params(self->device, 1, SPA_PARAM_Route, 0, -1, nullptr);
}

static void trickster_volume_registry_global(void* data, uint32_t id,
                                             uint32_t permissions,
                                             const char* type,
                                             uint32_t version,
                                             const struct spa_dict* props) {
  TricksterVolume* self = (TricksterVolume*)data;
  if (g_strcmp0(type, PW_TYPE_INTERFACE_Metadata) == 0) {
    const gchar* name =
        props != nullptr ? spa_dict_lookup(props, PW_KEY_METADATA_NAME)
                         : nullptr;
    if (g_strcmp0(name, "default") == 0 && self->metadata == nullptr) {
      self->metadata = (pw_metadata*)pw_registry_bind(
          self->registry, id, type, PW_VERSION_METADATA, 0);
      if (self->metadata != nullptr) {
        spa_zero(self->metadata_listener);
        pw_metadata_add_listener(self->metadata, &self->metadata_listener,
                                 &trickster_volume_metadata_events, self);
      }
    }
    return;
  }
  if (g_strcmp0(type, PW_TYPE_INTERFACE_Node) != 0) {
    return;
  }
  const gchar* klass =
      props != nullptr ? spa_dict_lookup(props, PW_KEY_MEDIA_CLASS) : nullptr;
  if (g_strcmp0(klass, "Audio/Sink") != 0) {
    return;
  }
  const gchar* name =
      props != nullptr ? spa_dict_lookup(props, PW_KEY_NODE_NAME) : nullptr;
  if (name == nullptr) {
    return;
  }
  g_hash_table_insert(self->sinks, g_strdup(name), GUINT_TO_POINTER(id));
  if (g_strcmp0(name, self->default_sink) == 0) {
    trickster_volume_bind_sink(self, name);
  }
}

static void trickster_volume_registry_global_remove(void* data, uint32_t id) {
  TricksterVolume* self = (TricksterVolume*)data;
  GHashTableIter iter;
  gpointer key;
  gpointer value;
  g_hash_table_iter_init(&iter, self->sinks);
  while (g_hash_table_iter_next(&iter, &key, &value)) {
    if (GPOINTER_TO_UINT(value) == id) {
      g_hash_table_iter_remove(&iter);
      break;
    }
  }
}

static int trickster_volume_metadata_property(void* data, uint32_t subject,
                                              const char* key, const char* type,
                                              const char* value) {
  TricksterVolume* self = (TricksterVolume*)data;
  if (g_strcmp0(key, "default.audio.sink") != 0) {
    return 0;
  }
  g_autofree gchar* name = trickster_volume_parse_sink(value);
  if (name == nullptr || g_strcmp0(name, self->default_sink) == 0) {
    return 0;
  }
  g_free(self->default_sink);
  self->default_sink = g_strdup(name);
  trickster_volume_bind_sink(self, name);
  return 0;
}

static void trickster_volume_node_info(void* data,
                                       const struct pw_node_info* info) {
  TricksterVolume* self = (TricksterVolume*)data;
  if (info == nullptr || info->props == nullptr) {
    return;
  }
  const gchar* device = spa_dict_lookup(info->props, PW_KEY_DEVICE_ID);
  const gchar* profile =
      spa_dict_lookup(info->props, "card.profile.device");
  const guint32 device_id = device != nullptr ? (guint32)atoi(device) : 0;
  const gint32 route_device = profile != nullptr ? atoi(profile) : -1;
  if (device_id == self->device_id && route_device == self->route_device &&
      self->device != nullptr) {
    return;
  }
  self->device_id = device_id;
  self->route_device = route_device;
  trickster_volume_bind_device(self);
}

static void trickster_volume_device_info(void* data,
                                         const struct pw_device_info* info) {
  // Route params carry everything; the info callback only marks the device
  // as live.
}

static void trickster_volume_device_param(void* data, int seq, uint32_t id,
                                          uint32_t index, uint32_t next,
                                          const struct spa_pod* param) {
  if (param == nullptr || id != SPA_PARAM_Route) {
    return;
  }
  TricksterVolume* self = (TricksterVolume*)data;
  if (SPA_POD_TYPE(param) != SPA_TYPE_Object) {
    return;
  }
  const struct spa_pod_object* route = (const struct spa_pod_object*)param;
  const struct spa_pod_prop* prop = nullptr;
  gint32 route_index = -1;
  gint32 route_device = -1;
  const struct spa_pod* props = nullptr;
  SPA_POD_OBJECT_FOREACH(route, prop) {
    switch (prop->key) {
      case SPA_PARAM_ROUTE_index: {
        int32_t value = 0;
        if (spa_pod_get_int(&prop->value, &value) == 0) {
          route_index = value;
        }
        break;
      }
      case SPA_PARAM_ROUTE_device: {
        int32_t value = 0;
        if (spa_pod_get_int(&prop->value, &value) == 0) {
          route_device = value;
        }
        break;
      }
      case SPA_PARAM_ROUTE_props:
        props = &prop->value;
        break;
      default:
        break;
    }
  }
  if (route_device != self->route_device || props == nullptr) {
    return;
  }
  g_mutex_lock(&self->mutex);
  self->has_route = TRUE;
  self->route_index = route_index;
  trickster_volume_read_props(self, props);
  g_mutex_unlock(&self->mutex);
  trickster_volume_schedule_push(self);
}

static void trickster_volume_node_param(void* data, int seq, uint32_t id,
                                        uint32_t index, uint32_t next,
                                        const struct spa_pod* param) {
  if (param == nullptr || id != SPA_PARAM_Props) {
    return;
  }
  TricksterVolume* self = (TricksterVolume*)data;
  g_mutex_lock(&self->mutex);
  // The node's own Props only matter when no device route owns the volume.
  if (!self->has_route) {
    trickster_volume_read_props(self, param);
  }
  g_mutex_unlock(&self->mutex);
  trickster_volume_schedule_push(self);
}

static gboolean trickster_volume_push(gpointer data) {
  TricksterVolume* self = (TricksterVolume*)data;
  g_mutex_lock(&self->mutex);
  self->push_source = 0;
  if (!self->has_volume || !self->running) {
    g_mutex_unlock(&self->mutex);
    return G_SOURCE_REMOVE;
  }
  // WirePlumber's mixer API displays the cubic root of the first channel.
  const gdouble volume =
      self->channels > 0 ? cbrt((double)self->volumes[0]) : 0;
  const gboolean muted = self->muted;
  g_mutex_unlock(&self->mutex);
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "volume", fl_value_new_float(volume));
  fl_value_set_string_take(args, "muted", fl_value_new_bool(muted));
  fl_method_channel_invoke_method(self->channel, "volume", args, nullptr,
                                  nullptr, nullptr);
  return G_SOURCE_REMOVE;
}

static void trickster_volume_init_once(void) {
  static gsize once = 0;
  if (g_once_init_enter(&once)) {
    pw_init(nullptr, nullptr);
    g_once_init_leave(&once, 1);
  }
}

static void trickster_volume_method_call(FlMethodChannel* channel,
                                         FlMethodCall* method_call,
                                         gpointer user_data) {
  TricksterVolume* self = (TricksterVolume*)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "volumeStart") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(trickster_volume_start(self) ? TRUE : FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "volumeStop") == 0) {
    trickster_volume_stop(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "volumeSet") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* value = fl_value_lookup_string(args, "volume");
      if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
        trickster_volume_set(self, fl_value_get_float(value));
      }
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

TricksterVolume* trickster_volume_new(FlBinaryMessenger* messenger) {
  TricksterVolume* self = g_new0(TricksterVolume, 1);
  g_mutex_init(&self->mutex);
  self->sinks = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
  self->route_index = -1;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger, "org.trickster.bar/volume",
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel,
                                            trickster_volume_method_call, self,
                                            nullptr);
  return self;
}

gboolean trickster_volume_start(TricksterVolume* self) {
  if (self->running) {
    return TRUE;
  }
  trickster_volume_init_once();
  self->loop = pw_thread_loop_new("trickster-volume", nullptr);
  if (self->loop == nullptr) {
    return FALSE;
  }
  self->context = pw_context_new(pw_thread_loop_get_loop(self->loop), nullptr,
                                 0);
  if (self->context == nullptr) {
    pw_thread_loop_destroy(self->loop);
    self->loop = nullptr;
    return FALSE;
  }
  if (pw_thread_loop_start(self->loop) < 0) {
    pw_context_destroy(self->context);
    self->context = nullptr;
    pw_thread_loop_destroy(self->loop);
    self->loop = nullptr;
    return FALSE;
  }
  pw_thread_loop_lock(self->loop);
  self->core = pw_context_connect(self->context, nullptr, 0);
  if (self->core != nullptr) {
    pw_core_add_listener(self->core, &self->core_listener,
                         &trickster_volume_core_events, self);
    self->registry = pw_core_get_registry(self->core, PW_VERSION_REGISTRY, 0);
    if (self->registry != nullptr) {
      pw_registry_add_listener(self->registry, &self->registry_listener,
                               &trickster_volume_registry_events, self);
    }
  }
  pw_thread_loop_unlock(self->loop);
  if (self->core == nullptr || self->registry == nullptr) {
    trickster_volume_stop(self);
    return FALSE;
  }
  self->running = TRUE;
  return TRUE;
}

void trickster_volume_stop(TricksterVolume* self) {
  if (self->loop != nullptr) {
    pw_thread_loop_stop(self->loop);
  }
  self->running = FALSE;
  g_mutex_lock(&self->mutex);
  const guint source = self->push_source;
  self->push_source = 0;
  self->has_volume = FALSE;
  self->has_route = FALSE;
  self->channels = 0;
  g_mutex_unlock(&self->mutex);
  if (source != 0) {
    g_source_remove(source);
  }
  if (self->core != nullptr) {
    pw_core_disconnect(self->core);
    self->core = nullptr;
    self->registry = nullptr;
    self->metadata = nullptr;
    self->node = nullptr;
    self->device = nullptr;
  }
  if (self->context != nullptr) {
    pw_context_destroy(self->context);
    self->context = nullptr;
  }
  if (self->loop != nullptr) {
    pw_thread_loop_destroy(self->loop);
    self->loop = nullptr;
  }
  self->device_id = 0;
  self->route_device = -1;
  g_hash_table_remove_all(self->sinks);
  g_clear_pointer(&self->default_sink, g_free);
}

void trickster_volume_set(TricksterVolume* self, gdouble value) {
  if (!self->running || self->loop == nullptr) {
    return;
  }
  const gdouble clamped = CLAMP(value, 0.0, 1.0);
  // WirePlumber's mixer API stores linear volumes: the cubic scale the user
  // sees cubes before it is written.
  const gfloat linear = (gfloat)(clamped * clamped * clamped);
  pw_thread_loop_lock(self->loop);
  g_mutex_lock(&self->mutex);
  const guint32 channels =
      CLAMP(self->channels, 1, TRICKSTER_VOLUME_MAX_CHANNELS);
  const gboolean has_route = self->has_route;
  const gint32 route_index = self->route_index;
  const gint32 route_device = self->route_device;
  g_mutex_unlock(&self->mutex);

  guint8 buffer[1024];
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
  if (has_route && self->device != nullptr) {
    spa_pod_frame route_frame;
    spa_pod_builder_push_object(&builder, &route_frame,
                                SPA_TYPE_OBJECT_ParamRoute, SPA_PARAM_Route);
    spa_pod_builder_prop(&builder, SPA_PARAM_ROUTE_index, 0);
    spa_pod_builder_int(&builder, route_index);
    spa_pod_builder_prop(&builder, SPA_PARAM_ROUTE_device, 0);
    spa_pod_builder_int(&builder, route_device);
    spa_pod_builder_prop(&builder, SPA_PARAM_ROUTE_props, 0);
    spa_pod_frame props_frame;
    spa_pod_builder_push_object(&builder, &props_frame, SPA_TYPE_OBJECT_Props,
                                SPA_PARAM_Props);
    spa_pod_builder_prop(&builder, SPA_PROP_channelVolumes, 0);
    spa_pod_frame array_frame;
    spa_pod_builder_push_array(&builder, &array_frame);
    for (guint32 i = 0; i < channels; i++) {
      spa_pod_builder_float(&builder, linear);
    }
    spa_pod_builder_pop(&builder, &array_frame);
    spa_pod_builder_pop(&builder, &props_frame);
    spa_pod_builder_prop(&builder, SPA_PARAM_ROUTE_save, 0);
    spa_pod_builder_bool(&builder, true);
    spa_pod* pod = (spa_pod*)spa_pod_builder_pop(&builder, &route_frame);
    pw_device_set_param(self->device, SPA_PARAM_Route, 0, pod);
  } else if (self->node != nullptr) {
    spa_pod_frame props_frame;
    spa_pod_builder_push_object(&builder, &props_frame, SPA_TYPE_OBJECT_Props,
                                SPA_PARAM_Props);
    spa_pod_builder_prop(&builder, SPA_PROP_channelVolumes, 0);
    spa_pod_frame array_frame;
    spa_pod_builder_push_array(&builder, &array_frame);
    for (guint32 i = 0; i < channels; i++) {
      spa_pod_builder_float(&builder, linear);
    }
    spa_pod_builder_pop(&builder, &array_frame);
    spa_pod* pod = (spa_pod*)spa_pod_builder_pop(&builder, &props_frame);
    pw_node_set_param(self->node, SPA_PARAM_Props, 0, pod);
  }
  pw_thread_loop_unlock(self->loop);
}

void trickster_volume_free(TricksterVolume* self) {
  trickster_volume_stop(self);
  g_clear_object(&self->channel);
  g_hash_table_unref(self->sinks);
  g_mutex_clear(&self->mutex);
  g_free(self);
}
