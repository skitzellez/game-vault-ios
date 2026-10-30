// Copyright (c) 2026 Skitzelles - part of Game Vault, https://github.com/skitzellez/xbox-game-vault
// PolyForm Noncommercial License 1.0.0: not for sale, and this notice stays in every copy.
// Game Vault for iPhone - OpenGL ES for cores that draw with the GPU (host_gl.m).
#ifndef GV_HOST_GL_H
#define GV_HOST_GL_H

int gv_gl_create(int major);
int gv_gl_framebuffer(int width, int height, int depth, int stencil);
void gv_gl_current(void);
unsigned gv_gl_fbo(void);
void *gv_gl_proc(const char *name);
int gv_gl_read(void *rgba, int width, int height);   // bottom row first, R G B A
void gv_gl_destroy(void);

#endif
