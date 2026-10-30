// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the small libretro player the app is built around: loads one core (a framework in the
// app), one game, runs a frame at a time and hands the picture and sound to Swift.
#ifndef GV_HOST_H
#define GV_HOST_H

#include <stddef.h>
#include <stdint.h>

// 0 = started; else *error says why (a sentence for the player)
int gv_load(const char *core_path, const char *game_path, const char *system_dir, const char *save_dir,
            const char **error);
void gv_run(void);   // one frame
void gv_reset(void);
void gv_unload(void);

double gv_fps(void);
double gv_sample_rate(void);
float gv_aspect(void);
// The last picture as 32-bit pixels (B,G,R,X in memory); changes serial when a new one came.
const uint32_t *gv_frame(unsigned *width, unsigned *height, unsigned *serial);

void gv_set_buttons(unsigned port, uint16_t mask);   // bit n = RETRO_DEVICE_ID_JOYPAD n
void gv_set_analog(unsigned port, unsigned stick, int16_t x, int16_t y);   // stick 0 left, 1 right; y down = +
void gv_set_pointer(int16_t x, int16_t y, int down);   // -32767..32767 over the whole picture
size_t gv_audio_read(int16_t *out, size_t frames);   // stereo, interleaved; called from the sound thread
size_t gv_audio_queued(void);

int gv_save_sram(const char *path);
int gv_load_sram(const char *path);
int gv_save_state(const char *path);
int gv_load_state(const char *path);

#endif
