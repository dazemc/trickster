#include "pipewire_capture.h"

#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/param/audio/raw.h>
#include <spa/pod/builder.h>
#include <spa/utils/result.h>

// Delivery cadence. PipeWire's quantum lands at ~21 ms, so the pump coalesces
// one or two periods per call; the Dart side resamples to display rate.
#define TRICKSTER_PUMP_MS 33

struct _TricksterCapture {
  FlMethodChannel* channel;
  pw_thread_loop* loop;
  pw_stream* stream;
  GMutex mutex;
  GByteArray* pending;
  guint pump;
  gint rate;
  gint channels;
  gboolean running;
};

static void trickster_capture_process(void* data) {
  TricksterCapture* self = (TricksterCapture*)data;
  pw_buffer* buffer = pw_stream_dequeue_buffer(self->stream);
  if (buffer == nullptr) {
    return;
  }
  spa_buffer* spa = buffer->buffer;
  if (spa != nullptr && spa->n_datas > 0) {
    spa_data* data = &spa->datas[0];
    if (data->data != nullptr && data->chunk != nullptr &&
        data->chunk->size > 0) {
      g_mutex_lock(&self->mutex);
      g_byte_array_append(self->pending, (const guint8*)data->data,
                          data->chunk->size);
      g_mutex_unlock(&self->mutex);
    }
  }
  pw_stream_queue_buffer(self->stream, buffer);
}

static void trickster_capture_param_changed(void* data, uint32_t id,
                                            const spa_pod* param) {
  if (param == nullptr || id != SPA_PARAM_Format) {
    return;
  }
  spa_audio_info_raw info = {};
  if (spa_format_audio_raw_parse(param, &info) < 0) {
    return;
  }
  TricksterCapture* self = (TricksterCapture*)data;
  g_mutex_lock(&self->mutex);
  if (info.rate > 0) {
    self->rate = (gint)info.rate;
  }
  if (info.channels > 0) {
    self->channels = (gint)info.channels;
  }
  g_mutex_unlock(&self->mutex);
}

static void trickster_capture_state_changed(void* data,
                                            enum pw_stream_state old,
                                            enum pw_stream_state state,
                                            const char* error) {
  if (state == PW_STREAM_STATE_ERROR) {
    g_warning("trickster: pipewire capture error: %s",
              error != nullptr ? error : "unknown");
  }
}

static const pw_stream_events trickster_capture_events = {
    .version = PW_VERSION_STREAM_EVENTS,
    .state_changed = trickster_capture_state_changed,
    .param_changed = trickster_capture_param_changed,
    .process = trickster_capture_process,
};

// Answers the Dart capture lifecycle on the channel that also carries frames.
static void trickster_capture_method_call(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  TricksterCapture* self = (TricksterCapture*)user_data;
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "pipewireStart") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(trickster_capture_start(self) ? TRUE : FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "pipewireStop") == 0) {
    trickster_capture_stop(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Delivers the accumulated PCM as one frame map. Runs on the main thread, so
// the stream can be stopped without racing this callback.
static gboolean trickster_capture_pump(gpointer data) {
  TricksterCapture* self = (TricksterCapture*)data;
  g_mutex_lock(&self->mutex);
  GByteArray* batch = self->pending;
  self->pending = g_byte_array_new();
  const gint rate = self->rate;
  const gint channels = self->channels;
  g_mutex_unlock(&self->mutex);
  if (batch->len > 0) {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(
        args, "data", fl_value_new_uint8_list(batch->data, batch->len));
    fl_value_set_string_take(args, "rate", fl_value_new_int(rate));
    fl_value_set_string_take(args, "channels", fl_value_new_int(channels));
    fl_method_channel_invoke_method(self->channel, "frame", args, nullptr,
                                    nullptr, nullptr);
  }
  g_byte_array_unref(batch);
  return self->running ? G_SOURCE_CONTINUE : G_SOURCE_REMOVE;
}

static void trickster_capture_init_once(void) {
  static gsize once = 0;
  if (g_once_init_enter(&once)) {
    pw_init(nullptr, nullptr);
    g_once_init_leave(&once, 1);
  }
}

TricksterCapture* trickster_capture_new(FlBinaryMessenger* messenger) {
  TricksterCapture* self = g_new0(TricksterCapture, 1);
  g_mutex_init(&self->mutex);
  self->pending = g_byte_array_new();
  self->rate = 48000;
  self->channels = 2;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger,
                                        "org.trickster.bar/pipewire",
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel,
                                            trickster_capture_method_call,
                                            self, nullptr);
  return self;
}

// Connects the stream to the default sink's monitor. The format pod is built
// per call: PipeWire copies it during connect, so the buffer only has to
// outlive this function.
static gint trickster_capture_connect(TricksterCapture* self) {
  guint8 pod_buffer[1024];
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(pod_buffer,
                                                 sizeof(pod_buffer));
  spa_audio_info_raw info = {};
  info.format = SPA_AUDIO_FORMAT_F32;
  info.channels = 2;
  info.rate = 48000;
  const spa_pod* params[1] = {
      spa_format_audio_raw_build(&builder, SPA_PARAM_EnumFormat, &info),
  };
  return pw_stream_connect(
      self->stream, PW_DIRECTION_INPUT, PW_ID_ANY,
      (enum pw_stream_flags)(PW_STREAM_FLAG_AUTOCONNECT |
                             PW_STREAM_FLAG_MAP_BUFFERS),
      params, 1);
}

// Disconnects and destroys the stream. A stream is never reconnected: a fresh
// one per start keeps the negotiate state clean across play/pause edges.
static void trickster_capture_drop_stream(TricksterCapture* self) {
  if (self->stream == nullptr) {
    return;
  }
  pw_thread_loop_lock(self->loop);
  pw_stream_disconnect(self->stream);
  pw_thread_loop_unlock(self->loop);
  pw_thread_loop_stop(self->loop);
  pw_stream_destroy(self->stream);
  self->stream = nullptr;
}

gboolean trickster_capture_start(TricksterCapture* self) {
  if (self->running) {
    return TRUE;
  }
  trickster_capture_init_once();
  if (self->loop == nullptr) {
    self->loop = pw_thread_loop_new("trickster-capture", nullptr);
    if (self->loop == nullptr) {
      return FALSE;
    }
  }
  if (self->stream == nullptr) {
    pw_properties* props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_STREAM_CAPTURE_SINK, "true", PW_KEY_NODE_NAME,
        "trickster-visualizer", PW_KEY_APP_NAME, "Trickster",
        PW_KEY_NODE_DESCRIPTION, "Trickster visualizer", nullptr);
    self->stream = pw_stream_new_simple(pw_thread_loop_get_loop(self->loop),
                                        "trickster-visualizer", props,
                                        &trickster_capture_events, self);
    if (self->stream == nullptr) {
      return FALSE;
    }
  }
  pw_thread_loop_start(self->loop);
  pw_thread_loop_lock(self->loop);
  const gint result = trickster_capture_connect(self);
  pw_thread_loop_unlock(self->loop);
  if (result < 0) {
    g_warning("trickster: pipewire stream connect failed: %s",
              spa_strerror(result));
    trickster_capture_drop_stream(self);
    return FALSE;
  }
  self->running = TRUE;
  self->pump = g_timeout_add(TRICKSTER_PUMP_MS, trickster_capture_pump, self);
  return TRUE;
}

void trickster_capture_stop(TricksterCapture* self) {
  self->running = FALSE;
  if (self->pump != 0) {
    g_source_remove(self->pump);
    self->pump = 0;
  }
  trickster_capture_drop_stream(self);
  g_mutex_lock(&self->mutex);
  g_byte_array_set_size(self->pending, 0);
  g_mutex_unlock(&self->mutex);
}

void trickster_capture_free(TricksterCapture* self) {
  trickster_capture_stop(self);
  if (self->loop != nullptr) {
    pw_thread_loop_destroy(self->loop);
    self->loop = nullptr;
  }
  g_clear_object(&self->channel);
  g_mutex_clear(&self->mutex);
  g_byte_array_unref(self->pending);
  g_free(self);
}
