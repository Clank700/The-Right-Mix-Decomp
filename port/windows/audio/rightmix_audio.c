/* Tiny sound layer for The Right Mix (Windows): miniaudio engine + a handle table, called from Dart via FFI. */
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#define RA_EXPORT __declspec(dllexport)
#define RA_MAX_SOUNDS 64

static ma_engine g_engine;
static int g_engine_ready = 0;
static ma_sound g_sounds[RA_MAX_SOUNDS];
static int g_loaded[RA_MAX_SOUNDS];
static int g_count = 0;

RA_EXPORT int ra_init(void) {
  if (g_engine_ready) return 0;
  ma_engine_config cfg = ma_engine_config_init();
  cfg.periodSizeInMilliseconds = 10; /* small mixing buffers: sound starts within ~one period of the request */
  if (ma_engine_init(&cfg, &g_engine) != MA_SUCCESS) return -1;
  g_engine_ready = 1;
  return 0;
}

/* Returns a handle >= 0, or -1 on failure. `path` is UTF-16. */
RA_EXPORT int ra_load(const wchar_t* path) {
  if (!g_engine_ready || g_count >= RA_MAX_SOUNDS) return -1;
  int h = g_count;
  if (ma_sound_init_from_file_w(&g_engine, path, MA_SOUND_FLAG_DECODE, NULL, NULL, &g_sounds[h]) != MA_SUCCESS) return -1;
  g_loaded[h] = 1;
  g_count++;
  return h;
}

RA_EXPORT void ra_play(int h, double offset_seconds, int loop) {
  if (h < 0 || h >= g_count || !g_loaded[h]) return;
  ma_sound* s = &g_sounds[h];
  ma_sound_stop(s);
  ma_uint32 rate = 0;
  ma_sound_get_data_format(s, NULL, NULL, &rate, NULL, 0);
  ma_sound_seek_to_pcm_frame(s, (ma_uint64)(offset_seconds * (double)rate));
  ma_sound_set_looping(s, loop ? MA_TRUE : MA_FALSE);
  ma_sound_start(s);
}

RA_EXPORT void ra_stop(int h) {
  if (h < 0 || h >= g_count || !g_loaded[h]) return;
  ma_sound_stop(&g_sounds[h]);
}

RA_EXPORT void ra_volume(int h, float v) {
  if (h < 0 || h >= g_count || !g_loaded[h]) return;
  ma_sound_set_volume(&g_sounds[h], v);
}

RA_EXPORT int ra_is_playing(int h) {
  if (h < 0 || h >= g_count || !g_loaded[h]) return 0;
  return ma_sound_is_playing(&g_sounds[h]) ? 1 : 0;
}

/* Output buffering the engine is running with, in milliseconds (period size x period count / sample rate). */
RA_EXPORT double ra_latency_ms(void) {
  if (!g_engine_ready) return -1;
  ma_device* d = ma_engine_get_device(&g_engine);
  if (!d || d->playback.internalSampleRate == 0) return -1;
  return 1000.0 * (double)d->playback.internalPeriodSizeInFrames * (double)d->playback.internalPeriods /
         (double)d->playback.internalSampleRate;
}
