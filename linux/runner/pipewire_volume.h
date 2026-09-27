#ifndef TRICKSTER_PIPEWIRE_VOLUME_H_
#define TRICKSTER_PIPEWIRE_VOLUME_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

typedef struct _TricksterVolume TricksterVolume;

// Creates a volume watcher that reports the default sink's level as
// "volume" calls on the org.trickster.bar/volume channel of [messenger].
TricksterVolume* trickster_volume_new(FlBinaryMessenger* messenger);

// Connects to PipeWire, follows WirePlumber's default sink, and pushes the
// first reading. Returns FALSE when the connection fails.
gboolean trickster_volume_start(TricksterVolume* volume);

// Disconnects and stops pushing. Safe to call when not running.
void trickster_volume_stop(TricksterVolume* volume);

// Sets every channel of the current default sink to [value] (0..1).
void trickster_volume_set(TricksterVolume* volume, gdouble value);

// Stops and frees everything; the object must not be used afterwards.
void trickster_volume_free(TricksterVolume* volume);

G_END_DECLS

#endif  // TRICKSTER_PIPEWIRE_VOLUME_H_
