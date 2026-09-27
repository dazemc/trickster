#ifndef TRICKSTER_PIPEWIRE_CAPTURE_H_
#define TRICKSTER_PIPEWIRE_CAPTURE_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

typedef struct _TricksterCapture TricksterCapture;

// Creates a capture that delivers raw F32 interleaved PCM as "frame" calls
// on the org.trickster.bar/pipewire channel of [messenger]. The stream is
// created lazily by trickster_capture_start.
TricksterCapture* trickster_capture_new(FlBinaryMessenger* messenger);

// Opens the default sink's monitor and pumps PCM to Dart at ~30 Hz. Returns
// FALSE when PipeWire is unavailable or the stream cannot connect; the
// object stays reusable after a failure.
gboolean trickster_capture_start(TricksterCapture* capture);

// Stops the stream and the pump. Safe to call when not running.
void trickster_capture_stop(TricksterCapture* capture);

// Stops and frees everything; the object must not be used afterwards.
void trickster_capture_free(TricksterCapture* capture);

G_END_DECLS

#endif  // TRICKSTER_PIPEWIRE_CAPTURE_H_
