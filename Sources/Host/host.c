// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - the libretro player (see host.h). One core at a time; everything runs on the main thread
// except gv_audio_read, which the sound thread calls (a one-writer one-reader ring between them).
#include "host.h"
#include "libretro.h"
#include "host_gl.h"

#include <dlfcn.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void *lib;
static void (*p_init)(void);
static void (*p_deinit)(void);
static void (*p_set_environment)(retro_environment_t);
static void (*p_set_video_refresh)(retro_video_refresh_t);
static void (*p_set_audio_sample)(retro_audio_sample_t);
static void (*p_set_audio_sample_batch)(retro_audio_sample_batch_t);
static void (*p_set_input_poll)(retro_input_poll_t);
static void (*p_set_input_state)(retro_input_state_t);
static void (*p_get_system_info)(struct retro_system_info *);
static void (*p_get_system_av_info)(struct retro_system_av_info *);
static bool (*p_load_game)(const struct retro_game_info *);
static void (*p_unload_game)(void);
static void (*p_run)(void);
static void (*p_reset)(void);
static size_t (*p_serialize_size)(void);
static bool (*p_serialize)(void *, size_t);
static bool (*p_unserialize)(const void *, size_t);
static void *(*p_get_memory_data)(unsigned);
static size_t (*p_get_memory_size)(unsigned);

static char system_dir[1024], save_dir[1024];
static enum retro_pixel_format pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
static struct retro_system_av_info av;
static void *game_data;
static bool game_loaded;

static uint32_t *frame;
static unsigned frame_w, frame_h, frame_serial;
static size_t frame_cap;

static uint16_t buttons[4];
static int16_t analog[4][2][2];   // port, stick (left, right), axis (x, y)
static int16_t pointer_x, pointer_y, pointer_down;

// a core that draws with the GPU (SET_HW_RENDER): OpenGL ES, see host_gl.m
static struct retro_hw_render_callback hw;
static bool hw_on;
static uint8_t *hw_pixels;
static size_t hw_cap;

static uintptr_t hw_framebuffer(void) {
    return gv_gl_fbo();
}

static retro_proc_address_t hw_proc(const char *name) {
    return (retro_proc_address_t)gv_gl_proc(name);
}

// sound: one second of stereo samples
#define RING_FRAMES 65536
static int16_t ring[RING_FRAMES * 2];
static atomic_size_t ring_write, ring_read;

static void log_cb(enum retro_log_level level, const char *fmt, ...) {
    if (level < RETRO_LOG_WARN) return;
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[core] ");
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

// Core options Game Vault sets: no code may be made at run time on an iPhone without JIT, so every recompiler
// stays off. Anything not listed keeps the core's own default.
static const char *option(const char *key) {
    static const struct { const char *key, *value; } list[] = {
        {"pcsx_rearmed_drc", "disabled"},
        {"pcsx_rearmed_show_bios_bootlogo", "disabled"},
        {"mupen64plus-cpucore", "cached_interpreter"},
        {"genesis_plus_gx_bram", "per game"},
        {"mupen64plus-rdp-plugin", "gliden64"},
        {"mupen64plus-rsp-plugin", "hle"},
        {"ppsspp_cpu_core", "IR JIT"},
        {"ppsspp_internal_resolution", "960x544"},
        {"desmume_cpu_mode", "interpreter"},
        {"desmume_pointer_type", "touch"},
        {"mgba_sgb_borders", "OFF"},
    };
    for (size_t i = 0; i < sizeof(list) / sizeof(list[0]); i++)
        if (!strcmp(list[i].key, key)) return list[i].value;
    return NULL;
}

static bool environment(unsigned cmd, void *data) {
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        ((struct retro_log_callback *)data)->log = log_cb;
        return true;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
        *(bool *)data = true;
        return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
        *(const char **)data = system_dir;
        return true;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char **)data = save_dir;
        return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        enum retro_pixel_format f = *(const enum retro_pixel_format *)data;
        if (f != RETRO_PIXEL_FORMAT_0RGB1555 && f != RETRO_PIXEL_FORMAT_XRGB8888 && f != RETRO_PIXEL_FORMAT_RGB565)
            return false;
        pixel_format = f;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        struct retro_variable *v = data;
        v->value = v->key ? option(v->key) : NULL;
        return v->value != NULL;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE:
        *(bool *)data = false;
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:
        return true;
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
        *(unsigned *)data = 0;   // cores fall back to SET_VARIABLES, which needs nothing from us
        return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE:
        *(unsigned *)data = RETRO_LANGUAGE_ENGLISH;
        return true;
    case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE:
        *(int *)data = 3;
        return true;
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
        av.geometry = *(const struct retro_game_geometry *)data;
        return true;
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO:
        av = *(const struct retro_system_av_info *)data;
        return true;
    case RETRO_ENVIRONMENT_SET_VARIABLES:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
    case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL:
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
    case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY:
    case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS:
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
        return true;
    case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER:
        *(unsigned *)data = RETRO_HW_CONTEXT_OPENGLES3;
        return true;
    case RETRO_ENVIRONMENT_SET_HW_RENDER: {
        struct retro_hw_render_callback *cb = data;
        int major;
        if (cb->context_type == RETRO_HW_CONTEXT_OPENGLES3) major = 3;
        else if (cb->context_type == RETRO_HW_CONTEXT_OPENGLES2) major = 2;
        else if (cb->context_type == RETRO_HW_CONTEXT_OPENGLES_VERSION && cb->version_major <= 3) major = 3;
        else return false;   // desktop OpenGL / Vulkan: the core tries the next kind
        if (!hw_on && gv_gl_create(major) != 0) return false;
        cb->get_current_framebuffer = hw_framebuffer;
        cb->get_proc_address = hw_proc;
        hw = *cb;
        hw_on = true;
        return true;
    }
    default:
        return false;
    }
}

static void hw_frame(unsigned width, unsigned height);

static void video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (!data || !width || !height) return;   // a dupe: keep the last picture
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
        hw_frame(width, height);
        return;
    }
    if ((size_t)width * height > frame_cap) {
        frame_cap = (size_t)width * height;
        frame = realloc(frame, frame_cap * 4);
        if (!frame) {
            frame_cap = 0;
            return;
        }
    }
    for (unsigned y = 0; y < height; y++) {
        const uint8_t *row = (const uint8_t *)data + y * pitch;
        uint32_t *out = frame + (size_t)y * width;
        if (pixel_format == RETRO_PIXEL_FORMAT_XRGB8888) {
            memcpy(out, row, width * 4);
        } else if (pixel_format == RETRO_PIXEL_FORMAT_RGB565) {
            const uint16_t *in = (const uint16_t *)row;
            for (unsigned x = 0; x < width; x++) {
                uint16_t p = in[x];
                uint32_t r = (p >> 11) & 31, g = (p >> 5) & 63, b = p & 31;
                out[x] = ((r << 3 | r >> 2) << 16) | ((g << 2 | g >> 4) << 8) | (b << 3 | b >> 2);
            }
        } else {
            const uint16_t *in = (const uint16_t *)row;
            for (unsigned x = 0; x < width; x++) {
                uint16_t p = in[x];
                uint32_t r = (p >> 10) & 31, g = (p >> 5) & 31, b = p & 31;
                out[x] = ((r << 3 | r >> 2) << 16) | ((g << 3 | g >> 2) << 8) | (b << 3 | b >> 2);
            }
        }
    }
    frame_w = width;
    frame_h = height;
    frame_serial++;
}

// The GPU's picture back into the frame: RGBA bottom row first -> B G R X top row first.
static void hw_frame(unsigned width, unsigned height) {
    size_t n = (size_t)width * height;
    if (n * 4 > hw_cap) {
        hw_cap = n * 4;
        hw_pixels = realloc(hw_pixels, hw_cap);
        if (!hw_pixels) {
            hw_cap = 0;
            return;
        }
    }
    if (n > frame_cap) {
        frame_cap = n;
        frame = realloc(frame, frame_cap * 4);
        if (!frame) {
            frame_cap = 0;
            return;
        }
    }
    if (gv_gl_read(hw_pixels, (int)width, (int)height) != 0) return;
    for (unsigned y = 0; y < height; y++) {
        unsigned src_y = hw.bottom_left_origin ? height - 1 - y : y;
        const uint8_t *in = hw_pixels + (size_t)src_y * width * 4;
        uint32_t *out = frame + (size_t)y * width;
        for (unsigned x = 0; x < width; x++, in += 4)
            out[x] = (uint32_t)in[0] << 16 | (uint32_t)in[1] << 8 | in[2];
    }
    frame_w = width;
    frame_h = height;
    frame_serial++;
}

static size_t audio_batch(const int16_t *data, size_t frames) {
    size_t w = atomic_load_explicit(&ring_write, memory_order_relaxed);
    size_t r = atomic_load_explicit(&ring_read, memory_order_acquire);
    size_t room = RING_FRAMES - 1 - (w - r);
    if (frames > room) frames = room;   // the sound thread is behind: drop the newest
    for (size_t i = 0; i < frames; i++) {
        size_t at = ((w + i) % RING_FRAMES) * 2;
        ring[at] = data[i * 2];
        ring[at + 1] = data[i * 2 + 1];
    }
    atomic_store_explicit(&ring_write, w + frames, memory_order_release);
    return frames;
}

static void audio_sample(int16_t left, int16_t right) {
    int16_t s[2] = {left, right};
    audio_batch(s, 1);
}

static void input_poll(void) {}

static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port >= 4) return 0;
    device &= RETRO_DEVICE_MASK;
    if (device == RETRO_DEVICE_ANALOG) return index < 2 && id < 2 ? analog[port][index][id] : 0;
    if (device == RETRO_DEVICE_POINTER) {
        if (port != 0) return 0;
        if (id == RETRO_DEVICE_ID_POINTER_X) return pointer_x;
        if (id == RETRO_DEVICE_ID_POINTER_Y) return pointer_y;
        if (id == RETRO_DEVICE_ID_POINTER_PRESSED) return pointer_down;
        return 0;
    }
    if (device != RETRO_DEVICE_JOYPAD) return 0;
    if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)buttons[port];
    return id < 16 ? (buttons[port] >> id) & 1 : 0;
}

size_t gv_audio_read(int16_t *out, size_t frames) {
    size_t r = atomic_load_explicit(&ring_read, memory_order_relaxed);
    size_t w = atomic_load_explicit(&ring_write, memory_order_acquire);
    size_t have = w - r;
    if (frames > have) frames = have;
    for (size_t i = 0; i < frames; i++) {
        size_t at = ((r + i) % RING_FRAMES) * 2;
        out[i * 2] = ring[at];
        out[i * 2 + 1] = ring[at + 1];
    }
    atomic_store_explicit(&ring_read, r + frames, memory_order_release);
    return frames;
}

size_t gv_audio_queued(void) {
    return atomic_load(&ring_write) - atomic_load(&ring_read);
}

#define SYM(name)                                                   \
    do {                                                            \
        *(void **)&p_##name = dlsym(lib, "retro_" #name);           \
        if (!p_##name) {                                            \
            *error = "This emulator is damaged (retro_" #name ").";  \
            goto fail;                                              \
        }                                                           \
    } while (0)

static void *read_file(const char *path, size_t *size) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    void *buf = n > 0 ? malloc((size_t)n) : NULL;
    if (buf && fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf);
        buf = NULL;
    }
    fclose(f);
    *size = buf ? (size_t)n : 0;
    return buf;
}

int gv_load(const char *core_path, const char *game_path, const char *sys_dir, const char *sav_dir,
            const char **error) {
    gv_unload();
    snprintf(system_dir, sizeof system_dir, "%s", sys_dir);
    snprintf(save_dir, sizeof save_dir, "%s", sav_dir);
    pixel_format = RETRO_PIXEL_FORMAT_0RGB1555;
    memset(buttons, 0, sizeof buttons);
    memset(analog, 0, sizeof analog);
    pointer_down = 0;
    hw_on = false;
    memset(&hw, 0, sizeof hw);
    atomic_store(&ring_write, 0);
    atomic_store(&ring_read, 0);
    frame_w = frame_h = 0;

    lib = dlopen(core_path, RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        fprintf(stderr, "dlopen: %s\n", dlerror());
        *error = "The emulator for this game could not start.";
        return -1;
    }
    SYM(init);
    SYM(deinit);
    SYM(set_environment);
    SYM(set_video_refresh);
    SYM(set_audio_sample);
    SYM(set_audio_sample_batch);
    SYM(set_input_poll);
    SYM(set_input_state);
    SYM(get_system_info);
    SYM(get_system_av_info);
    SYM(load_game);
    SYM(unload_game);
    SYM(run);
    SYM(reset);
    SYM(serialize_size);
    SYM(serialize);
    SYM(unserialize);
    SYM(get_memory_data);
    SYM(get_memory_size);

    p_set_environment(environment);
    p_init();
    p_set_video_refresh(video_refresh);
    p_set_audio_sample(audio_sample);
    p_set_audio_sample_batch(audio_batch);
    p_set_input_poll(input_poll);
    p_set_input_state(input_state);

    struct retro_system_info info = {0};
    p_get_system_info(&info);
    struct retro_game_info game = {.path = game_path};
    if (!info.need_fullpath) {
        size_t size;
        game_data = read_file(game_path, &size);
        if (!game_data) {
            *error = "The game file could not be read.";
            p_deinit();
            goto fail;
        }
        game.data = game_data;
        game.size = size;
    }
    if (!p_load_game(&game)) {
        *error = "The emulator could not open this game. It may need a BIOS file in Game Vault's BIOS folder.";
        p_deinit();
        goto fail;
    }
    game_loaded = true;
    memset(&av, 0, sizeof av);
    p_get_system_av_info(&av);
    if (hw_on) {
        unsigned w = av.geometry.max_width ? av.geometry.max_width : 1024;
        unsigned h = av.geometry.max_height ? av.geometry.max_height : 1024;
        if (gv_gl_framebuffer((int)w, (int)h, hw.depth, hw.stencil) != 0) {
            *error = "This phone's graphics could not be set up for this game.";
            p_unload_game();
            game_loaded = false;
            p_deinit();
            gv_gl_destroy();
            hw_on = false;
            goto fail;
        }
        if (hw.context_reset) hw.context_reset();
    }
    return 0;

fail:
    if (hw_on) gv_gl_destroy();
    hw_on = false;
    free(game_data);
    game_data = NULL;
    dlclose(lib);
    lib = NULL;
    return -1;
}

void gv_run(void) {
    if (!game_loaded) return;
    if (hw_on) gv_gl_current();
    p_run();
}

void gv_reset(void) {
    if (game_loaded) p_reset();
}

void gv_unload(void) {
    if (!lib) return;
    if (hw_on) {
        gv_gl_current();
        if (game_loaded && hw.context_destroy) hw.context_destroy();
    }
    if (game_loaded) p_unload_game();
    game_loaded = false;
    p_deinit();
    if (hw_on) gv_gl_destroy();
    hw_on = false;
    dlclose(lib);
    lib = NULL;
    free(game_data);
    game_data = NULL;
}

double gv_fps(void) {
    return av.timing.fps > 1 ? av.timing.fps : 60.0;
}

double gv_sample_rate(void) {
    return av.timing.sample_rate > 1000 ? av.timing.sample_rate : 44100.0;
}

float gv_aspect(void) {
    if (av.geometry.aspect_ratio > 0) return av.geometry.aspect_ratio;
    if (av.geometry.base_width && av.geometry.base_height)
        return (float)av.geometry.base_width / (float)av.geometry.base_height;
    return 4.0f / 3.0f;
}

const uint32_t *gv_frame(unsigned *width, unsigned *height, unsigned *serial) {
    *width = frame_w;
    *height = frame_h;
    *serial = frame_serial;
    return frame;
}

void gv_set_buttons(unsigned port, uint16_t mask) {
    if (port < 4) buttons[port] = mask;
}

void gv_set_analog(unsigned port, unsigned stick, int16_t x, int16_t y) {
    if (port < 4 && stick < 2) {
        analog[port][stick][0] = x;
        analog[port][stick][1] = y;
    }
}

void gv_set_pointer(int16_t x, int16_t y, int down) {
    pointer_x = x;
    pointer_y = y;
    pointer_down = down ? 1 : 0;
}

static int write_file(const char *path, const void *data, size_t size) {
    char tmp[1100];
    snprintf(tmp, sizeof tmp, "%s.tmp", path);
    FILE *f = fopen(tmp, "wb");
    if (!f) return -1;
    bool ok = fwrite(data, 1, size, f) == size;
    ok = fclose(f) == 0 && ok;
    if (!ok || rename(tmp, path) != 0) {
        remove(tmp);
        return -1;
    }
    return 0;
}

int gv_save_sram(const char *path) {
    if (!game_loaded) return -1;
    void *data = p_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    size_t size = p_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    if (!data || !size) return 0;   // the game has no battery save
    return write_file(path, data, size);
}

int gv_load_sram(const char *path) {
    if (!game_loaded) return -1;
    void *data = p_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    size_t size = p_get_memory_size(RETRO_MEMORY_SAVE_RAM), n;
    if (!data || !size) return 0;
    void *file = read_file(path, &n);
    if (!file) return -1;
    memcpy(data, file, n < size ? n : size);
    free(file);
    return 0;
}

int gv_save_state(const char *path) {
    if (!game_loaded) return -1;
    size_t size = p_serialize_size();
    if (!size) return -1;
    void *buf = malloc(size);
    int rc = buf && p_serialize(buf, size) ? write_file(path, buf, size) : -1;
    free(buf);
    return rc;
}

int gv_load_state(const char *path) {
    if (!game_loaded) return -1;
    size_t n;
    void *buf = read_file(path, &n);
    if (!buf) return -1;
    int rc = p_unserialize(buf, n) ? 0 : -1;
    free(buf);
    return rc;
}
